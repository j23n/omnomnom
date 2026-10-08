import Foundation

/// One line the widget can offer, reduced to what a tile needs to draw it.
nonisolated struct WidgetPhrase: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    /// The line as the user last typed it.
    let text: String
    /// What it comes to, so a tile can say it without reading any food.
    let energy: Double?
    /// Raw `MealSlot` this line is usually logged in; used only for the symbol.
    let slotRaw: String?
}

/// What the app last told the widget.
///
/// Deliberately tiny and deliberately not authoritative. It is a list of things to tap,
/// not a copy of anyone's log, and nothing is computed from it.
nonisolated struct WidgetSnapshot: Codable, Hashable, Sendable {
    /// Most-logged lines first, capped at what the largest tile can show.
    let phrases: [WidgetPhrase]

    static let empty = WidgetSnapshot(phrases: [])

    /// The most a snapshot ever holds. A widget shows at most four; a couple spare costs
    /// nothing and means the list survives one being logged.
    static let capacity = 6

    init(phrases: [WidgetPhrase]) {
        self.phrases = Array(phrases.prefix(WidgetSnapshot.capacity))
    }

    /// The URL a tile links to, which the app receives in `onOpenURL`.
    ///
    /// WidgetKit routes a widget's own links to its host app, so this scheme does not
    /// have to be registered for anyone else to use.
    static func logURL(for phrase: WidgetPhrase) -> URL? {
        var components = URLComponents()
        components.scheme = "omnomnom"
        components.host = "log"
        components.queryItems = [URLQueryItem(name: "phrase", value: phrase.id.uuidString)]
        return components.url
    }

    /// The phrase id in a link the app was opened with, or `nil` when it is not one.
    static func phraseID(from url: URL) -> UUID? {
        guard url.scheme == "omnomnom", url.host == "log",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let raw = components.queryItems?.first(where: { $0.name == "phrase" })?.value
        else { return nil }
        return UUID(uuidString: raw)
    }
}
