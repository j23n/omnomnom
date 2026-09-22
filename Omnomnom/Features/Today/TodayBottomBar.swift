import DeveloperToolsSupport
import SwiftUI

/// The bar above the tab bar: the unauthorized notice and the transient banner, when
/// either is up, stacked over a full-width Add food button.
struct TodayBottomBar: View {
    let model: TodayViewModel

    var body: some View {
        VStack(spacing: 8) {
            if model.showsUnauthorizedNotice {
                UnauthorizedNoticeView { model.showsUnauthorizedNotice = false }
            }
            if let banner = model.banner {
                BannerView(message: banner) { model.dismissBanner() }
            }
            Button {
                model.isAddPresented = true
            } label: {
                Label("Add food", systemImage: "plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .buttonBorderShape(.capsule)
            .accessibilityLabel("Add food")
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .animation(.default, value: model.banner)
        .animation(.default, value: model.showsUnauthorizedNotice)
    }
}

#if DEBUG
#Preview("Button only", traits: .sizeThatFitsLayout) {
    TodayBottomBar(model: TodayViewModel())
}

#Preview("Banner and notice", traits: .sizeThatFitsLayout) {
    let model = TodayViewModel()
    model.banner = "Logged here only. Health didn't accept it."
    model.showsUnauthorizedNotice = true
    return TodayBottomBar(model: model)
}

#Preview("Accessibility 5", traits: .sizeThatFitsLayout) {
    let model = TodayViewModel()
    model.banner = "Copied 4 entries from yesterday."
    model.showsUnauthorizedNotice = true
    return TodayBottomBar(model: model)
        .environment(\.dynamicTypeSize, .accessibility5)
}
#endif
