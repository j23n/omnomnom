import DeveloperToolsSupport
import SwiftUI

/// The mark: a disc with one round bite taken out of its upper right and two crumbs.
/// This file defines the geometry; `Tools/icon/make_icon.py` and
/// `docs/design/icon/mark.svg` copy it. Every value is relative to the square the
/// shape is drawn in, so it scales from a 28 pt row to the app icon. Fill it with
/// `.tint`.
nonisolated struct BiteMark: Shape {
    func path(in rect: CGRect) -> Path {
        let side = min(rect.width, rect.height)
        let origin = CGPoint(x: rect.midX - side / 2, y: rect.midY - side / 2)

        func disc(_ x: CGFloat, _ y: CGFloat, _ radius: CGFloat) -> Path {
            Path(ellipseIn: CGRect(
                x: origin.x + (x - radius) * side,
                y: origin.y + (y - radius) * side,
                width: 2 * radius * side,
                height: 2 * radius * side
            ))
        }

        return disc(0.50, 0.53, 0.30)
            .subtracting(disc(0.695, 0.325, 0.135))
            .union(disc(0.80, 0.235, 0.024))
            .union(disc(0.855, 0.31, 0.016))
    }
}

#if DEBUG
#Preview("Sizes", traits: .sizeThatFitsLayout) {
    HStack(alignment: .bottom, spacing: 24) {
        BiteMark().fill(.tint).frame(width: 28, height: 28)
        BiteMark().fill(.tint).frame(width: 56, height: 56)
        BiteMark().fill(.tint).frame(width: 96, height: 96)
    }
    .padding()
}

#Preview("Sizes, dark", traits: .sizeThatFitsLayout) {
    HStack(alignment: .bottom, spacing: 24) {
        BiteMark().fill(.tint).frame(width: 28, height: 28)
        BiteMark().fill(.tint).frame(width: 56, height: 56)
        BiteMark().fill(.tint).frame(width: 96, height: 96)
    }
    .padding()
    .preferredColorScheme(.dark)
}

#Preview("On the accent colour, as the icon", traits: .sizeThatFitsLayout) {
    BiteMark()
        .fill(.white)
        .frame(width: 180, height: 180)
        .background(Color.accentColor)
}
#endif
