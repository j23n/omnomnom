import Foundation

/// How sure the model is that a candidate is the food the line meant.
nonisolated enum VerdictCertainty: String, Hashable, Sendable {
    case certain
    case probable
    case unsure

    /// The same certainty as a row's confidence.
    ///
    /// One mapping, because every driving provider reads a certainty and what "probable"
    /// is worth on a row must not depend on which of them answered.
    var confidence: MatchConfidence {
        switch self {
        case .certain: .settled
        case .probable: .probable
        case .unsure: .unsure
        }
    }
}

/// What a model that searched for itself answers with: one entry per food, each naming a
/// candidate the searches returned, and the meal the foods belong to.
///
/// No nutrient value anywhere in this shape, the same as every other answer this app asks
/// for. What it adds over `MealEstimate` is that the food is a candidate id rather than a
/// term to look up afterwards — the model has already seen the rows, so there is nothing
/// left to guess about the table's wording and no second pass to check its guess.
nonisolated struct ResolvedLine: Hashable, Sendable, Decodable {
    let items: [ResolvedLineItem]
    let meal: EstimatedMeal
    let note: String

    init(items: [ResolvedLineItem], meal: EstimatedMeal = .snack, note: String = "") {
        self.items = items
        self.meal = meal
        self.note = note
    }

    private enum CodingKeys: String, CodingKey {
        case items
        case meal
        case note
    }

    /// Read tolerantly, as the other remote answer is: a schema the endpoint honoured
    /// gives this shape exactly, and a draft the user corrects beats a failure they
    /// cannot. An item that holds nothing usable is dropped; the line itself is not.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        items = (try? container.decode([ResolvedLineItem].self, forKey: .items)) ?? []
        let spelled = (try? container.decode(String.self, forKey: .meal))?
            .trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        meal = spelled.flatMap(EstimatedMeal.init(rawValue:)) ?? .snack
        note = (try? container.decode(String.self, forKey: .note)) ?? ""
    }
}

/// One food of an answered line.
nonisolated struct ResolvedLineItem: Hashable, Sendable, Decodable {
    /// What the person who ate it would call it, which is what a row with no food shows.
    let name: String
    /// The id of the chosen candidate, or 0 for "none of these" — which is a first-class
    /// answer and the correct one for a food neither source holds. An id this request
    /// never issued reads the same way, so the model can only ever choose among rows a
    /// search actually returned.
    let candidate: Int
    /// What was eaten, in the chosen row's own unit.
    let grams: Double
    let certainty: VerdictCertainty
    /// The amount and the food do not go together: 200 g of a powder, two kilos of
    /// butter. A judgment about the pair rather than a figure, which is why it is inside
    /// what a model may be asked.
    let implausible: Bool

    init(
        name: String, candidate: Int, grams: Double, certainty: VerdictCertainty,
        implausible: Bool = false
    ) {
        self.name = name
        self.candidate = candidate
        self.grams = grams
        self.implausible = implausible
        self.certainty = certainty
    }

    private enum CodingKeys: String, CodingKey {
        case name
        case candidate
        case grams
        case certainty
        case implausible
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = (try? container.decode(String.self, forKey: .name)) ?? ""
        candidate = (try? container.decode(Int.self, forKey: .candidate)) ?? 0
        grams = (try? container.decode(Double.self, forKey: .grams)).flatMap { $0.isFinite ? $0 : nil } ?? 0
        implausible = (try? container.decode(Bool.self, forKey: .implausible)) ?? false
        // An unreadable certainty is `unsure` rather than a guess at what was meant: it
        // puts the row in front of the user, which is the safe direction to fail in.
        let spelled = (try? container.decode(String.self, forKey: .certainty))?
            .trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        certainty = spelled.flatMap(VerdictCertainty.init(rawValue:)) ?? .unsure
    }
}
