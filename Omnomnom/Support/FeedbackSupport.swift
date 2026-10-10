#if FEEDBACK
import FeedbackKit
import Foundation

/// In-app feedback, in Debug builds only (the `FEEDBACK` condition, project.yml): a shake, a
/// screenshot or Settings › Feedback opens FeedbackKit's form, and the report goes to the
/// owner's private inbox, j23n/feedback, where it's triaged before an issue is filed here.
///
/// The screenshot carries nothing of the person's: with FeedbackKit's `.allContent` redaction,
/// SwiftUI draws placeholders for every text and image for the capture, and the titles and text
/// fields UIKit draws are painted over, so foods, meals, recipes, amounts, times, photographs and
/// what was typed are all hidden; the screen's layout and the tab bar stay. It fails safe: a new
/// view is hidden without being marked.
extension FeedbackCenter {
    static func omnomnom() -> FeedbackCenter {
        FeedbackCenter(configuration: FeedbackConfiguration(
            inbox: GitHubRepository(owner: "j23n", name: "feedback"),
            app: "omnomnom",
            kinds: [.bug, .idea, FeedbackKind(id: "content", title: "Food data")],
            redaction: .allContent
        ))
    }
}
#endif
