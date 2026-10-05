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
    /// Takes back what the last line wrote.
    let onUndo: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            if model.showsUnauthorizedNotice {
                UnauthorizedNoticeView { model.showsUnauthorizedNotice = false }
            }
            if let banner = model.banner {
                BannerView(message: banner) { model.dismissBanner() }
            }
            // Above the question and both above the field, so the order down the screen is
            // the order things happened in: what was written, what is still being asked,
            // and the place the next line goes.
            if let logged = model.lastLogged {
                LoggedLineBar(logged: logged, onUndo: onUndo) { model.dismissLogged() }
            }
            if let note = composer.unplacedNote {
                UnplacedRowsBar(
                    note: note,
                    onPick: { composer.askAboutUnplaced() },
                    onLeave: { composer.clearUnplaced() }
                )
            }
            ComposerView(model: composer, onSubmit: onSubmit)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .readableColumn()
        .animation(.default, value: model.banner)
        .animation(.default, value: model.showsUnauthorizedNotice)
        .animation(.default, value: model.lastLogged)
        .animation(.default, value: composer.unplacedNote)
    }
}

#if DEBUG
#Preview("Composer only", traits: .sizeThatFitsLayout) {
    TodayBottomBar(model: TodayViewModel(), composer: ComposerModel(), onSubmit: {}, onUndo: {})
}

#Preview("Mid sentence", traits: .sizeThatFitsLayout) {
    let composer = ComposerModel()
    composer.line = "oats, banana, large coffee"
    return TodayBottomBar(model: TodayViewModel(), composer: composer, onSubmit: {}, onUndo: {})
}

#Preview("Banner and notice", traits: .sizeThatFitsLayout) {
    let model = TodayViewModel()
    model.banner = "Logged here only. Health didn't accept it."
    model.showsUnauthorizedNotice = true
    return TodayBottomBar(model: model, composer: ComposerModel(), onSubmit: {}, onUndo: {})
}

#Preview("iPad width", traits: .fixedLayout(width: 1024, height: 220)) {
    let model = TodayViewModel()
    model.banner = "Copied 4 entries from yesterday."
    return TodayBottomBar(model: model, composer: ComposerModel(), onSubmit: {}, onUndo: {})
}

#Preview("Accessibility 5", traits: .sizeThatFitsLayout) {
    let model = TodayViewModel()
    model.banner = "Copied 4 entries from yesterday."
    model.showsUnauthorizedNotice = true
    return TodayBottomBar(model: model, composer: ComposerModel(), onSubmit: {}, onUndo: {})
        .environment(\.dynamicTypeSize, .accessibility5)
}
#endif
