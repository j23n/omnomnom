import SwiftUI

/// Results in two groups: what the user owns, then everything else.
///
/// Their own foods come first, ordered by what they last ate, because that is almost
/// always the answer and it is never a question where the numbers came from. Below
/// them the bundled tables and Open Food Facts are read as one list, best match first,
/// with a pill per row saying which — the one place that question arises.
///
/// The only things that are not results sit at the bottom: whether more are still
/// coming, and what went wrong if anything did. They sit there so nothing already on
/// screen moves when they appear.
struct SearchResultsList: View {
    let sections: SearchResults.Sections
    /// Why the bundled database could not be read; `nil` when it was.
    let databaseError: String?
    let products: ProductResults
    /// The Scan and Estimate row for the no-results state; `nil` in pick mode.
    let modules: ModuleButtonsRow?
    let onSelect: (SearchResult) -> Void

    private var hasStatus: Bool {
        products.isSearching || products.errorMessage != nil || databaseError != nil
    }

    var body: some View {
        List {
            if sections.isEmpty, !hasStatus {
                ContentUnavailableView.search
                    .listRowSeparator(.hidden)
                if let modules {
                    modules
                }
            }
            if !sections.yours.isEmpty {
                Section("Yours") {
                    rows(sections.yours, showsSource: false)
                }
            }
            if !sections.others.isEmpty {
                Section("Other foods") {
                    rows(sections.others, showsSource: true)
                }
            }
            if products.isSearching {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Searching Open Food Facts…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .listRowSeparator(.hidden)
            }
            if let message = products.errorMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .listRowSeparator(.hidden)
            }
            if let databaseError {
                Text(databaseError)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        .readableColumn()
        .animation(.default, value: sections.others.map(\.id))
    }

    private func rows(_ results: [SearchResult], showsSource: Bool) -> some View {
        ForEach(results) { result in
            Button {
                onSelect(result)
            } label: {
                SearchResultRow(result: result, showsSource: showsSource)
            }
            .buttonStyle(.plain)
        }
    }
}

#if DEBUG
#Preview("Both groups") {
    SearchResultsList(
        sections: PreviewStore.searchSections, databaseError: nil,
        products: ProductResults(isEnabled: true), modules: nil, onSelect: { _ in }
    )
}

#Preview("Nothing of the user's own") {
    SearchResultsList(
        sections: SearchResults.Sections(others: PreviewStore.searchSections.others),
        databaseError: nil, products: ProductResults(isEnabled: true),
        modules: nil, onSelect: { _ in }
    )
}

#Preview("Products still coming") {
    SearchResultsList(
        sections: PreviewStore.searchSections, databaseError: nil,
        products: ProductResults(isEnabled: true, isSearching: true), modules: nil, onSelect: { _ in }
    )
}

#Preview("Products unavailable") {
    SearchResultsList(
        sections: PreviewStore.searchSections, databaseError: nil,
        products: ProductResults(isEnabled: true, errorMessage: "Open Food Facts could not be reached."),
        modules: nil, onSelect: { _ in }
    )
}

#Preview("Database missing") {
    SearchResultsList(
        sections: SearchResults.Sections(), databaseError: FoodRepositoryError.databaseMissing.errorDescription,
        products: ProductResults(), modules: nil, onSelect: { _ in }
    )
}

#Preview("No matches") {
    SearchResultsList(
        sections: SearchResults.Sections(), databaseError: nil, products: ProductResults(),
        modules: nil, onSelect: { _ in }
    )
}

#Preview("No matches, modules on") {
    SearchResultsList(
        sections: SearchResults.Sections(), databaseError: nil, products: ProductResults(),
        modules: ModuleButtonsRow(scanRequested: .constant(false), estimateRequested: .constant(false)),
        onSelect: { _ in }
    )
    .defaultAppStorage(PreviewDefaults.modulesOn)
}

#Preview("iPad width", traits: .fixedLayout(width: 1024, height: 768)) {
    SearchResultsList(
        sections: PreviewStore.searchSections, databaseError: nil,
        products: ProductResults(isEnabled: true), modules: nil, onSelect: { _ in }
    )
}

#Preview("Accessibility 5") {
    SearchResultsList(
        sections: PreviewStore.searchSections, databaseError: nil,
        products: ProductResults(isEnabled: true), modules: nil, onSelect: { _ in }
    )
    .environment(\.dynamicTypeSize, .accessibility5)
}
#endif
