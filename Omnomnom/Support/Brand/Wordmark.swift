import DeveloperToolsSupport
import SwiftUI

/// "Omnomnom" in the rounded system face at bold weight. Together with the energy
/// figure on Today this is the only place the rounded design is used; body text keeps
/// the default face.
struct Wordmark: View {
    var body: some View {
        Text("Omnomnom")
            .font(.system(.title2, design: .rounded, weight: .bold))
    }
}

#if DEBUG
#Preview("Wordmark", traits: .sizeThatFitsLayout) {
    VStack(spacing: 16) {
        Wordmark()
        HStack(spacing: 12) {
            BiteMark().fill(.tint).frame(width: 28, height: 28)
            Wordmark()
        }
    }
    .padding()
}

#Preview("Accessibility 5", traits: .sizeThatFitsLayout) {
    Wordmark()
        .padding()
        .environment(\.dynamicTypeSize, .accessibility5)
}
#endif
