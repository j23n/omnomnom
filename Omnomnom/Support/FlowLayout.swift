import DeveloperToolsSupport
import SwiftUI

/// Subviews in rows, left to right, wrapping to a new row when the next one would not
/// fit the width on offer. Rows are left-aligned and as tall as their tallest subview.
/// Used for chips, which a horizontal scroller would push off the edge at large type.
nonisolated struct FlowLayout: Layout {
    /// Space between neighbours in a row and between rows.
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        let size = frames(for: subviews, maxWidth: maxWidth).size
        // Fill the offered width so the rows sit flush left in it; without an offer,
        // report the widest row.
        let width = maxWidth.isFinite ? max(maxWidth, size.width) : size.width
        return CGSize(width: width, height: size.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let placed = frames(for: subviews, maxWidth: bounds.width).frames
        for (subview, frame) in zip(subviews, placed) {
            subview.place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                anchor: .topLeading,
                proposal: ProposedViewSize(frame.size)
            )
        }
    }

    /// Each subview's frame relative to the layout's origin, and the size they span.
    /// Every subview is offered the full width, so an overlong label wraps rather than
    /// overflowing; a row never wraps its first subview.
    private func frames(for subviews: Subviews, maxWidth: CGFloat) -> (frames: [CGRect], size: CGSize) {
        var rects: [CGRect] = []
        var origin = CGPoint.zero
        var rowHeight: CGFloat = 0
        var widest: CGFloat = 0
        let offer = ProposedViewSize(width: maxWidth.isFinite ? maxWidth : nil, height: nil)
        for subview in subviews {
            let size = subview.sizeThatFits(offer)
            if origin.x > 0, origin.x + size.width > maxWidth {
                origin.x = 0
                origin.y += rowHeight + spacing
                rowHeight = 0
            }
            rects.append(CGRect(origin: origin, size: size))
            rowHeight = max(rowHeight, size.height)
            widest = max(widest, origin.x + size.width)
            origin.x += size.width + spacing
        }
        let height = rects.isEmpty ? 0 : origin.y + rowHeight
        return (rects, CGSize(width: widest, height: height))
    }
}

#if DEBUG
#Preview("Wrapping chips", traits: .sizeThatFitsLayout) {
    FlowLayout(spacing: 8) {
        ForEach(["1 medium (3\" dia), 182 g", "1 cup, chopped, 125 g", "0.5 cup, 62.5 g", "1 small, 149 g"], id: \.self) { label in
            Button(label) {}
                .buttonStyle(.bordered)
        }
    }
    .frame(width: 320)
    .padding()
}

#Preview("Wrapping chips, accessibility 5", traits: .sizeThatFitsLayout) {
    FlowLayout(spacing: 8) {
        ForEach(["½ serving", "1 serving", "2 servings"], id: \.self) { label in
            Button(label) {}
                .buttonStyle(.bordered)
        }
    }
    .frame(width: 320)
    .padding()
    .environment(\.dynamicTypeSize, .accessibility5)
}
#endif
