import Foundation
import SwiftUI

/// Placeholder for the food and recipe library. For now it confirms the bundled
/// database is present; custom foods and recipes arrive with later increments.
struct LibraryView: View {
    @Environment(\.foodRepository) private var foodRepository
    @State private var foodCount: Int?
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List {
                Section("Bundled database") {
                    if let foodCount {
                        Text("Bundled database ready: \(foodCount) foods")
                    } else if let errorMessage {
                        Text(errorMessage)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Checking the bundled database…")
                            .foregroundStyle(.secondary)
                    }
                }
                Section {
                    Text("Custom foods and recipes arrive in a later version.")
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Library")
            .task { await loadCount() }
        }
    }

    private func loadCount() async {
        do {
            foodCount = try await foodRepository.foodCount()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
