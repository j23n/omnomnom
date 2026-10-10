import Foundation
import SwiftData
import Testing
@testable import Omnomnom

/// Tags and the Library search that reads them, against an in-memory store with the
/// app's schema.
struct TagTests {
    private func recipe(_ name: String, in context: ModelContext) -> Recipe {
        let recipe = Recipe(name: name, servings: 2)
        context.insert(recipe)
        return recipe
    }

    private func food(_ name: String, in context: ModelContext) -> Food {
        let food = Food(name: name, kind: .custom, bundledID: nil, per100g: Nutrition(energy: 100))
        context.insert(food)
        return food
    }

    @Test func namedReusesAnExistingTagWhateverTheCasing() throws {
        let context = try TestStore.context()
        let first = try #require(try Tag.named("Breakfast", in: context))
        let again = try #require(try Tag.named("  breakfast ", in: context))
        #expect(first === again)
        #expect(first.name == "Breakfast")
        #expect(try context.fetchCount(FetchDescriptor<Omnomnom.Tag>()) == 1)
    }

    @Test func namedRefusesABlankName() throws {
        let context = try TestStore.context()
        #expect(try Tag.named("   ", in: context) == nil)
        #expect(try context.fetchCount(FetchDescriptor<Omnomnom.Tag>()) == 0)
    }

    @Test func aTagCountsEverythingThatCarriesIt() throws {
        let context = try TestStore.context()
        let tag = try #require(try Tag.named("breakfast", in: context))
        let porridge = recipe("Overnight oats", in: context)
        let granola = food("Homemade granola", in: context)
        porridge.tags = [tag]
        granola.tags = [tag]
        try context.save()
        #expect(tag.itemCount == 2)
        #expect(tag.isOrphaned == false)
    }

    @Test func orphansAreRemovedAndUsedTagsAreKept() throws {
        let context = try TestStore.context()
        let used = try #require(try Tag.named("breakfast", in: context))
        _ = try Tag.named("abandoned", in: context)
        recipe("Overnight oats", in: context).tags = [used]
        try context.save()

        try Tag.removeOrphans(in: context)
        try context.save()
        #expect(try Tag.all(in: context).map(\.name) == ["breakfast"])
    }

    @Test func removingTheLastUseLeavesAnOrphanToCollect() throws {
        let context = try TestStore.context()
        let tag = try #require(try Tag.named("breakfast", in: context))
        let porridge = recipe("Overnight oats", in: context)
        porridge.tags = [tag]
        try context.save()

        porridge.tags = []
        try Tag.removeOrphans(in: context)
        try context.save()
        #expect(try Tag.all(in: context).isEmpty)
    }

    @Test func searchFindsByNameAndByTag() throws {
        let context = try TestStore.context()
        let breakfast = try #require(try Tag.named("breakfast", in: context))
        let porridge = recipe("Overnight oats", in: context)
        porridge.tags = [breakfast]
        let omelette = recipe("Omelette", in: context)
        let granola = food("Homemade granola", in: context)
        granola.tags = [breakfast]
        _ = food("Sourdough bread", in: context)
        try context.save()

        #expect(try LibrarySearch.recipes(matching: "breakfast", in: context).map(\.name) == ["Overnight oats"])
        #expect(try LibrarySearch.foods(matching: "breakfast", in: context).map(\.name) == ["Homemade granola"])
        #expect(try LibrarySearch.recipes(matching: "omelette", in: context).map(\.name) == [omelette.name])
        #expect(try LibrarySearch.foods(matching: "bread", in: context).map(\.name) == ["Sourdough bread"])
    }

    @Test func aRowMatchingBothItsNameAndATagAppearsOnce() throws {
        let context = try TestStore.context()
        let tag = try #require(try Tag.named("oats", in: context))
        recipe("Overnight oats", in: context).tags = [tag]
        try context.save()
        #expect(try LibrarySearch.recipes(matching: "oats", in: context).count == 1)
    }

    @Test func searchIsSortedByName() throws {
        let context = try TestStore.context()
        let tag = try #require(try Tag.named("breakfast", in: context))
        recipe("Porridge", in: context).tags = [tag]
        recipe("Croissant", in: context).tags = [tag]
        recipe("Breakfast burrito", in: context)
        try context.save()
        #expect(try LibrarySearch.recipes(matching: "breakfast", in: context).map(\.name)
            == ["Breakfast burrito", "Croissant", "Porridge"])
    }
}
