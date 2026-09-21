import Foundation
import os
import SwiftUI

/// Every bundled database, its licence and links, rendered from `sources.json`.
struct SourcesView: View {
    @Environment(\.foodRepository) private var foodRepository
    @State private var sources: [SourceManifest] = []
    @State private var errorMessage: String?

    var body: some View {
        List {
            if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.secondary)
            }
            ForEach(sources) { source in
                Section(source.name) {
                    LabeledContent("Publisher", value: source.publisher)
                    ForEach(source.datasets) { dataset in
                        LabeledContent(dataset.name, value: dataset.version)
                    }
                    if let licenceURL = URL(string: source.licenceURL) {
                        Link(destination: licenceURL) {
                            LabeledContent("Licence", value: source.licence)
                        }
                    } else {
                        LabeledContent("Licence", value: source.licence)
                    }
                    if let url = URL(string: source.url) {
                        Link("Website", destination: url)
                    }
                    Text(source.citation)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Sources")
        .task { load() }
    }

    private func load() {
        do {
            sources = try foodRepository.sources()
        } catch {
            AppLog.foodDB.error("sources.json failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = error.localizedDescription
        }
    }
}
