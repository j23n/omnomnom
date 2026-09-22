#if DEBUG
import CoreGraphics
import Foundation
import os
import SwiftData

/// Which rows a preview container starts with. Every seed but `yesterdayOnly` uses
/// today's date so the Today screen shows them without navigating; times are 08:10,
/// 12:40, 15:30 and 19:15.
nonisolated enum PreviewSeed: Hashable, Sendable {
    /// Nothing at all: no foods, no entries, no recipes.
    case empty
    /// Nothing today, but oats and an apple logged yesterday, so Today offers to copy them.
    case yesterdayOnly
    /// The first thing ever logged: one banana at breakfast, synced.
    case firstRun
    /// Oats and a glass of oat drink, measured in millilitres, at breakfast plus two
    /// estimated items sharing a photo of the plate, chicken and rice at lunch, an apple
    /// as a snack, and 1.5 servings of a lentil soup recipe at dinner; everything synced
    /// to Health.
    case typicalDay
    /// One entry per `HealthState`, plus an estimated entry and a product fetched from
    /// Open Food Facts, so every badge Today can show is on screen at once.
    case healthStates
    /// Three recipes with ingredients, four custom foods and two products; the first
    /// recipe has been logged once so its editor shows the "previously logged" footnote,
    /// and the lentil soup and the Greek yogurt carry a photo.
    case library
}

/// In-memory SwiftData containers for previews, seeded with realistic rows. Bundled
/// ids are illustrative: they match the test fixture (1 apple, 2 banana, 3 chicken,
/// 4 milk, 5 rice) and point at whatever row carries that id in a real build.
@MainActor
enum PreviewStore {
    /// The same schema the app opens.
    static let schema = Schema([Food.self, LogEntry.self, Recipe.self, RecipeIngredient.self, Photo.self])

    static func container(seed: PreviewSeed = .typicalDay) -> ModelContainer {
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        // Preview-only: an in-memory container has no fallback, and a crash here shows
        // in the canvas rather than in the app. Nowhere else may use `try!`.
        let container = try! ModelContainer(for: schema, configurations: [configuration])
        let seeder = Seeder(context: container.mainContext)
        seeder.apply(seed)
        do {
            try container.mainContext.save()
        } catch {
            AppLog.store.error("preview seed failed: \(error.localizedDescription, privacy: .public)")
        }
        return container
    }

    /// Every entry in the container, oldest first.
    static func entries(in container: ModelContainer) -> [LogEntry] {
        let descriptor = FetchDescriptor<LogEntry>(sortBy: [SortDescriptor(\LogEntry.timestamp)])
        return (try? container.mainContext.fetch(descriptor)) ?? []
    }

    /// The first entry in `state`, if the seed holds one.
    static func entry(in container: ModelContainer, state: HealthState) -> LogEntry? {
        entries(in: container).first { $0.healthState == state }
    }

    /// The first entry the seed holds, if any.
    static func firstEntry(in container: ModelContainer) -> LogEntry? {
        entries(in: container).first
    }

    /// Recipes by name.
    static func recipes(in container: ModelContainer) -> [Recipe] {
        let descriptor = FetchDescriptor<Recipe>(sortBy: [SortDescriptor(\Recipe.name)])
        return (try? container.mainContext.fetch(descriptor)) ?? []
    }

    /// Foods by name, every kind.
    static func foods(in container: ModelContainer) -> [Food] {
        let descriptor = FetchDescriptor<Food>(sortBy: [SortDescriptor(\Food.name)])
        return (try? container.mainContext.fetch(descriptor)) ?? []
    }

    /// The first food of `kind`, if the seed holds one.
    static func food(in container: ModelContainer, kind: FoodKind) -> Food? {
        foods(in: container).first { $0.kind == kind }
    }

    // MARK: A photo, drawn rather than bundled

    /// A 600 x 400 two-colour JPEG standing in for a photo of a plate: a warm
    /// background with a pale disc, so thumbnails and the viewer have something to show.
    static let samplePhoto: Data = drawSamplePhoto()

