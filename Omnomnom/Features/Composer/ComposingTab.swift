import Foundation
import SwiftUI

/// Puts the field at the bottom of a tab, and points it at the day that tab is about.
///
/// Inside the tab's own content and not on the `TabView`. An inset on the tab view belongs
/// to the tab bar's chrome rather than to any screen, and three things went wrong at once
/// when it was there: the field drew over the tab bar instead of above it, keystrokes
/// reached the bar's own selection and changed tabs, and every character re-laid-out the
/// whole tab. Inside the content it is an ordinary bottom inset — which is what makes it
/// rise with the keyboard, the reason it is an inset and not a bar.
///
/// Applied once per tab. The state behind it is one `ComposerModel` in the environment, so
/// four fields are four views of the same half-typed line.
struct ComposingTab: ViewModifier {
    /// The day a line typed here goes into. `nil` means today, which is every tab but
    /// Today — it holds the app's one day selector and is the only screen that can be
    /// showing something else.
    var day: Date?

    @Environment(\.composer) private var composer

    func body(content: Content) -> some View {
        content
            .safeAreaInset(edge: .bottom, spacing: 0) {
                ComposerBar()
            }
            .onAppear { composer.looking(at: day ?? .now) }
            .onChange(of: day) { _, day in
                composer.looking(at: day ?? .now)
            }
    }
}

extension View {
    /// The field over this tab's content; see `ComposingTab`.
    func composingTab(day: Date? = nil) -> some View {
        modifier(ComposingTab(day: day))
    }
}
