import DeveloperToolsSupport
import SwiftUI

/// One search result: its photo or the mark, its name, where it came from, and the one
/// line of figures. The pill is neutral, like every other badge in the app: it says
/// where a number is from without implying that one source is better than another.
///
/// At accessibility type sizes the pill moves above the figures rather than squeezing
/// them, since both are short and the name needs the width.
struct SearchResultRow: View {
    let result: SearchResult

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var detailLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 6))
    }

    var body: some View {
        HStack(spacing: 12) {
            PhotoThumbnail(data: result.photo, size: 44)
            VStack(alignment: .leading, spacing: 4) {
                Text(result.name)
                detailLayout {
                    Badge(result.provenance.pill)
                    ValueText(result.caption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
