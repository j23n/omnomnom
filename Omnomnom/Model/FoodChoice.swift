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
/// needs. A food is measured in grams and carries per-100 g values; a recipe is
/// measured in servings and carries per-serving values plus the raw grams of one.
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
    /// Per 100 g of a food, or per one serving of a recipe.
    let perUnit: Nutrition
    /// Raw grams in one serving; `nil` for a food, whose amount is grams already.
    let gramsPerServing: Double?
    /// Amount used last time, to prefill the field: grams for a food, servings for a
    /// recipe. `nil` for an item never logged.
    let lastAmount: Double?
    /// Barcode, brand and origin of a product; `nil` for everything else.
    let attribution: ProductAttribution?

    var id: Source { source }

    init(
        source: Source, name: String, perUnit: Nutrition, gramsPerServing: Double? = nil,
        lastAmount: Double? = nil, attribution: ProductAttribution? = nil
    ) {
        self.source = source
        self.name = name
        self.perUnit = perUnit
        self.gramsPerServing = gramsPerServing
        self.lastAmount = lastAmount
        self.attribution = attribution
    }

    /// A search hit from the bundled database; knows nothing of past use yet.
    init(bundled: BundledFood) {
        self.init(source: .bundled(id: bundled.id), name: bundled.name, perUnit: bundled.per100g)
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
            source: source, name: name, perUnit: perUnit, gramsPerServing: gramsPerServing,
            lastAmount: lastAmount, attribution: attribution
        )
    }

    /// Raw grams consumed for `amount` units: the grams themselves, or servings times the
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

    /// "100 g" or "serving", for "x kcal per …" captions.
    var unitText: String {
        isRecipe ? "serving" : "100 g"
    }

    /// "182 g" or "1.5 servings", for a stored or typed amount.
    func amountText(_ amount: Double) -> String {
        isRecipe ? Formatters.servings(amount) : Formatters.grams(amount)
    }
}