    private nonisolated static func drawSamplePhoto() -> Data {
        let width = 600
        let height = 400
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return Data() }
        context.setFillColor(red: 0.78, green: 0.47, blue: 0.29, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(red: 0.96, green: 0.93, blue: 0.86, alpha: 1)
        context.fillEllipse(in: CGRect(x: 140, y: 40, width: 320, height: 320))
        guard let image = context.makeImage(), let data = PhotoData.jpegData(image, quality: 0.8) else { return Data() }
        return data
    }

    // MARK: Choices for the Quantity sheet and search results, no store needed

    /// A bundled apple, never logged before; portions come from the bundled database.
    static let bundledChoice = FoodChoice(
        source: .bundled(id: 1), name: PreviewFoods.apple.name, perUnit: PreviewFoods.apple.per100g
    )

    /// A custom food logged before at 150 g.
    static let customChoice = FoodChoice(
        source: .custom(foodID: UUID()), name: "Greek yogurt", perUnit: PreviewFoods.greekYogurt, lastAmount: 150
    )

    /// A four-serving lentil soup logged before at 1.5 servings.
    static let recipeChoice = FoodChoice(
        source: .recipe(id: UUID()),
        name: "Lentil soup",
        perUnit: Nutrition(
            energy: 318, protein: 17.6, carbohydrates: 49.1, fatTotal: 4.6,
            fatSaturated: 0.6, fiber: 9.9, sugar: 6.4, sodium: 52
        ),
        gramsPerServing: 233.75,
        lastAmount: 1.5
    )

    /// The lentil soup with the sample photo, as its Add-sheet row shows it.
    static let photoRecipeChoice = FoodChoice(
        source: .recipe(id: UUID()),
        name: "Lentil soup",
        perUnit: recipeChoice.perUnit,
        gramsPerServing: recipeChoice.gramsPerServing,
        lastAmount: 1.5,
        photo: samplePhoto
    )

    /// A product fetched from Open Food Facts, logged before at 30 g.
    static let productChoice = FoodChoice(
        source: .product(foodID: UUID()),
        name: "Smooth peanut butter",
        perUnit: PreviewFoods.peanutButter,
        lastAmount: 30,
        attribution: ProductAttribution(barcode: "5013665111818", brand: "Whole Earth", source: .openFoodFacts)
    )

    /// A product typed from its label after a miss, measured in millilitres.
    static let manualProductChoice = FoodChoice(
        source: .product(foodID: UUID()),
        name: "Oat drink",
        perUnit: PreviewFoods.oatDrink,
        measure: .volume,
        lastAmount: 250,
        attribution: ProductAttribution(barcode: "7394376616105", brand: "Oatly", source: .manual)
    )

    /// Search hits from the bundled database, as the results list shows them.
    static let bundledResults: [BundledFood] = [
        PreviewFoods.apple,
        BundledFood(id: 2, name: "Bananas, raw", category: "Fruits and Fruit Juices", per100g: PreviewFoods.banana, popularity: 99),
        BundledFood(id: 6, name: "Apple juice, canned or bottled, unsweetened", category: "Fruits and Fruit Juices", per100g: Nutrition(energy: 46, protein: 0.1, carbohydrates: 11.3, fatTotal: 0.1, fatSaturated: 0.02, fiber: 0.2, sugar: 9.6, sodium: 4), popularity: 0),
        BundledFood(id: 7, name: "Applesauce, canned, unsweetened", category: "Fruits and Fruit Juices", per100g: Nutrition(energy: 42, protein: 0.2, carbohydrates: 11.3, fatTotal: 0.1, fatSaturated: 0.01, fiber: 1.1, sugar: 9.4, sodium: 2), popularity: 0),
    ]

    /// Library matches for the "Yours" section of the results list.
    static let localResults: [FoodChoice] = [recipeChoice, customChoice, productChoice, manualProductChoice]
}

