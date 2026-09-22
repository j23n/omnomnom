import CoreGraphics
import DeveloperToolsSupport
import Foundation
import SwiftUI

/// One photo at full stored size, fitted on black, under the name of what it shows
/// and, when given, when it was logged. Opened from a thumbnail; Done closes it.
struct PhotoViewer: View {
    let data: Data
    let title: String
    let subtitle: String?

    @Environment(\.dismiss) private var dismiss
    @State private var image: CGImage?

    init(data: Data, title: String, subtitle: String? = nil) {
        self.data = data
        self.title = title
        self.subtitle = subtitle
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black
                    .ignoresSafeArea()
                if let image {
                    Image(image, scale: 1, label: Text("Photo of \(title)"))
                        .resizable()
                        .scaledToFit()
                }
            }
            .navigationTitle(title)
            .navigationSubtitle(subtitle ?? "")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task(id: data) {
                image = PhotoData.downscaled(data, maxPixelSize: PhotoData.storedPixelSize)
            }
        }
    }
}

#if DEBUG
#Preview("Entry photo") {
    PhotoViewer(data: PreviewStore.samplePhoto, title: "Scrambled eggs", subtitle: "Today, 08:10")
}

#Preview("Recipe photo, no subtitle") {
    PhotoViewer(data: PreviewStore.samplePhoto, title: "Lentil soup")
}
#endif
