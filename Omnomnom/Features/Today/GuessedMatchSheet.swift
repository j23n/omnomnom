import Foundation
import SwiftData
import SwiftUI

/// The question a marked row is asking, with the three answers to it.
///
/// A line is logged without being signed off, so somewhere the app has to be able to say
/// "this is what I made of that word" — and to be told it was wrong. This is that place,
/// and it is reached from the mark on the row rather than from a screen of its own: the
/// question belongs to the entry, not to a queue.
///
/// Three answers, in the order they are wanted. The match was right, which is the common
/// one and takes the mark off and changes nothing else. Or it was one of the others the
/// word could have meant, which are the shortlist the guess itself came from — not a
/// fresh search that might not even contain the row being corrected. Or it was none of
/// them, and the search screen opens.
///
/// What it never offers is leaving the question open, because that is what closing it
/// does. The mark stays until it is answered.
struct GuessedMatchSheet: View {
    let entry: LogEntry
    /// The foods the word could have meant, asked for when the sheet opens. A closure so
    /// this screen holds no database of its own and a preview can hand it a list.
    let load: () async -> [FoodChoice]
    /// The food is right. The mark goes.
    let onSettle: () -> Void
    /// Log this one instead.
    let onReplace: (FoodChoice) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var candidates: [FoodChoice] = []
    @State private var hasLoaded = false
    @State private var isSearching = false

    /// Everything the word could have meant except what is already logged.
    private var alternatives: [FoodChoice] {
        candidates.filter { $0.name != entry.foodName }
    }

    var body: some View {
        NavigationStack {
            List {
                logged
                others
                Section {
                    Button("Search for something else", systemImage: "magnifyingglass") {
                        isSearching = true
                    }
                }
            }
            .navigationTitle("Is this right?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .sheet(isPresented: $isSearching) {
                FoodSearchView(mode: .pick(multiple: false, onPick: replace))
            }
            .task {
                guard !hasLoaded else { return }
                candidates = await load()
                hasLoaded = true
            }
        }
    }

    /// What is in the day now, and the answer that keeps it.
    private var logged: some View {
        Section {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.foodName)
                Text(Self.loggedDetail(of: entry))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            Button("Yes, that's right", systemImage: "checkmark") {
                onSettle()
                dismiss()
            }
        } header: {
            Text(Self.question(for: entry))
        } footer: {
            Text("This is already logged either way. Answering only settles whether the app got the food right.")
        }
    }

    @ViewBuilder private var others: some View {
        Section("Or log one of these instead") {
            if !hasLoaded {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text("Looking again").foregroundStyle(.secondary)
                }
            } else if alternatives.isEmpty {
                Text("Nothing else in the tables answers that.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(alternatives) { choice in
                    Button {
                        replace(choice)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(choice.name)
                            Text(SearchResult.caption(for: choice))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Logs this instead, at the same amount")
                }
            }
        }
    }

    private func replace(_ choice: FoodChoice) {
        isSearching = false
        onReplace(choice)
        dismiss()
    }

    /// "You said “oats”" — or, where nothing was said, what the app is asking about.
    ///
    /// The quotation is the whole point of keeping the wording. A row reading *Oat flakes*
    /// is unarguable beside the word "oats" and plainly wrong beside "oat milk", and only
    /// one of those two is something the person can see for themselves.
    static func question(for entry: LogEntry) -> String {
        guard let wording = entry.wording, !wording.isEmpty else { return "Logged as" }
        return "You said “\(wording)”"
    }

    /// "1.5 servings · 351 g · 08:10": the amount in the units it was logged in, both of
    /// them for a recipe that mixes them, then the time it was logged.
    ///
    /// The row's own figures, so the answer is given against what is actually in the day
    /// rather than against a remembered version of it. `EntryRow`'s caption is the same
    /// line, from here, for the same reason.
    static func loggedDetail(of entry: LogEntry) -> String {
        var parts: [String] = []
        if let servings = entry.servings {
            parts.append(Formatters.servings(servings))
        }
        if !entry.rawAmount.isEmpty {
            parts.append(entry.rawAmount.wholeText)
        }
        parts.append(entry.timestamp.formatted(date: .omitted, time: .shortened))
        return parts.joined(separator: " · ")
    }
}

#if DEBUG
/// The sheet around whichever entry a seed holds, so a preview stays honest when a seed
/// changes rather than trapping on a force-unwrap.
private struct GuessedMatchPreview: View {
    let container: ModelContainer
    let entry: LogEntry?
    var candidates: [FoodChoice] = []

    var body: some View {
        Group {
            if let entry {
                GuessedMatchSheet(
                    entry: entry,
                    load: { candidates },
                    onSettle: {},
                    onReplace: { _ in }
                )
            } else {
                Text("No entry in this seed.")
            }
        }
        .modelContainer(container)
    }
}

private func previewChoice(_ name: String, kcal: Double, last: Double? = nil) -> FoodChoice {
    FoodChoice(
        source: .bundled(id: abs(name.hashValue % 10_000)),
        name: name,
        perUnit: Nutrition(energy: kcal, protein: 11, carbohydrates: 60, fatTotal: 7),
        measure: .mass,
        lastAmount: last
    )
}

#Preview("Three other things it could have meant") {
    let container = PreviewStore.container(seed: .typicalDay)
    let entry = PreviewStore.entries(in: container).first
    entry?.wording = "oats"
    entry?.guessed = true
    return GuessedMatchPreview(
        container: container,
        entry: entry,
        candidates: [
            previewChoice("Oat flakes", kcal: 372, last: 45),
            previewChoice("Oat drink, unsweetened", kcal: 46),
            previewChoice("Oat bran", kcal: 246),
            previewChoice("Porridge, made with water", kcal: 60)
        ]
    )
}

#Preview("Nothing else answers it") {
    let container = PreviewStore.container(seed: .typicalDay)
    let entry = PreviewStore.entries(in: container).first
    entry?.wording = "the rest of the lasagne"
    entry?.guessed = true
    return GuessedMatchPreview(container: container, entry: entry)
}

#Preview("Nothing was said, as a widget tap leaves it") {
    let container = PreviewStore.container(seed: .typicalDay)
    let entry = PreviewStore.entries(in: container).first
    entry?.guessed = true
    return GuessedMatchPreview(
        container: container,
        entry: entry,
        candidates: [previewChoice("Oat flakes", kcal: 372)]
    )
}

#Preview("Accessibility 5") {
    let container = PreviewStore.container(seed: .typicalDay)
    let entry = PreviewStore.entries(in: container).first
    entry?.wording = "oats"
    entry?.guessed = true
    return GuessedMatchPreview(
        container: container,
        entry: entry,
        candidates: [previewChoice("Oat flakes", kcal: 372, last: 45)]
    )
    .environment(\.dynamicTypeSize, .accessibility5)
}
#endif