/// Per-100 values used across seeds and sample choices; USDA figures, rounded. Each is
/// per 100 g except `oatDrink`, whose food is measured in millilitres.
nonisolated enum PreviewFoods {
    static let apple = BundledFood(
        id: 1, name: "Apples, raw, with skin", category: "Fruits and Fruit Juices",
        per100g: Nutrition(energy: 52, protein: 0.3, carbohydrates: 13.8, fatTotal: 0.2, fatSaturated: 0.03, fiber: 2.4, sugar: 10.4, sodium: 1),
        popularity: 100
    )
    static let banana = Nutrition(energy: 89, protein: 1.1, carbohydrates: 22.8, fatTotal: 0.3, fatSaturated: 0.1, fiber: 2.6, sugar: 12.2, sodium: 1)
    static let chicken = Nutrition(energy: 165, protein: 31, carbohydrates: 0, fatTotal: 3.6, fatSaturated: 1, fiber: 0, sugar: 0, sodium: 74)
    static let milk = Nutrition(energy: 61, protein: 3.2, carbohydrates: 4.8, fatTotal: 3.3, fatSaturated: 1.9, fiber: 0, sugar: 5.1, sodium: 43)
    static let rice = Nutrition(energy: 130, protein: 2.7, carbohydrates: 28.2, fatTotal: 0.3, fatSaturated: 0.1, fiber: 0.4, sugar: 0.1, sodium: 1)
    static let egg = Nutrition(energy: 143, protein: 12.6, carbohydrates: 0.7, fatTotal: 9.5, fatSaturated: 3.1, fiber: 0, sugar: 0.4, sodium: 142)
    static let oats = Nutrition(energy: 379, protein: 13.2, carbohydrates: 67.7, fatTotal: 6.5, fatSaturated: 1.2, fiber: 10.1, sugar: 1, sodium: 6)
    static let lentils = Nutrition(energy: 352, protein: 24.6, carbohydrates: 63.4, fatTotal: 1.1, fatSaturated: 0.2, fiber: 10.7, sugar: 2, sodium: 6)
    static let carrot = Nutrition(energy: 41, protein: 0.9, carbohydrates: 9.6, fatTotal: 0.2, fatSaturated: 0.04, fiber: 2.8, sugar: 4.7, sodium: 69)
    static let onion = Nutrition(energy: 40, protein: 1.1, carbohydrates: 9.3, fatTotal: 0.1, fatSaturated: 0.04, fiber: 1.7, sugar: 4.2, sodium: 4)
    static let oliveOil = Nutrition(energy: 884, protein: 0, carbohydrates: 0, fatTotal: 100, fatSaturated: 13.8, fiber: 0, sugar: 0, sodium: 2)
    static let greekYogurt = Nutrition(energy: 59, protein: 10.2, carbohydrates: 3.6, fatTotal: 0.4, fatSaturated: 0.1, fiber: 0, sugar: 3.2, sodium: 36)
    static let sourdough = Nutrition(energy: 289, protein: 11.8, carbohydrates: 56, fatTotal: 1.8, fatSaturated: 0.4, fiber: 2.4, sugar: 2.9, sodium: 513)
    static let passata = Nutrition(energy: 32, protein: 1.5, carbohydrates: 5.4, fatTotal: 0.3, fatSaturated: 0.05, fiber: 1.4, sugar: 4, sodium: 10)
    static let granola = Nutrition(energy: 471, protein: 10.5, carbohydrates: 58.2, fatTotal: 21.3, fatSaturated: 3.1, fiber: 6.8, sugar: 18.4, sodium: 12)
    static let peanutButter = Nutrition(energy: 588, protein: 25, carbohydrates: 20, fatTotal: 50, fatSaturated: 10, fiber: 6, sugar: 9, sodium: 17)
    static let oatDrink = Nutrition(energy: 46, protein: 1, carbohydrates: 6.6, fatTotal: 1.5, fatSaturated: 0.2, fiber: 0.8, sugar: 4, sodium: 40)
    /// A latte as the on-device model might estimate it: values for the portion, not per 100 g.
    static let latteEstimate = Nutrition(energy: 180, protein: 9.4, carbohydrates: 14.2, fatTotal: 9.6, fatSaturated: 5.5, fiber: 0, sugar: 14, sodium: 130)
    /// Two scrambled eggs and a slice of rye toast as estimated from a photo, values for the portion.
    static let scrambledEggsEstimate = Nutrition(energy: 200, protein: 13.5, carbohydrates: 2, fatTotal: 15, fatSaturated: 5.2, fiber: 0, sugar: 1.2, sodium: 320)
    static let ryeToastEstimate = Nutrition(energy: 90, protein: 3, carbohydrates: 17, fatTotal: 1.2, fatSaturated: 0.2, fiber: 2.3, sugar: 1.5, sodium: 200)
    /// Totals of a full day, for the totals row on its own.
    static let dayTotals = Nutrition(energy: 1_648, protein: 92, carbohydrates: 181, fatTotal: 58, fatSaturated: 18, fiber: 27, sugar: 54, sodium: 2_130)
    /// What other apps wrote to Health for the day: the latte from the default foreign samples.
    static let foreignTotals = Nutrition(energy: 180, protein: 9.4)
}

