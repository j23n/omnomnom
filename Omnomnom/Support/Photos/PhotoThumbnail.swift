import CoreGraphics
import DeveloperToolsSupport
import Foundation
import SwiftUI

/// A square, rounded thumbnail of a stored photo, decoded at three times its point
/// size so it stays sharp on any screen. Draws nothing when `data` is `nil`, so a row
/// without a photo keeps its layout. Decorative: the row or button around it says
/// what it is. The decode is a synchronous ImageIO thumbnail of a small JPEG.
struct PhotoThumbnail: View {
    let data: Data?
    let size: CGFloat

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
        }
    }
}

#if DEBUG
#Preview("Sizes", traits: .sizeThatFitsLayout) {
    HStack(spacing: 16) {
        PhotoThumbnail(data: PreviewStore.samplePhoto, size: 44)
        PhotoThumbnail(data: PreviewStore.samplePhoto, size: 72)
        PhotoThumbnail(data: nil, size: 44)
    }
    .padding()
}
#endif
