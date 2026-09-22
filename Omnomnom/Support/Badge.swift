import DeveloperToolsSupport
import SwiftUI

/// A small capsule caption next to a row's details: "Estimated", "Partly in Health".
/// Neutral fill and secondary text, so it labels without judging.
struct Badge: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.fill.tertiary, in: Capsule())
    }
}

#if DEBUG
#Preview("Badges", traits: .sizeThatFitsLayout) {
    HStack(spacing: 8) {
        Badge("Estimated")
        Badge("Partly in Health")
        Badge("Only in Health")
    }
    .padding()
}

#Preview("Accessibility 5", traits: .sizeThatFitsLayout) {
    Badge("No longer in Health")
        .padding()
        .environment(\.dynamicTypeSize, .accessibility5)
}
#endif
