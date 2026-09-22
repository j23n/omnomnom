import Foundation
import os
import SwiftUI

/// Describe a meal in words, add a photo on iOS 27, and get a draft to check. The
/// request runs in a cancellable task; the draft screen is pushed on success, offers to
/// keep the photo with the entries, and hands its banner message back through
/// `onLogged` once they are saved.
struct EstimationSheet: View {
    let day: Date
    let onLogged: (String) -> Void
    private let estimator: any MealEstimating
    /// A fixed model state for previews; `nil` reads the model.
    private let fixedAvailability: EstimationAvailability?

    @Environment(\.dismiss) private var dismiss
    @State private var description = ""
    @State private var photo: Data?
    @State private var availability: EstimationAvailability?
    @State private var isEstimating = false
    @State private var errorMessage: String?
    @State private var draft: EstimateDraft?
    @State private var task: Task<Void, Never>?

    init(
        day: Date, estimator: any MealEstimating = FoundationMealEstimator(),
        availability: EstimationAvailability? = nil, onLogged: @escaping (String) -> Void
    ) {
        self.day = day
        self.estimator = estimator
        self.fixedAvailability = availability
        self.onLogged = onLogged
    }

    private var hasInput: Bool {
        photo != nil || !EstimationPrompt.clean(description).isEmpty
    }

    private var canEstimate: Bool {
        hasInput && !isEstimating && availability?.isAvailable == true
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Describe the meal") {
                    TextField("Two scrambled eggs and a slice of rye toast", text: $description, axis: .vertical)
                        .lineLimit(1...4)
                        .accessibilityLabel("Meal description")
                }
                if availability?.supportsPhoto == true {
                    PhotoPickerSection(
                        photo: $photo, isBusy: isEstimating,
                        footer: "Used on this device only. You choose whether to keep it when you log."
                    )
                }
                if let availability, !availability.isAvailable {
                    Section {
                        Text(availability.message)
                            .foregroundStyle(.secondary)
                    }
                }
                Section {
                    if isEstimating {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("Estimating…")
                            Spacer()
                            Button("Cancel") { cancel() }
                        }
                    } else {
                        Button("Estimate") { start() }
                            .disabled(!canEstimate)
                    }
                    if let errorMessage {
                        Text(errorMessage)
                            .foregroundStyle(.secondary)
                    }
                } footer: {
                    Text("Estimates are rough and made on this device. You check every value before it is logged.")
                }
            }
            .navigationTitle("Estimate a meal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .navigationDestination(item: $draft) { draft in
                EstimateDraftView(draft: draft, day: day, photo: photo, onLogged: onLogged)
            }
            .task { availability = fixedAvailability ?? EstimationAvailability.current() }
            .onDisappear { task?.cancel() }
        }
    }

    /// The photo wins when there is one; the text then rides along as a hint.
    private func start() {
        guard canEstimate else { return }
        let text = EstimationPrompt.clean(description)
        let input: EstimationInput
        if let photo {
            input = .photo(photo, description: text.isEmpty ? nil : text)
        } else {
            input = .text(text)
        }
        isEstimating = true
        errorMessage = nil
        task = Task { await run(input) }
    }

    private func run(_ input: EstimationInput) async {
        do {
            let estimate = try await estimator.estimate(input)
            guard !Task.isCancelled else { return }
            let result = EstimateConversion.convert(estimate)
            if result.items.isEmpty {
                errorMessage = "Nothing recognisable came back. Try a fuller description or a clearer photo."
            } else {
                draft = EstimateDraft(result: result)
            }
        } catch {
            guard !Task.isCancelled else { return }
            errorMessage = (error as? EstimationError)?.errorDescription ?? error.localizedDescription
        }
        isEstimating = false
        task = nil
    }

    /// Stops waiting; the model may finish in the background and its answer is dropped.
    private func cancel() {
        task?.cancel()
        task = nil
        isEstimating = false
    }
}

#if DEBUG
extension EstimationSheet {
    /// Preview-only: the sheet in a chosen state, with an estimator that never reaches the
    /// model. `onLogged` is a no-op.
    init(
        previewDay day: Date,
        availability: EstimationAvailability,
        description: String = "",
        isEstimating: Bool = false,
        errorMessage: String? = nil
    ) {
        self.day = day
        self.estimator = PreviewMealEstimator()
        self.fixedAvailability = availability
        self.onLogged = { _ in }
        _description = State(initialValue: description)
        _isEstimating = State(initialValue: isEstimating)
        _errorMessage = State(initialValue: errorMessage)
    }
}

#Preview("Idle, text only (iOS 26)") {
    EstimationSheet(previewDay: .now, availability: .available(photo: false))
        .previewEnvironment(seed: .empty)
}

#Preview("Idle, with photo (iOS 27)") {
    EstimationSheet(previewDay: .now, availability: .available(photo: true))
        .previewEnvironment(seed: .empty)
}

#Preview("Running") {
    EstimationSheet(
        previewDay: .now, availability: .available(photo: false),
        description: "Two scrambled eggs and a slice of rye toast with butter", isEstimating: true
    )
    .previewEnvironment(seed: .empty)
}

#Preview("Error") {
    EstimationSheet(
        previewDay: .now, availability: .available(photo: false),
        description: "Two scrambled eggs and a slice of rye toast with butter",
        errorMessage: EstimationError.guardrail.errorDescription
    )
    .previewEnvironment(seed: .empty)
}

#Preview("Model not ready") {
    EstimationSheet(previewDay: .now, availability: .modelNotReady)
        .previewEnvironment(seed: .empty)
}

#Preview("Idle, accessibility 5") {
    EstimationSheet(previewDay: .now, availability: .available(photo: false))
        .previewEnvironment(seed: .empty)
        .environment(\.dynamicTypeSize, .accessibility5)
}
#endif
