import DeveloperToolsSupport
import Foundation
import SwiftUI

/// The graphical picker behind the calendar toolbar button, shown as a popover.
struct DayPicker: View {
    let model: TodayViewModel

    var body: some View {
        DatePicker(
            "Day",
            selection: Binding(
                get: { model.selectedDay },
                set: { model.select(day: $0) }
            ),
            displayedComponents: .date
        )
        .datePickerStyle(.graphical)
        .padding()
        .presentationCompactAdaptation(.popover)
    }
}

#if DEBUG
#Preview("Day picker", traits: .sizeThatFitsLayout) {
    DayPicker(model: TodayViewModel())
}
#endif
