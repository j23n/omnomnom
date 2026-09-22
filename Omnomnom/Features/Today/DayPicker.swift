import DeveloperToolsSupport
import Foundation
import SwiftUI

/// The calendar behind the toolbar button, shown as a sheet. A graphical `DatePicker`
/// has no firm ideal width, so a popover would squeeze it into a strip; a sheet gives
/// it the full width. Choosing a day selects it and closes the sheet, and Done closes
/// it without changing the day.
struct DayPicker: View {
    let model: TodayViewModel

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                DatePicker(
                    "Day",
                    selection: Binding(
                        get: { model.selectedDay },
                        set: { model.select(day: $0) }
                    ),
                    displayedComponents: .date
                )
                .datePickerStyle(.graphical)
                .padding(.horizontal)
                // One tap on a day is enough; the sheet goes as soon as the day changes.
                .onChange(of: model.selectedDay) { _, _ in dismiss() }
            }
            // The calendar fits as it is and only scrolls once it no longer does.
            .scrollBounceBehavior(.basedOnSize)
            .navigationTitle("Choose a day")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.large, .medium])
        .presentationDragIndicator(.visible)
    }
}

#if DEBUG
#Preview("Day picker", traits: .sizeThatFitsLayout) {
    DayPicker(model: TodayViewModel())
}

#Preview("Accessibility 5", traits: .sizeThatFitsLayout) {
    DayPicker(model: TodayViewModel())
        .environment(\.dynamicTypeSize, .accessibility5)
}
#endif
