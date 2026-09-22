import CoreGraphics
import DeveloperToolsSupport
import Foundation
import SwiftUI

/// A square, rounded thumbnail of a stored photo, decoded at three times its point
/// size so it stays sharp on any screen. Without a photo it draws the mark on a tinted
/// square of the same size, so a list keeps one left edge whether its items have
/// photos or not. Decorative either way: the row or button around it says what it is,
/// and the placeholder is never a button and never offers to add a photo, which the
/// editors own. At accessibility type sizes the placeholder steps aside and the row
/// draws nothing, giving the name back the 56 points a square and its spacing take;
/// a real photo is the item's own content and is always drawn.
/// The decode is a synchronous ImageIO thumbnail of a small JPEG.
struct PhotoThumbnail: View {
    let data: Data?
    let size: CGFloat

    /// The placeholder's square, about the weight of a system tertiary fill: enough to
    /// show where a photo would go, little enough that a long list of results without
    /// photos reads as quiet texture rather than a column of orange.
    private static let squareOpacity = 0.12
    /// The mark, which carries more than its square because it covers less than a tenth
    /// of it and still has to read at 44 pt. Well short of the full tint, which in this
    /// app means "you can act on this" and would make a decorative square look tappable.
    private static let markOpacity = 0.4

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var image: CGImage?

    var body: some View {
        if let data {
            Group {
                if let image {
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .scaledToFill()
                } else {
                    Color.secondary.opacity(0.15)
                }
            }
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.22))
            .task(id: data) {
                image = PhotoData.downscaled(data, maxPixelSize: min(Int(size * 3), PhotoData.thumbnailPixelSize))
            }
        } else if !dynamicTypeSize.isAccessibilitySize {
            placeholder
        }
    }

    /// The mark centred on the same rounded square the photo is clipped to, at a little
    /// over half the side so it keeps a margin rather than filling edge to edge.
    private var placeholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.22)
                .fill(.tint.opacity(Self.squareOpacity))
            BiteMark()
                .fill(.tint.opacity(Self.markOpacity))
                .frame(width: size * 0.55, height: size * 0.55)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

#if DEBUG
/// A photo beside a placeholder at both sizes the app uses: 44 pt in the lists, 72 pt
/// in the editors.
private struct ThumbnailSamples: View {
    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            PhotoThumbnail(data: PreviewStore.samplePhoto, size: 44)
            PhotoThumbnail(data: nil, size: 44)
            PhotoThumbnail(data: PreviewStore.samplePhoto, size: 72)
            PhotoThumbnail(data: nil, size: 72)
        }
        .padding()
    }
}

#Preview("Photo and placeholder", traits: .sizeThatFitsLayout) {
    ThumbnailSamples()
}

#Preview("Photo and placeholder, dark", traits: .sizeThatFitsLayout) {
    ThumbnailSamples()
        .preferredColorScheme(.dark)
}

/// What a page of search results looks like when nothing in it has a photo.
private struct PlaceholderColumn: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(0..<6, id: \.self) { _ in
                HStack(spacing: 12) {
                    PhotoThumbnail(data: nil, size: 44)
                    Text("Food nobody photographed")
                }
            }
        }
        .padding()
    }
}

#Preview("A column of placeholders", traits: .sizeThatFitsLayout) {
    PlaceholderColumn()
}

#Preview("A column of placeholders, accessibility 5", traits: .sizeThatFitsLayout) {
    // The squares step aside here: the names need the width more than the list needs
    // its left edge.
    PlaceholderColumn()
        .environment(\.dynamicTypeSize, .accessibility5)
}
#endif
