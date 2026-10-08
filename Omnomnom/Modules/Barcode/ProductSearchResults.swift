import Foundation

/// What the food search screen knows about the product half of a search: whether a
/// request is in flight, what came back, and what went wrong. A value type, so the screen
/// holds one piece of state rather than three. Whether the module is switched on is the
/// screen's own `@AppStorage` to read, not something to carry a second copy of here.
///
/// The records are turned into `SearchResult` rows where they are shown, so a product
/// ends up in the same ordered list as everything else rather than in a section of
/// its own.
nonisolated struct ProductResults: Hashable, Sendable {
    var isSearching = false
    var records: [ProductRecord] = []
    var errorMessage: String?

    /// Nothing is asked of a service abroad until there is enough typed to ask about.
    static let shortestQuery = 3

    /// How still the field has to be before anything leaves the device. The local
    /// search answers while the typist is still going; this one waits for them to
    /// stop, so a nine-letter product is one request rather than seven.
    static let quietPeriod = Duration.seconds(1)

    /// Whether a query is worth sending.
    static func isWorthSearching(_ text: String) -> Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).count >= shortestQuery
    }

    mutating func clear() {
        isSearching = false
        records = []
        errorMessage = nil
    }
}
