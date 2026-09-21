import Foundation
import os
import SwiftUI

/// Describe a meal in words, add a photo on iOS 27, and get a draft to check. The
/// request runs in a cancellable task; the draft screen is pushed on success and hands
/// its banner message back through `onLogged` once the entries are saved.
struct EstimationSheet: View {
    let day: Date
    let onLogged: (String) -> Void
    private let estimator: any MealEstimating

    @Environment(\.dismiss) private var dismiss
    @State private var description = ""
    @State private var photo: Data?
    @State private var availability: EstimationAvailability?
    @State private var isEstimating = false
    @State private var errorMessage: String?
    @State private var draft: EstimateDraft?
    @State private var task: Task<Void, Never>?

    init(day: Date, estimator: any MealEstimating = FoundationMealEstimator(), onLogged: @escaping (String) -> Void) {
        self.day = day
        self.estimator = estimator
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
                    EstimationPhotoSection(photo: $photo, isBusy: isEstimating)
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
                EstimateDraftView(draft: draft, day: day, onLogged: onLogged)
            }
            .task { availability = EstimationAvailability.current() }
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
