import Foundation
import SwiftData
import Testing
@testable import Omnomnom

/// The `Photo` row and its links, against an in-memory store with the app's schema.
struct PhotoTests {
    private let bytes = Data([0xFF, 0xD8, 0x01, 0x02, 0x03])
    private let otherBytes = Data([0xFF, 0xD8, 0x09, 0x08])

    private func makeContext() throws -> ModelContext {
        let schema = Schema([Food.self, LogEntry.self, Recipe.self, RecipeIngredient.self, Photo.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        return ModelContext(container)
    }

    private func photoCount(in context: ModelContext) throws -> Int {
        try context.fetchCount(FetchDescriptor<Photo>())
    }

    private func entry(_ name: String, in context: ModelContext) -> LogEntry {
        let entry = LogEntry(timestamp: .now, mealSlot: .lunch, foodName: name, grams: 100, snapshot: Nutrition(energy: 100))
        context.insert(entry)
        return entry
    }

    @Test func replacingInsertsKeepsAndDeletes() throws {
        let context = try makeContext()
        let recipe = Recipe(name: "Soup", servings: 2)
        context.insert(recipe)

        recipe.photo = Photo.replacing(recipe.photo, with: bytes, in: context)
        try context.save()
        #expect(recipe.photo?.data == bytes)
        #expect(recipe.photo?.recipe?.id == recipe.id)
        #expect(try photoCount(in: context) == 1)

        let same = recipe.photo
        recipe.photo = Photo.replacing(recipe.photo, with: bytes, in: context)
        try context.save()
        #expect(recipe.photo === same)
        #expect(try photoCount(in: context) == 1)

        recipe.photo = Photo.replacing(recipe.photo, with: otherBytes, in: context)
        try context.save()
        #expect(recipe.photo?.data == otherBytes)
        #expect(try photoCount(in: context) == 1)

        recipe.photo = Photo.replacing(recipe.photo, with: nil, in: context)
        try context.save()
        #expect(recipe.photo == nil)
        #expect(try photoCount(in: context) == 0)
    }

    @Test func deletingARecipeOrFoodTakesItsPhotoAlong() throws {
        let context = try makeContext()
        let recipe = Recipe(name: "Soup", servings: 2)
        context.insert(recipe)
        recipe.photo = Photo.replacing(nil, with: bytes, in: context)
        let food = Food(name: "Granola", kind: .custom, bundledID: nil, per100g: Nutrition(energy: 450))
        context.insert(food)
        food.photo = Photo.replacing(nil, with: otherBytes, in: context)
        try context.save()
        #expect(try photoCount(in: context) == 2)

        context.delete(recipe)
        try context.save()
        #expect(try photoCount(in: context) == 1)

        context.delete(food)
        try context.save()
        #expect(try photoCount(in: context) == 0)
    }

    @Test func entriesOfOneEstimateShareThePhotoUntilTheLastIsDeleted() throws {
        let context = try makeContext()
        let eggs = entry("Scrambled eggs", in: context)
        let toast = entry("Rye toast", in: context)
        let photo = Photo(data: bytes)
        context.insert(photo)
        eggs.photo = photo
        toast.photo = photo
        try context.save()
        #expect(Set((photo.entries ?? []).map(\.id)) == [eggs.id, toast.id])

        eggs.releasePhoto(in: context)
        context.delete(eggs)
        try context.save()
        #expect(try photoCount(in: context) == 1)
        #expect(toast.photo?.data == bytes)

        toast.releasePhoto(in: context)
        context.delete(toast)
        try context.save()
        #expect(try photoCount(in: context) == 0)
    }

    @Test func releasingAnEntryWithoutItsOwnPhotoLeavesTheRecipesAlone() throws {
        let context = try makeContext()
        let recipe = Recipe(name: "Soup", servings: 2)
        context.insert(recipe)
        recipe.photo = Photo.replacing(nil, with: bytes, in: context)
        let served = entry("Soup", in: context)
        served.recipe = recipe
        try context.save()

        served.releasePhoto(in: context)
        context.delete(served)
        try context.save()
        #expect(try photoCount(in: context) == 1)
        #expect(recipe.photo?.data == bytes)
    }

    @Test func displayPhotoPrefersOwnThenRecipeThenFood() throws {
        let context = try makeContext()
        let recipe = Recipe(name: "Soup", servings: 2)
        context.insert(recipe)
        recipe.photo = Photo.replacing(nil, with: bytes, in: context)
        let food = Food(name: "Granola", kind: .custom, bundledID: nil, per100g: Nutrition(energy: 450))
        context.insert(food)
        food.photo = Photo.replacing(nil, with: otherBytes, in: context)

        let plain = entry("Apple", in: context)
        #expect(plain.displayPhoto == nil)

        let fromFood = entry("Granola", in: context)
        fromFood.food = food
        #expect(fromFood.displayPhoto?.data == otherBytes)

        let fromRecipe = entry("Soup", in: context)
        fromRecipe.recipe = recipe
        #expect(fromRecipe.displayPhoto?.data == bytes)

        let own = Data([0x01])
        let estimated = entry("Eggs", in: context)
        estimated.recipe = recipe
        let ownPhoto = Photo(data: own)
        context.insert(ownPhoto)
        estimated.photo = ownPhoto
        #expect(estimated.displayPhoto?.data == own)
        try context.save()
    }

    @Test func recipeWriterRoundTripsThePhoto() throws {
        let context = try makeContext()
        let writer = RecipeWriter(context: context)
        var draft = RecipeDraft()
        draft.name = "Porridge"
        draft.add(FoodChoice(source: .bundled(id: 1), name: "Oats", perUnit: Nutrition(energy: 389)))
        draft.photo = bytes
        try writer.write(draft, into: nil)

        let recipe = try #require(try Recipe.matching("Porridge", in: context).first)
        #expect(recipe.photo?.data == bytes)
        #expect(RecipeWriter.draft(of: recipe).photo == bytes)
        #expect(recipe.choice.photo == bytes)
        #expect(try photoCount(in: context) == 1)

        var edited = RecipeWriter.draft(of: recipe)
        edited.photo = nil
        try writer.write(edited, into: recipe)
        #expect(recipe.photo == nil)
        #expect(recipe.choice.photo == nil)
        #expect(try photoCount(in: context) == 0)
    }

    @Test func foodChoiceCarriesTheFoodsPhoto() throws {
        let context = try makeContext()
        let food = Food(name: "Granola", kind: .custom, bundledID: nil, per100g: Nutrition(energy: 450))
        context.insert(food)
        #expect(food.choice?.photo == nil)
        food.photo = Photo.replacing(nil, with: bytes, in: context)
        try context.save()
        #expect(food.choice?.photo == bytes)
    }
}
