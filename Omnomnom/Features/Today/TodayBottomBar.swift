import DeveloperToolsSupport
import SwiftUI

/// The bar above the tab bar: the unauthorized notice and the transient banner, when
/// either is up, stacked over the composer.
///
/// The composer stands where the Add food button used to. Add has not gone — it is in
/// the toolbar, where it was already — but it is the second way in now rather than the
/// first, which is the whole point of the redesign: the common case is a line of text,
/// and the search screen is for when you would rather point than type.
struct TodayBottomBar: View {
    let model: TodayViewModel
    @Bindable var composer: ComposerModel
    let onSubmit: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            if model.showsUnauthorizedNotice {
                UnauthorizedNoticeView { model.showsUnauthorizedNotice = false }
            }
            if let banner = model.banner {
                BannerView(message: banner) { model.dismissBanner() }
            }
            ComposerView(model: composer, onSubmit: onSubmit)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .readableColumn()
        .animation(.default, value: model.banner)
        .animation(.default, value: model.showsUnauthorizedNotice)
    }
}

#if DEBUG
#Preview("Composer only", traits: .sizeThatFitsLayout) {
    TodayBottomBar(model: TodayViewModel(), composer: ComposerModel()) {}
}

#Preview("Mid sentence", traits: .sizeThatFitsLayout) {
    let composer = ComposerModel()
    composer.line = "oats, banana, large coffee"
    return TodayBottomBar(model: TodayViewModel(), composer: composer) {}
}

#Preview("Banner and notice", traits: .sizeThatFitsLayout) {
    let model = TodayViewModel()
    model.banner = "Logged here only. Health didn't accept it."
    model.showsUnauthorizedNotice = true
    return TodayBottomBar(model: model, composer: ComposerModel()) {}
}

#Preview("iPad width", traits: .fixedLayout(width: 1024, height: 220)) {
    let model = TodayViewModel()
    model.banner = "Copied 4 entries from yesterday."
    return TodayBottomBar(model: model, composer: ComposerModel()) {}
}

#Preview("Accessibility 5", traits: .sizeThatFitsLayout) {
    let model = TodayViewModel()
    model.banner = "Copied 4 entries from yesterday."
    model.showsUnauthorizedNotice = true
    return TodayBottomBar(model: model, composer: ComposerModel()) {}
        .environment(\.dynamicTypeSize, .accessibility5)
}
#endif
