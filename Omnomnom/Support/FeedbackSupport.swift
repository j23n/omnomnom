#if FEEDBACK
import FeedbackKit
import Foundation

/// In-app feedback, in Debug builds only (the `FEEDBACK` condition, project.yml): a shake, a
/// screenshot or Settings › Feedback opens FeedbackKit's form, and the report goes to the
/// owner's private inbox, j23n/feedback, where it's triaged before an issue is filed here.
///
/// The screenshot redacts every view marked `privacySensitive()`: what someone ate, as
/// `ValueText` shows it, the amounts typed and the trends. A new view that shows a figure of
/// someone's intake uses `ValueText` or is marked too.
extension FeedbackCenter {
    static func omnomnom() -> FeedbackCenter {
        FeedbackCenter(configuration: FeedbackConfiguration(
            inbox: GitHubRepository(owner: "j23n", name: "feedback"),
            app: "omnomnom",
            kinds: [.bug, .idea, FeedbackKind(id: "content", title: "Food data")],
            redaction: .privacySensitiveViews
        ))
    }
}
#endif
