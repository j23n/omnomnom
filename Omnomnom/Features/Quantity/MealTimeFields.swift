import SwiftUI

/// Which meal this is and when it was eaten: the two questions every screen that logs
/// something has to ask, in the same order and the same words wherever it asks them.
///
/// Two rows rather than a `Section` of its own, because one of the four callers asks a
/// third question in the same section — whether to keep the photograph — and a section
/// boundary there would read as a different subject rather than the same one continued.
struct MealTimeFields: View {
    @Binding var mealSlot: MealSlot
    @Binding var timestamp: Date

    var body: some View {
        Group {
            Picker("Meal", selection: $mealSlot) {
                ForEach(MealSlot.allCases, id: \.self) { slot in
                    Text(slot.displayName).tag(slot)
                }
            }
            DatePicker("Time", selection: $timestamp, displayedComponents: [.date, .hourAndMinute])
        }
    }
}
