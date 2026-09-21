import Foundation

/// One entry of `sources.json`, the attribution manifest the pipeline writes.
nonisolated struct SourceManifest: Codable, Hashable, Sendable, Identifiable {
    let id: String
    let name: String
    let publisher: String
    let datasets: [SourceDataset]
    let licence: String
    let licenceURL: String
    let url: String
    let citation: String

    enum CodingKeys: String, CodingKey {
        case id, name, publisher, datasets, licence, url, citation
        case licenceURL = "licence_url"
    }
}

/// A dataset within a source, with the version the bundle was built from.
nonisolated struct SourceDataset: Codable, Hashable, Sendable, Identifiable {
    let id: String
    let name: String
    let version: String
}
