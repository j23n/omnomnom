import SwiftUI
import WidgetKit

/// One refresh of the widget.
struct TopPhrasesEntry: TimelineEntry {
    let date: Date
    let phrases: [WidgetPhrase]
}

/// Reads the snapshot the app writes. Nothing is computed here and nothing is stored.
struct TopPhrasesProvider: TimelineProvider {
    func placeholder(in context: Context) -> TopPhrasesEntry {
        TopPhrasesEntry(date: .now, phrases: TopPhrasesProvider.sample)
    }

    func getSnapshot(in context: Context, completion: @escaping (TopPhrasesEntry) -> Void) {
        let stored = AppGroupStore.read().phrases
        completion(TopPhrasesEntry(date: .now, phrases: stored.isEmpty ? Self.sample : stored))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TopPhrasesEntry>) -> Void) {
        let entry = TopPhrasesEntry(date: .now, phrases: AppGroupStore.read().phrases)
        // The snapshot only changes when the app writes one, and the app reloads the
        // timeline itself when it does. An hour is a backstop, not the mechanism.
        completion(Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(3_600))))
    }

    /// Shown in the gallery and before the app has ever written a snapshot.
    static let sample: [WidgetPhrase] = [
        WidgetPhrase(id: UUID(), text: "oats with a banana", energy: 240, slotRaw: "breakfast"),
        WidgetPhrase(id: UUID(), text: "chicken salad", energy: 420, slotRaw: "lunch"),
        WidgetPhrase(id: UUID(), text: "flat white", energy: 90, slotRaw: "snack"),
        WidgetPhrase(id: UUID(), text: "lentil soup", energy: 380, slotRaw: "dinner"),
    ]
}

/// The lines this person logs most, one tap each.
///
/// It does not log anything itself: a tap opens the app on that line, which resolves and
/// logs it. See `AppGroupStore` for why that is the right division rather than a
/// compromise.
///
/// What it deliberately does not show: any total, any count, any figure about the day. A
/// widget that fits three numbers will be read as a score, and this app does not score
/// anyone. It offers things to tap and nothing else.
struct TopPhrasesWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "TopPhrases", provider: TopPhrasesProvider()) { entry in
            TopPhrasesView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Log a meal")
        .description("The lines you log most, one tap each.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct TopPhrasesView: View {
    let entry: TopPhrasesEntry
    @Environment(\.widgetFamily) private var family

    private var shown: [WidgetPhrase] {
        Array(entry.phrases.prefix(family == .systemSmall ? 2 : 4))
    }

    var body: some View {
        if shown.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text("Nothing logged yet")
                    .font(.subheadline.weight(.semibold))
                Text("Lines you log appear here.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } else {
            VStack(alignment: .leading, spacing: family == .systemSmall ? 8 : 6) {
                ForEach(shown) { phrase in
                    if let url = WidgetSnapshot.logURL(for: phrase) {
                        Link(destination: url) {
                            PhraseTile(phrase: phrase, compact: family == .systemSmall)
                        }
                    } else {
                        PhraseTile(phrase: phrase, compact: family == .systemSmall)
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }
}

/// One line, with its symbol and what it comes to.
private struct PhraseTile: View {
    let phrase: WidgetPhrase
    let compact: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.caption)
                .foregroundStyle(.tint)
            Text(phrase.text)
                .font(compact ? .caption : .subheadline)
                .lineLimit(compact ? 2 : 1)
            if !compact, let energy = phrase.energy {
                Spacer(minLength: 4)
                Text("\(Int(energy.rounded())) kcal")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityLabel("Log \(phrase.text)")
    }
}

/// The meal symbols, duplicated rather than shared.
///
/// `MealSlot` lives in the app target and this is four strings; a shared folder for them
/// would cost more than the duplication does. They are kept in step by name: a slot is
/// its raw value.
private extension PhraseTile {
    var symbol: String {
        switch phrase.slotRaw {
        case "breakfast": "sunrise"
        case "lunch": "sun.max"
        case "dinner": "moon.stars"
        default: "carrot"
        }
    }
}
