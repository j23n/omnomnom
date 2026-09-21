import Foundation
import SwiftUI

/// Open Food Facts as a data source: name, licence, links and the note the Sources
/// screen shows. Static because nothing from it is bundled; only lookups touch it.
nonisolated enum OpenFoodFactsSource {
    static let name = "Open Food Facts"
    static let publisher = "Open Food Facts (association loi 1901, France)"
    static let licence = "Open Database License 1.0"
    static let licenceURL = "https://opendatacommons.org/licenses/odbl/1-0/"
    static let websiteURL = "https://world.openfoodfacts.org"
    static let note = "Used only for barcode lookups; results are cached on this device."

    /// The public page of one product, for the attribution link.
    static func productURL(barcode: String) -> URL? {
        URL(string: "\(websiteURL)/product/\(barcode)")
    }
}

/// "Data from Open Food Facts · ODbL" with the product and licence links, as the
/// licence asks. Renders nothing unless the product was fetched from there.
struct OpenFoodFactsAttribution: View {
    let attribution: ProductAttribution?

    var body: some View {
        if let attribution, attribution.isFromOpenFoodFacts {
            VStack(alignment: .leading, spacing: 4) {
                Text("Data from Open Food Facts · ODbL")
                HStack(spacing: 12) {
                    if let url = OpenFoodFactsSource.productURL(barcode: attribution.barcode) {
                        Link("Product page", destination: url)
                    }
                    if let url = URL(string: OpenFoodFactsSource.licenceURL) {
                        Link("Licence", destination: url)
                    }
                }
            }
            .font(.footnote)
        }
    }
}
