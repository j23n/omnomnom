import Foundation
import SwiftUI

/// Household measures as shortcuts. Tapping one fills the gram field; grams stay canonical.
struct PortionChips: View {
    let portions: [Portion]
    let onSelect: (Portion) -> Void

    var body: some View {
        if portions.isEmpty {
            EmptyView()
        } else {
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(portions, id: \.self) { portion in
                        Button {
                            onSelect(portion)
                        } label: {
                            Text("\(portion.label), \(Formatters.grams(portion.grams))")
                                .lineLimit(1)
                        }
                        .buttonStyle(.bordered)
                        .accessibilityLabel("\(portion.label), \(Formatters.grams(portion.grams))")
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
    }
}
