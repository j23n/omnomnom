import Foundation

/// One food another app or the Health app wrote, as the "Also in Health" section shows it.
nonisolated struct ForeignMeal: Hashable, Identifiable, Sendable {
    let name: String
    let sourceName: String
    /// Start of the samples, rounded down to the minute they were grouped by.
    let start: Date
    let nutrition: Nutrition

    var id: String { "\(name)|\(sourceName)|\(start.timeIntervalSinceReferenceDate)" }
}

/// What Health holds for one day, split into this app's own samples and everyone else's.
nonisolated struct DayHealthSummary: Hashable, Sendable {
    let own: Nutrition
    let foreign: Nutrition
    /// Foreign samples grouped into meals, oldest first.
    let meals: [ForeignMeal]

    static let empty = DayHealthSummary(own: .empty, foreign: .empty, meals: [])

    /// True when another source contributed any positive amount.
    var hasForeign: Bool {
        Nutrient.allCases.contains { (foreign[$0] ?? 0) > 0 }
    }

    /// What a foreign meal written by this app is called: from another device, or left in
    /// Health by an entry this device removed.
    static let unmirroredLabel = "Omnomnom, not in this log"

    /// Sums own and foreign samples and groups the foreign ones into meals by name,
    /// source and start minute. Own means mirrored by a local entry: the sync identifier
    /// parses and names an id in `localEntryIDs`. Everything else is foreign, including
    /// this app's samples without a local entry, which are labelled as such.
    static func make(from samples: [HealthNutritionSample], localEntryIDs: Set<UUID>) -> DayHealthSummary {
        var own = Nutrition.empty
        var foreign = Nutrition.empty
        var groups: [MealKey: Nutrition] = [:]
        for sample in samples {
            var single = Nutrition.empty
            single[sample.nutrient] = sample.value
            if isMirrored(sample, by: localEntryIDs) {
                own = own + single
                continue
            }
            foreign = foreign + single
            let key = MealKey(
                name: name(for: sample),
                sourceName: sample.sourceName,
                minute: minute(of: sample.start)
            )
            groups[key] = (groups[key] ?? .empty) + single
        }
        let meals = groups
            .map { ForeignMeal(name: $0.key.name, sourceName: $0.key.sourceName, start: $0.key.minute, nutrition: $0.value) }
            .sorted { ($0.start, $0.name, $0.sourceName) < ($1.start, $1.name, $1.sourceName) }
        return DayHealthSummary(own: own, foreign: foreign, meals: meals)
    }

    static func isMirrored(_ sample: HealthNutritionSample, by localEntryIDs: Set<UUID>) -> Bool {
        guard let id = sample.syncIdentifier, let parsed = SyncIdentifier.parse(id) else { return false }
        return localEntryIDs.contains(parsed.entryID)
    }

    /// The food type when the writer set one, else the source; this app's own bundle
    /// without a local entry is named so the user knows why it cannot be edited here.
    static func name(for sample: HealthNutritionSample) -> String {
        guard sample.isOwnBundle else { return sample.foodType ?? sample.sourceName }
        return [sample.foodType, unmirroredLabel].compactMap { $0 }.joined(separator: " · ")
    }

    /// `date` with seconds dropped, so samples of one meal written moments apart share a group.
    static func minute(of date: Date) -> Date {
        Date(timeIntervalSinceReferenceDate: (date.timeIntervalSinceReferenceDate / 60).rounded(.down) * 60)
    }
}

private nonisolated struct MealKey: Hashable {
    let name: String
    let sourceName: String
    let minute: Date
}