/// Inserts the rows of one seed. Every relationship is set after `insert`, as the
/// model initialisers require; every entry's health state is applied last.
@MainActor
private struct Seeder {
    let context: ModelContext
    private let calendar = Calendar.current

    init(context: ModelContext) {
        self.context = context
    }

    func apply(_ seed: PreviewSeed) {
        switch seed {
        case .empty:
            break
        case .yesterdayOnly:
            let oats = food("Oats, whole grain, rolled, old fashioned", bundledID: 9, per100g: PreviewFoods.oats)
            let apple = food(PreviewFoods.apple.name, bundledID: 1, per100g: PreviewFoods.apple.per100g)
            entry(oats, grams: 40, at: time(8, 10, daysAgo: 1), slot: .breakfast)
            entry(apple, grams: 182, at: time(15, 30, daysAgo: 1), slot: .snack)
        case .firstRun:
            let banana = food("Bananas, raw", bundledID: 2, per100g: PreviewFoods.banana)
            entry(banana, grams: 118, at: time(8, 10), slot: .breakfast)
        case .typicalDay:
            typicalDay()
        case .healthStates:
            healthStates()
        case .library:
            library()
        }
    }

    private func typicalDay() {
        let oats = food("Oats, whole grain, rolled, old fashioned", bundledID: 9, per100g: PreviewFoods.oats)
        let chicken = food("Chicken, broilers or fryers, breast, meat only, cooked, roasted", bundledID: 3, per100g: PreviewFoods.chicken)
        let rice = food("Rice, white, long-grain, regular, enriched, cooked", bundledID: 5, per100g: PreviewFoods.rice)
        let apple = food(PreviewFoods.apple.name, bundledID: 1, per100g: PreviewFoods.apple.per100g)
        let oatDrink = product(
            "Oat drink", brand: "Oatly", barcode: "7394376616105", source: .manual,
            per100g: PreviewFoods.oatDrink, measure: .volume
        )
        let soup = lentilSoup()
        entry(oats, grams: 40, at: time(8, 10), slot: .breakfast)
        entry(oatDrink, grams: 200, at: time(8, 10), slot: .breakfast)
        let eggs = estimate("Scrambled eggs", grams: 120, nutrition: PreviewFoods.scrambledEggsEstimate, at: time(8, 10), slot: .breakfast)
        let toast = estimate("Rye toast", grams: 35, nutrition: PreviewFoods.ryeToastEstimate, at: time(8, 10), slot: .breakfast)
        photo(for: [eggs, toast])
        entry(chicken, grams: 150, at: time(12, 40), slot: .lunch)
        entry(rice, grams: 180, at: time(12, 40), slot: .lunch)
        entry(apple, grams: 182, at: time(15, 30), slot: .snack)
        entry(soup, servings: 1.5, at: time(19, 15), slot: .dinner)
    }

