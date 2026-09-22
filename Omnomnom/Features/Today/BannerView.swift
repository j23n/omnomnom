import DeveloperToolsSupport
import Foundation
import SwiftUI

/// Transient notice at the bottom of Today. The view model takes it down after a few
/// seconds; a tap anywhere on it does so at once.
struct BannerView: View {
    let message: String
    let dismiss: () -> Void

    var body: some View {
        Button(action: dismiss) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(message)
                    .font(.footnote)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "xmark")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding()
            .glassEffect(in: RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(message)
        .accessibilityHint("Dismisses the notice")
    }
}

/// Shown once per launch when Health is on the device but currently accepts no nutrient
/// from this app, so the sentence is true of the app right now rather than of one old
/// entry. Opens the Health app, where sharing with this app is switched on.
struct UnauthorizedNoticeView: View {
    let dismiss: () -> Void

    @Environment(\.openURL) private var openURL

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Health isn't accepting nutrition from this app. Entries are kept here.")
                    .font(.footnote)
                    .multilineTextAlignment(.leading)
                if let url = URL(string: "x-apple-health://") {
                    Button("Open Health") { openURL(url) }
                        .font(.footnote.weight(.semibold))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: dismiss) {
                Image(systemName: "xmark")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss")
        }
        .padding()
        .glassEffect(in: RoundedRectangle(cornerRadius: 16))
    }
}

#if DEBUG
#Preview("Banner", traits: .sizeThatFitsLayout) {
    BannerView(message: "Logged here only. Health didn't accept it.") {}
        .padding()
}

#Preview("Banner, long message", traits: .sizeThatFitsLayout) {
    BannerView(message: DeleteOutcome.orphaned.bannerMessage ?? "") {}
        .padding()
}

#Preview("Unauthorized notice", traits: .sizeThatFitsLayout) {
    UnauthorizedNoticeView {}
        .padding()
}

#Preview("Both, accessibility 5", traits: .sizeThatFitsLayout) {
    VStack(spacing: 8) {
        UnauthorizedNoticeView {}
        BannerView(message: "Logged here only. Health didn't accept it.") {}
    }
    .padding()
    .environment(\.dynamicTypeSize, .accessibility5)
}
#endif
