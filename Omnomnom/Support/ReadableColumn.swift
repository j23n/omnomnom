import SwiftUI

/// How wide content is allowed to get before it stops being readable.
///
/// Every measure here is wider than any iPhone, so none of them changes anything on
/// one. On an iPad they stop a row of food running the width of a thirteen-inch
/// display, which is most of the difference between an app designed for the iPad and
/// one merely allowed onto it.
nonisolated enum ReadableColumn {
    /// A list meant to be read down. Wide enough for a long database name and its
    /// figures on one line, narrow enough that the eye finds the next row without
    /// travelling back across a desk.
    static let list: CGFloat = 700

    /// A control meant to be tapped rather than read. A button the width of an iPad is
    /// not easier to hit, only harder to believe in.
    static let control: CGFloat = 420
}

extension View {
    /// Caps this view's width and centres it in whatever is left.
    func readableColumn(_ width: CGFloat = ReadableColumn.list) -> some View {
        frame(maxWidth: width)
            .frame(maxWidth: .infinity)
    }
}