    private func healthStates() {
        let oats = food("Oats, whole grain, rolled, old fashioned", bundledID: 9, per100g: PreviewFoods.oats)
        let banana = food("Bananas, raw", bundledID: 2, per100g: PreviewFoods.banana)
        let chicken = food("Chicken, broilers or fryers, breast, meat only, cooked, roasted", bundledID: 3, per100g: PreviewFoods.chicken)
        let rice = food("Rice, white, long-grain, regular, enriched, cooked", bundledID: 5, per100g: PreviewFoods.rice)
        let apple = food(PreviewFoods.apple.name, bundledID: 1, per100g: PreviewFoods.apple.per100g)
        let peanutButter = product(
            "Smooth peanut butter", brand: "Whole Earth", barcode: "5013665111818",
            source: .openFoodFacts, per100g: PreviewFoods.peanutButter
        )
        entry(oats, grams: 40, at: time(8, 10), slot: .breakfast, state: .synced)
        entry(banana, grams: 118, at: time(8, 10), slot: .breakfast, state: .partial)
        entry(chicken, grams: 150, at: time(12, 40), slot: .lunch, state: .gone)
        entry(rice, grams: 180, at: time(12, 40), slot: .lunch, state: .orphaned)
        entry(apple, grams: 182, at: time(15, 30), slot: .snack, state: .unauthorized)
        estimate("Latte", grams: 250, nutrition: PreviewFoods.latteEstimate, at: time(15, 30), slot: .snack)
        entry(peanutButter, grams: 30, at: time(19, 15), slot: .dinner, state: .synced)
    }

    private func library() {
        let soup = lentilSoup()
        let oats = food("Oats, whole grain, rolled, old fashioned", bundledID: 9, per100g: PreviewFoods.oats)
        let milk = food("Milk, whole, 3.25% milkfat, with added vitamin D", bundledID: 4, per100g: PreviewFoods.milk)
        let banana = food("Bananas, raw", bundledID: 2, per100g: PreviewFoods.banana)
        let egg = food("Egg, whole, raw, fresh", bundledID: 6, per100g: PreviewFoods.egg)
        let oil = food("Oil, olive, salad or cooking", bundledID: 15, per100g: PreviewFoods.oliveOil)
        let yogurt = food("Greek yogurt", kind: .custom, per100g: PreviewFoods.greekYogurt)
        yogurt.photo = photo()
        soup.photo = photo()
        food("Sourdough bread", kind: .custom, per100g: PreviewFoods.sourdough)
        food("Homemade granola", kind: .custom, per100g: PreviewFoods.granola)
        recipe("Overnight oats", servings: 2, ingredients: [(oats, 80), (milk, 200), (yogurt, 100), (banana, 120)])
        recipe("Omelette", servings: 1, ingredients: [(egg, 120), (oil, 5), (milk, 30)])
        product(
            "Smooth peanut butter", brand: "Whole Earth", barcode: "5013665111818",
            source: .openFoodFacts, per100g: PreviewFoods.peanutButter
        )
        product(
            "Oat drink", brand: "Oatly", barcode: "7394376616105", source: .manual,
            per100g: PreviewFoods.oatDrink, measure: .volume
        )
        entry(soup, servings: 1, at: time(19, 15), slot: .dinner)
    }

    /// Four servings of red lentil soup; the passata is a custom food.
    private func lentilSoup() -> Recipe {
        let lentils = food("Lentils, pink or red, raw", bundledID: 12, per100g: PreviewFoods.lentils)
        let carrot = food("Carrots, raw", bundledID: 19, per100g: PreviewFoods.carrot)
        let onion = food("Onions, raw", bundledID: 21, per100g: PreviewFoods.onion)
        let oil = food("Oil, olive, salad or cooking", bundledID: 15, per100g: PreviewFoods.oliveOil)
        let passata = food("Tomato passata", kind: .custom, per100g: PreviewFoods.passata)
        return recipe(
            "Lentil soup", servings: 4,
            ingredients: [(lentils, 250), (carrot, 150), (onion, 120), (oil, 15), (passata, 400)]
        )
    }

    // MARK: Rows

    @discardableResult
    private func food(_ name: String, kind: FoodKind = .bundled, bundledID: Int? = nil, per100g: Nutrition) -> Food {
        let food = Food(name: name, kind: kind, bundledID: bundledID, per100g: per100g)
        context.insert(food)
        return food
    }

