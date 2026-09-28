import DeveloperToolsSupport
import Foundation
import SwiftUI

/// What the food search screen knows about the product half of a search: whether it is
/// switched on at all, whether a request is in flight, what came back, and what went
/// wrong. A value type, so the screen holds one piece of state rather than four.
nonisolated struct ProductResults: Hashable, Sendable {
    var isEnabled = false
    var isSearching = false
    var records: [ProductRecord] = []
    var errorMessage: String?

    /// Nothing is asked of a service abroad until there is enough typed to ask about.
    static let shortestQuery = 3

    /// How still the field has to be before anything leaves the device. The local
    /// search answers while the typist is still going; this one waits for them to
    /// stop, so a nine-letter product is one request rather than seven.
    static let quietPeriod = Duration.seconds(1)

    /// Whether a query is worth sending.
    static func isWorthSearching(_ text: String) -> Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).count >= shortestQuery
    }

    /// Whether the section has anything to show, including the reason it has not.
    var hasSomethingToSay: Bool {
        isEnabled && (isSearching || !records.isEmpty || errorMessage != nil)
    }

    mutating func clear() {
        isSearching = false
        records = []
        errorMessage = nil
    }
}

/// One product from Open Food Facts in the search results: name, brand and the energy
/// on its label when the index carries one. The thumbnail is the placeholder, because
/// product images are never requested.
struct ProductResultRow: View {
    let record: ProductRecord

    /// "Ferrero · 571 kcal per 100 g · Open Food Facts", wrapping as one line of text.
    private var caption: String {
        var parts: [String] = []
        if let brand = record.brand {
            parts.append(brand)
        }
        if let energy = record.per100g.energy {
            parts.append("\(Formatters.amount(energy, unit: .kilocalorie)) \(record.measure.referenceText)")
        }
        parts.append("Open Food Facts")
        return parts.joined(separator: " · ")
    }

    var body: some View {
        HStack(spacing: 12) {
            PhotoThumbnail(data: nil, size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(record.name ?? record.code)
                ValueText(caption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

#if DEBUG
#Preview("Products", traits: .sizeThatFitsLayout) {
    VStack(alignment: .leading, spacing: 16) {
        ProductResultRow(record: ProductRecord(
            code: "8000500037560", name: "Kinder Bueno", brand: "Ferrero",
            per100g: Nutrition(energy: 571, protein: 8.6, carbohydrates: 49.5, fatTotal: 37.3)
        ))
        ProductResultRow(record: ProductRecord(
            code: "5449000000996", name: "Coca-Cola", brand: "Coca-Cola",
            per100g: Nutrition(energy: 42, carbohydrates: 10.6), measure: .volume
        ))
        ProductResultRow(record: ProductRecord(
            code: "4006381333931", name: "A product the index knows only by name", brand: nil,
            per100g: .empty
        ))
    }
    .padding()
}
#endif
