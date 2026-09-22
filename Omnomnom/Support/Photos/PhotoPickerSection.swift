import CoreTransferable
import DeveloperToolsSupport
import Foundation
import os
import PhotosUI
import SwiftUI
import UIKit

/// A form section that holds one photo: the thumbnail, the camera when the device has
/// one, the library picker, and a remove button. With no photo yet the thumbnail is the
/// placeholder, which shows where the picked photo will go; the buttons below it, not
/// the square, are what the user taps. Whatever is picked or captured goes through
/// `PhotoData.stored(from:)` at once, so the binding never holds more than the stored
/// size. Each screen says in `footer` what it keeps.
struct PhotoPickerSection: View {
    @Binding var photo: Data?
    let isBusy: Bool
    let footer: String

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var pickerItem: PhotosPickerItem?
    @State private var isCameraPresented = false
    @State private var loadError: String?

    init(photo: Binding<Data?>, isBusy: Bool = false, footer: String) {
        _photo = photo
        self.isBusy = isBusy
        self.footer = footer
    }

    private var hasCamera: Bool {
        UIImagePickerController.isSourceTypeAvailable(.camera)
    }

    /// Whether the thumbnail gets a row of its own. The placeholder is not drawn at
    /// accessibility type sizes, and a row whose whole content is missing would be a
    /// blank cell between the header and the buttons.
    private var showsThumbnail: Bool {
        photo != nil || !dynamicTypeSize.isAccessibilitySize
    }

    var body: some View {
        Section {
            if showsThumbnail {
                PhotoThumbnail(data: photo, size: 72)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Photo")
                    .accessibilityHidden(photo == nil)
            }
            if hasCamera {
                Button {
                    isCameraPresented = true
                } label: {
                    Label("Take photo", systemImage: "camera")
                }
                .disabled(isBusy)
                .fullScreenCover(isPresented: $isCameraPresented) {
                    CameraCaptureView(
                        onCapture: { image in
                            isCameraPresented = false
                            if let data = image.jpegData(compressionQuality: 0.9) {
                                set(data)
                            } else {
                                loadError = "The photo could not be encoded."
                            }
                        },
                        onCancel: { isCameraPresented = false }
                    )
                    .ignoresSafeArea()
                }
            }
            PhotosPicker(selection: $pickerItem, matching: .images) {
                Label(photo == nil ? "Choose photo" : "Choose another photo", systemImage: "photo.on.rectangle")
            }
            .disabled(isBusy)
            .onChange(of: pickerItem) { _, item in
                guard let item else { return }
                Task { await load(item) }
            }
            if photo != nil {
                Button("Remove photo", role: .destructive) { set(nil) }
                    .disabled(isBusy)
            }
            if let loadError {
                Text(loadError)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Photo")
        } footer: {
            Text(footer)
        }
    }

    /// Reads the picked item as raw image data; HEIC and JPEG both decode through ImageIO.
    private func load(_ item: PhotosPickerItem) async {
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                loadError = "That item could not be read as a photo."
                return
            }
            set(data)
        } catch {
            AppLog.estimation.error("photo load failed: \(error.localizedDescription, privacy: .public)")
            loadError = "Could not load the photo: \(error.localizedDescription)"
        }
    }

    /// Stores the downscaled bytes, or clears them. A file that is not an image is refused.
    private func set(_ data: Data?) {
        guard let data else {
            photo = nil
            pickerItem = nil
            return
        }
        guard let stored = PhotoData.stored(from: data) else {
            loadError = "That file is not a photo the device can read."
            return
        }
        loadError = nil
        photo = stored
        pickerItem = nil
    }
}

#if DEBUG
/// Preview-only: owns the binding the section edits.
private struct PhotoPickerPreview: View {
    @State var photo: Data?
    var isBusy = false
    let footer: String

    var body: some View {
        Form {
            PhotoPickerSection(photo: $photo, isBusy: isBusy, footer: footer)
        }
    }
}

#Preview("Empty") {
    PhotoPickerPreview(photo: nil, footer: "Shown with the recipe and every entry logged from it.")
}

#Preview("With a photo") {
    PhotoPickerPreview(
        photo: PreviewStore.samplePhoto,
        footer: "Used on this device only. You choose whether to keep it when you log."
    )
}

#Preview("Busy, accessibility 5") {
    PhotoPickerPreview(
        photo: PreviewStore.samplePhoto, isBusy: true,
        footer: "Used on this device only. You choose whether to keep it when you log."
    )
    .environment(\.dynamicTypeSize, .accessibility5)
}
#endif
