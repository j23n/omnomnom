import DeveloperToolsSupport
import Foundation
import SwiftUI
import UIKit

/// Non-blocking notice at the bottom of Today, dismissed by tap.
struct BannerView: View {
    let message: String
    let dismiss: () -> Void

    var body: some View {
        Button(action: dismiss) {
            HStack {
                Text(message)
                    .font(.footnote)
                    .multilineTextAlignment(.leading)
                Spacer()
                Image(systemName: "xmark")
                    .font(.footnote)
            }
            .padding()
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Notice: \(message). Double tap to dismiss.")
    }
}

/// Shown once per launch when an entry never reached Health because no nutrient may be
/// written. Links to the app's page in Settings, where Health permissions live.
struct UnauthorizedNoticeView: View {
    let dismiss: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("Some entries never reached Health because no nutrient may be written.")
                .font(.footnote)
                .multilineTextAlignment(.leading)
            Spacer()
            if let url = URL(string: UIApplication.openSettingsURLString) {
                Link("Settings", destination: url)
                    .font(.footnote.weight(.semibold))
            }
            Button(action: dismiss) {
                Image(systemName: "xmark")
                    .font(.footnote)
            }
            .accessibilityLabel("Dismiss")
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
    }
}

#if DEBUG
#Preview("Banner", traits: .sizeThatFitsLayout) {
    BannerView(message: "Logged locally. Nothing reached Health; check Settings.") {}
        .padding(.vertical)
}

#Preview("Banner, long message", traits: .sizeThatFitsLayout) {
    BannerView(message: DeleteOutcome.orphaned.bannerMessage ?? "") {}
        .padding(.vertical)
}

#Preview("Unauthorized notice", traits: .sizeThatFitsLayout) {
    UnauthorizedNoticeView {}
        .padding(.vertical)
}

#Preview("Both, accessibility 5", traits: .sizeThatFitsLayout) {
    VStack(spacing: 8) {
        UnauthorizedNoticeView {}
        BannerView(message: "Logged locally. Nothing reached Health; check Settings.") {}
    }
    .padding(.vertical)
    .environment(\.dynamicTypeSize, .accessibility5)
}
#endif
