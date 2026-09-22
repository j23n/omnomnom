import Foundation

/// Provenance of a scanned product, shown on its rows and on the Quantity sheet so
/// Open Food Facts gets the attribution its licence asks for.
nonisolated struct ProductAttribution: Hashable, Sendable {
    let barcode: String
    let brand: String?
    let source: FoodSource

    var isFromOpenFoodFacts: Bool {
        source == .openFoodFacts
    }
}

/// What the user picked in the Add sheet, reduced to the values the Quantity sheet
/// needs. A food is measured in its own unit, grams or millilitres, and carries the
/// per-100 values in that unit; a recipe is measured in servings and carries
/// per-serving values plus the raw grams of one.
nonisolated struct FoodChoice: Identifiable, Hashable, Sendable {
    /// Where the item lives: the bundled database, a custom or product `Food` row, or a `Recipe`.
    nonisolated enum Source: Hashable, Sendable {
        case bundled(id: Int)
        case custom(foodID: UUID)
        case product(foodID: UUID)
        case recipe(id: UUID)
    }

    let source: Source
    let name: String
    /// Per 100 g or 100 ml of a food, as `measure` says, or per one serving of a recipe.
    let perUnit: Nutrition
    /// The unit a food's amount and per-100 values are counted in. A recipe is measured
    /// in servings, so its own measure says nothing and stays `.mass`.
    let measure: FoodMeasure
    /// Raw grams in one serving; `nil` for a food, whose amount is its own unit already.
    let gramsPerServing: Double?
    /// Amount used last time, to prefill the field: grams or millilitres for a food,
    /// servings for a recipe. `nil` for an item never logged.
    let lastAmount: Double?
    /// Barcode, brand and origin of a product; `nil` for everything else.
    let attribution: ProductAttribution?
    /// The stored photo of a custom food, product or recipe, so a row can show it
    /// without a fetch; `nil` for a bundled food and for anything without one.
    var photo: Data? = nil

    var id: Source { source }

    init(
        source: Source, name: String, perUnit: Nutrition, measure: FoodMeasure = .mass,
        gramsPerServing: Double? = nil, lastAmount: Double? = nil,
        attribution: ProductAttribution? = nil, photo: Data? = nil
    ) {
        self.source = source
        self.name = name
        self.perUnit = perUnit
        self.measure = measure
        self.gramsPerServing = gramsPerServing
        self.lastAmount = lastAmount
        self.attribution = attribution
        self.photo = photo
    }

    /// A search hit from the bundled database; knows nothing of past use yet. The
    /// bundled database is per 100 g throughout, so the measure is settled here.
    init(bundled: BundledFood) {
        self.init(source: .bundled(id: bundled.id), name: bundled.name, perUnit: bundled.per100g, measure: .mass)
    }

    var isRecipe: Bool {
        if case .recipe = source { return true }
        return false
    }

    /// The bundled row's id, for portions and the stored copy; `nil` otherwise.
    var bundledID: Int? {
        if case .bundled(let id) = source { return id }
        return nil
    }

    /// The same choice with the amount used last time filled in.
    func with(lastAmount: Double?) -> FoodChoice {
        FoodChoice(
            source: source, name: name, perUnit: perUnit, measure: measure,
            gramsPerServing: gramsPerServing, lastAmount: lastAmount,
            attribution: attribution, photo: photo
        )
    }

    /// Raw grams consumed for `amount` units: the amount itself, or servings times the
    /// raw weight of one serving.
    func grams(for amount: Double) -> Double {
        guard let gramsPerServing else { return amount }
        return amount * gramsPerServing
    }

    /// Nutrition to freeze for `amount` units.
    func snapshot(for amount: Double) -> Nutrition {
        if isRecipe {
            return RecipeMath.snapshot(perServing: perUnit, servings: amount)
        }
        return SnapshotMath.snapshot(per100g: perUnit, grams: amount)
    }

    /// "100 g", "100 ml" or "serving", for "x kcal per …" captions.
    var unitText: String {
        isRecipe ? "serving" : measure.referenceUnit
    }

    /// "182 g", "250 ml" or "1.5 servings", for a stored or typed amount.
    func amountText(_ amount: Double) -> String {
        isRecipe ? Formatters.servings(amount) : Formatters.amount(amount, measure: measure)
    }
}
