import SwiftUI

/// One list of results, best match first, each row saying where it came from.
///
/// The three sources used to be three sections, which put the app's plumbing between
/// the user and their porridge and buried a perfect Library match under a heading. The
/// order is `SearchRelevance`'s now, and the only things that are not results sit at
/// the bottom: whether more are still coming, and what went wrong if anything did.
/// They sit there so that nothing already on screen moves when they appear.
struct SearchResultsList: View {
    let results: [SearchResult]
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
            if results.isEmpty, !hasStatus {
                ContentUnavailableView.search
                    .listRowSeparator(.hidden)
                if let modules {
                    modules
                }
            }
            ForEach(results) { result in
                Button {
                    onSelect(result)
                } label: {
                    SearchResultRow(result: result)
                }
                .buttonStyle(.plain)
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
        .animation(.default, value: results.map(\.id))
    }
}

#if DEBUG
#Preview("Mixed sources") {
    SearchResultsList(
        results: PreviewStore.searchResults, databaseError: nil,
        products: ProductResults(isEnabled: true), modules: nil, onSelect: { _ in }
    )
}

#Preview("Products still coming") {
    SearchResultsList(
        results: Array(PreviewStore.searchResults.prefix(3)), databaseError: nil,
        products: ProductResults(isEnabled: true, isSearching: true), modules: nil, onSelect: { _ in }
    )
}

#Preview("Products unavailable") {
    SearchResultsList(
        results: Array(PreviewStore.searchResults.prefix(3)), databaseError: nil,
        products: ProductResults(isEnabled: true, errorMessage: "Open Food Facts could not be reached."),
        modules: nil, onSelect: { _ in }
    )
}

#Preview("Database missing") {
    SearchResultsList(
        results: [], databaseError: FoodRepositoryError.databaseMissing.errorDescription,
        products: ProductResults(), modules: nil, onSelect: { _ in }
    )
}

#Preview("No matches") {
    SearchResultsList(
        results: [], databaseError: nil, products: ProductResults(), modules: nil, onSelect: { _ in }
    )
}

#Preview("No matches, modules on") {
    SearchResultsList(
        results: [], databaseError: nil, products: ProductResults(),
        modules: ModuleButtonsRow(scanRequested: .constant(false), estimateRequested: .constant(false)),
        onSelect: { _ in }
    )
    .defaultAppStorage(PreviewDefaults.modulesOn)
}

#Preview("Accessibility 5") {
    SearchResultsList(
        results: PreviewStore.searchResults, databaseError: nil,
        products: ProductResults(isEnabled: true), modules: nil, onSelect: { _ in }
    )
    .environment(\.dynamicTypeSize, .accessibility5)
}
#endif
