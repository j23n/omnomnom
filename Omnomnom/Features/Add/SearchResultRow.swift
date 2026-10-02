import DeveloperToolsSupport
import SwiftUI

/// One food in a list: its photo or the mark, its name, the one line of figures, and
/// where it came from when that is in question.
///
/// It is in question in the search results, which mix three sources, and the pill
/// answers it — neutral, like every other badge in the app, so it says where a number
/// is from without implying that one source is better. It is not in question in the
/// recents, where the heading already says that everything below it is yours or
/// something you have eaten, so `showsSource` is off there. A label on every row of a
/// list that cannot vary is not information.
///
/// At accessibility type sizes the pill moves above the figures rather than squeezing
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

    private var figures: some View {
        ValueText(result.caption)
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    var body: some View {
        HStack(spacing: 12) {
            PhotoThumbnail(data: result.photo, size: 44)
            VStack(alignment: .leading, spacing: 4) {
                Text(result.name)
                if showsSource {
                    detailLayout {
                        Badge(result.provenance.pill)
                        figures
                    }
                } else {
                    figures
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

#if DEBUG
#Preview("Every source", traits: .sizeThatFitsLayout) {
    VStack(alignment: .leading, spacing: 16) {
        ForEach(PreviewStore.searchResults) { result in
            SearchResultRow(result: result)
        }
    }
    .padding()
}

#Preview("Without the pill, as the recents show them", traits: .sizeThatFitsLayout) {
    VStack(alignment: .leading, spacing: 16) {
        ForEach(PreviewStore.searchResults.prefix(3)) { result in
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
#endif
