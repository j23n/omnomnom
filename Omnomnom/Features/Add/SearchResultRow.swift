import DeveloperToolsSupport
import SwiftUI

/// One food in a list: its photo or the mark, its name, the one line of figures, and
/// where it came from when that is in question.
///
/// It is in question under "Other foods", which reads the bundled tables and Open Food
/// Facts as one list, and the pill answers it — neutral, like every other badge in the
/// app, so it says where a number is from without implying that one source is better.
/// It is not in question among the user's own foods or in the recents, where the heading
/// already says what everything below it is, so `showsSource` is off there. A label on
/// every row of a list that cannot vary is not information.
///
/// A second pill says which of the eight nutrient figures the row carries, and that one is
/// on every row. It is what tells two otherwise identical rows apart — the same cheese
/// twice, where one of them has no figure for fibre — and that is a question the user is
/// the only one who can answer, since a row short of a figure is often still the right
/// answer. It is a count and never a grade.
///
/// At accessibility type sizes the pills move above the figures rather than squeezing
/// them, since both are short and the name needs the width.
struct SearchResultRow: View {
    let result: SearchResult
    /// Whether to show the provenance pill. Off where the list is of one kind.
    let showsSource: Bool

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(result: SearchResult, showsSource: Bool = true) {
        self.result = result
        self.showsSource = showsSource
    }

    private var detailLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 6))
    }

    private var numbers: some View {
        ValueText(result.caption)
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    /// How many of the eight figures the row holds, as a pill of its own.
    private var figures: some View {
        Badge(result.figures.pill)
            .accessibilityLabel(result.figures.spoken)
    }

    var body: some View {
        HStack(spacing: 12) {
            PhotoThumbnail(data: result.photo, size: 44)
            VStack(alignment: .leading, spacing: 4) {
                Text(result.name)
                detailLayout {
                    if showsSource {
                        Badge(result.provenance.pill)
                    }
                    figures
                    numbers
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// A result as a row of a list: the row, and the tray's plus where there is a tray.
///
/// Two buttons side by side rather than one with something inside it, because a control
/// inside a button is a control that never gets tapped. The row opens the food; the plus
/// puts it in the tray and leaves the screen where it is, which is the whole point of the
/// tray — four foods in one visit costs four taps and one Log.
///
/// The plus is absent, not disabled, where a row cannot go in the tray: a product Open
/// Food Facts knows by name but not by its values has to be fetched before anything can
/// be done with it, and that is what tapping the row does.
struct PickableResultRow: View {
    let result: SearchResult
    var showsSource: Bool = true
    /// Puts this food in the tray; `nil` where there is no tray or this row cannot join it.
    var onAdd: (() -> Void)?
    let onSelect: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onSelect) {
                SearchResultRow(result: result, showsSource: showsSource)
            }
            .buttonStyle(.plain)
            if let onAdd {
                Button(action: onAdd) {
                    Image(systemName: "plus")
                        .font(.body.weight(.semibold))
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.tint)
                .accessibilityLabel("Add \(result.name)")
                .accessibilityHint("Puts it in the tray. Nothing is logged until you tap Log")
            }
        }
    }
}

#if DEBUG
#Preview("With a pill, as Other foods show them", traits: .sizeThatFitsLayout) {
    VStack(alignment: .leading, spacing: 16) {
        ForEach(PreviewStore.searchResults) { result in
            SearchResultRow(result: result)
        }
    }
    .padding()
}

#Preview("The user's own, without a pill", traits: .sizeThatFitsLayout) {
    VStack(alignment: .leading, spacing: 16) {
        ForEach(PreviewStore.yourResults) { result in
            SearchResultRow(result: result, showsSource: false)
        }
    }
    .padding()
}

#Preview("Accessibility 5", traits: .sizeThatFitsLayout) {
    VStack(alignment: .leading, spacing: 16) {
        ForEach(PreviewStore.searchResults.prefix(2)) { result in
            SearchResultRow(result: result)
        }
    }
    .padding()
    .environment(\.dynamicTypeSize, .accessibility5)
}

/// Two rows that read the same until the figures pill: the whole reason it is there.
private func feta(_ missing: Set<Nutrient>, id: String) -> SearchResult {
    SearchResult(
        id: id,
        provenance: .database,
        name: "Feta",
        caption: "Cheese · 264 kcal per 100 g",
        figures: SearchResult.Figures(missing: missing),
        photo: nil,
        rank: 0.8,
        lastUsed: nil,
        action: .choice(FoodChoice(
            source: .bundled(id: 1), name: "Feta", perUnit: Nutrition(energy: 264)
        ))
    )
}

#Preview("Telling two identical rows apart", traits: .sizeThatFitsLayout) {
    List {
        SearchResultRow(result: feta([], id: "a"))
        SearchResultRow(result: feta([.fiber], id: "b"))
        SearchResultRow(result: feta([.fiber, .sugar, .sodium], id: "c"))
    }
    .listStyle(.plain)
}

#Preview("The figures pill at accessibility 5", traits: .sizeThatFitsLayout) {
    List {
        SearchResultRow(result: feta([], id: "a"))
        SearchResultRow(result: feta([.fiber], id: "b"))
    }
    .listStyle(.plain)
    .environment(\.dynamicTypeSize, .accessibility5)
}

#Preview("With the tray's plus", traits: .sizeThatFitsLayout) {
    List {
        ForEach(PreviewStore.searchSections.others) { result in
            PickableResultRow(result: result, onAdd: {}, onSelect: {})
        }
    }
    .listStyle(.plain)
}

#Preview("The plus at accessibility 5", traits: .sizeThatFitsLayout) {
    List {
        ForEach(PreviewStore.searchSections.others.prefix(2)) { result in
            PickableResultRow(result: result, onAdd: {}, onSelect: {})
        }
    }
    .listStyle(.plain)
    .environment(\.dynamicTypeSize, .accessibility5)
}
#endif