    @discardableResult
    private func product(
        _ name: String, brand: String, barcode: String, source: FoodSource,
        per100g: Nutrition, measure: FoodMeasure = .mass
    ) -> Food {
        let food = Food(name: name, kind: .product, bundledID: nil, per100g: per100g, measure: measure)
        context.insert(food)
        food.brand = brand
        food.barcode = barcode
        food.source = source
        if source == .openFoodFacts {
            food.fetchedAt = calendar.date(byAdding: .day, value: -3, to: Date.now)
        }
        return food
    }

    @discardableResult
    private func recipe(_ name: String, servings: Double, ingredients: [(food: Food, grams: Double)]) -> Recipe {
        let recipe = Recipe(name: name, servings: servings)
        context.insert(recipe)
        for (index, row) in ingredients.enumerated() {
            let ingredient = RecipeIngredient(
                sortIndex: index, grams: row.grams, name: row.food.name,
                per100g: row.food.per100g, measure: row.food.measure
            )
            context.insert(ingredient)
            ingredient.recipe = recipe
            ingredient.food = row.food
        }
        return recipe
    }

    @discardableResult
    private func entry(_ food: Food, grams: Double, at timestamp: Date, slot: MealSlot, state: HealthState = .synced) -> LogEntry {
        let entry = LogEntry(
            timestamp: timestamp, mealSlot: slot, foodName: food.name, grams: grams,
            snapshot: SnapshotMath.snapshot(per100g: food.per100g, grams: grams),
            measure: food.measure
        )
        context.insert(entry)
        entry.food = food
        food.noteUsed(amount: grams, at: timestamp)
        apply(state, to: entry)
        return entry
    }

    @discardableResult
    private func entry(_ recipe: Recipe, servings: Double, at timestamp: Date, slot: MealSlot, state: HealthState = .synced) -> LogEntry {
        let entry = LogEntry(
            timestamp: timestamp, mealSlot: slot, foodName: recipe.name,
            grams: recipe.gramsPerServing * servings,
            snapshot: RecipeMath.snapshot(perServing: recipe.perServing, servings: servings)
        )
        context.insert(entry)
        entry.servings = servings
        entry.recipe = recipe
        recipe.noteUsed(servings: servings, at: timestamp)
        apply(state, to: entry)
        return entry
    }

    /// An entry confirmed from an on-device estimate: no food link, values for the portion.
    @discardableResult
    private func estimate(
        _ name: String, grams: Double, nutrition: Nutrition, at timestamp: Date, slot: MealSlot, state: HealthState = .synced
    ) -> LogEntry {
        let entry = LogEntry(timestamp: timestamp, mealSlot: slot, foodName: name, grams: grams, snapshot: nutrition)
        context.insert(entry)
        entry.isEstimate = true
        apply(state, to: entry)
        return entry
    }

    /// A fresh `Photo` row holding the sample picture, inserted and ready to relate.
    private func photo() -> Photo {
        let photo = Photo(data: PreviewStore.samplePhoto)
        context.insert(photo)
        return photo
    }

    /// One photo of the plate shared by the entries of an estimate.
    private func photo(for entries: [LogEntry]) {
        let shared = photo()
        for entry in entries {
            entry.photo = shared
        }
    }

    /// Sets the written and present sets so `entry.healthState` derives to `state`.
    private func apply(_ state: HealthState, to entry: LogEntry) {
        let all = entry.snapshot.presentNutrients
        switch state {
        case .synced:
            entry.written = all
            entry.present = all
        case .partial:
            entry.written = all
            entry.present = all.subtracting([.fiber, .sugar, .sodium])
        case .gone:
            entry.written = all
            entry.present = []
        case .unauthorized:
            entry.written = []
            entry.present = []
        case .orphaned:
            entry.written = all
            entry.present = all
            entry.orphaned = true
        }
    }

    /// Today, or `daysAgo` days back, at `hour`:`minute` local time.
    private func time(_ hour: Int, _ minute: Int, daysAgo: Int = 0) -> Date {
        let day = calendar.date(byAdding: .day, value: -daysAgo, to: Date.now) ?? Date.now
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
    }
}
#endif
