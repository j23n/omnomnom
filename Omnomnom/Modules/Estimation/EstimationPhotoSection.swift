import CoreTransferable
import Foundation
import os
import PhotosUI
import SwiftUI
import UIKit

/// The photo controls of the sheet, shown only on iOS 27 with the model available: a
/// library picker, the camera when there is one, and the thumbnail with a remove button.
/// The photo is kept as data in memory for the request and dropped with the sheet.
struct EstimationPhotoSection: View {
    @Binding var photo: Data?
    let isBusy: Bool

    @State private var pickerItem: PhotosPickerItem?
    @State private var thumbnail: UIImage?
    @State private var isCameraPresented = false
    @State private var loadError: String?

    private var hasCamera: Bool {
        UIImagePickerController.isSourceTypeAvailable(.camera)
    }

    var body: some View {
        Section {
            if let thumbnail {
                HStack {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 72, height: 72)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .accessibilityLabel("Photo of the meal")
                    Spacer()
                    Button("Remove", role: .destructive) { set(nil) }
                        .buttonStyle(.borderless)
                        .disabled(isBusy)
                }
            }
            PhotosPicker(selection: $pickerItem, matching: .images) {
                Label(thumbnail == nil ? "Choose photo" : "Choose another photo", systemImage: "photo.on.rectangle")
            }
            .disabled(isBusy)
            .onChange(of: pickerItem) { _, item in
                guard let item else { return }
                Task { await load(item) }
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
                            if let data = image.jpegData(compressionQuality: 0.8) {
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
            if let loadError {
                Text(loadError)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Photo")
        } footer: {
            Text("The photo stays in memory on this device and is not saved anywhere.")
        }
    }

    /// Reads the picked item as raw image data; HEIC and JPEG both decode later through ImageIO.
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

    /// Stores the data and a small thumbnail, or clears both. A file that is not an image is refused.
    private func set(_ data: Data?) {
        guard let data else {
            photo = nil
            thumbnail = nil
            pickerItem = nil
            return
        }
        guard let image = EstimationImage.downscaled(data, maxPixelSize: EstimationImage.thumbnailPixelSize) else {
            loadError = "That file is not a photo the device can read."
            return
        }
        loadError = nil
        photo = data
        thumbnail = UIImage(cgImage: image)
    }
}
