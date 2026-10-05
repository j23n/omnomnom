import DeveloperToolsSupport
import SwiftUI

/// This screen's own notices: the once-per-launch word that Health is accepting nothing,
/// and the transient banner for something that just happened on this day.
///
/// The field used to be here and is not any more. It sits over the tab bar, so it is on
/// every tab and is laid out above the keyboard by the one inset that holds it; what is
/// left here is what belongs to Today in particular — a delete, a repeat, a day copied
/// from yesterday.
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
        }
        .padding(.horizontal)
        .padding(.vertical, model.showsUnauthorizedNotice || model.banner != nil ? 8 : 0)
        .readableColumn()
        .animation(.default, value: model.banner)
        .animation(.default, value: model.showsUnauthorizedNotice)
    }
}

#if DEBUG
#Preview("Nothing to say", traits: .sizeThatFitsLayout) {
    TodayBottomBar(model: TodayViewModel())
}

#Preview("A banner", traits: .sizeThatFitsLayout) {
    let model = TodayViewModel()
    model.banner = "Logged here only. Health didn't accept it."
    return TodayBottomBar(model: model)
}

#Preview("Banner and notice", traits: .sizeThatFitsLayout) {
    let model = TodayViewModel()
    model.banner = "Copied 4 entries from yesterday."
    model.showsUnauthorizedNotice = true
    return TodayBottomBar(model: model)
}

#Preview("iPad width", traits: .fixedLayout(width: 1024, height: 160)) {
    let model = TodayViewModel()
    model.banner = "Copied 4 entries from yesterday."
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
