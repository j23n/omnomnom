import SwiftUI

/// Plain-language explanation shown before the system Health sheet.
struct PermissionPrimerView: View {
    let isHealthAvailable: Bool
    let isRequesting: Bool
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Spacer()
            Text("Writing to Health")
                .font(.largeTitle.bold())
            Text("Each entry is written to Health as one food with these nutrients:")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Nutrient.allCases, id: \.self) { nutrient in
                    Label(nutrient.displayName, systemImage: "checkmark")
                }
            }
            .font(.callout)
            Text("Health shows write permission only; if you decline, the app keeps a local log.")
                .foregroundStyle(.secondary)
            Spacer()
            Button(isHealthAvailable ? "Connect Health" : "Continue without Health", action: action)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(isRequesting)
                .frame(maxWidth: .infinity)
        }
        .padding(32)
    }
}
