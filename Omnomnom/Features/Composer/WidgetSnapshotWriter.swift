import Foundation
import os
import SwiftData
import WidgetKit

/// Keeps the widget's list of lines in step with what is actually logged.
///
/// Written after a line is logged rather than on a schedule, because that is the only
/// moment the answer changes. The widget's own timeline refresh is a backstop.
///
/// Nothing here is authoritative: the snapshot is a list of things to tap. It carries an
/// energy figure per line only so a tile can say what one comes to without reading any
/// food, and no total, count or figure about a day ever goes into it. A widget that fits
/// three numbers will be read as a score, and this app does not score anyone.
enum WidgetSnapshotWriter {
    /// Rebuilds the snapshot from the most-logged lines and asks the widget to reload.
    static func update(in context: ModelContext) {
        let phrases = (try? Phrase.all(in: context)) ?? []
        let ranked = phrases
            .filter(\.isRecallable)
            // Most logged first, then most recent, so a line eaten daily outranks one
            // eaten twice yesterday.
            .sorted {
                $0.useCount == $1.useCount ? $0.lastUsed > $1.lastUsed : $0.useCount > $1.useCount
            }
            .prefix(WidgetSnapshot.capacity)
            .map(summary(of:))
        AppGroupStore.write(WidgetSnapshot(phrases: ranked))
        WidgetCenter.shared.reloadAllTimelines()
        AppGroupLog.widget.info("snapshot written with \(ranked.count) lines")
    }

    /// One line reduced to what a tile draws.
    private static func summary(of phrase: Phrase) -> WidgetPhrase {
        let energy = phrase.orderedItems.reduce(into: 0.0) { total, item in
            guard let choice = item.recipe?.choice ?? item.food.flatMap(\.choice),
                  let value = choice.snapshot(for: item.amount).energy
            else { return }
            total += value
        }
        return WidgetPhrase(
            id: phrase.id,
            text: phrase.text,
            energy: energy > 0 ? energy : nil,
            slotRaw: phrase.lastSlotRaw
        )
    }

    /// The phrase a widget tap names, if it still exists and still resolves.
    static func phrase(id: UUID, in context: ModelContext) -> Phrase? {
        let wanted: UUID = id
        var descriptor = FetchDescriptor<Phrase>(predicate: #Predicate<Phrase> { $0.id == wanted })
        descriptor.fetchLimit = 1
        guard let phrase = try? context.fetch(descriptor).first, phrase.isRecallable else { return nil }
        return phrase
    }
}
