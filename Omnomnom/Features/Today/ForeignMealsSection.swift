import DeveloperToolsSupport
import Foundation
import SwiftUI

/// Foods other apps or the Health app wrote for the day: name, source, time and energy.
/// No swipe actions and no edit affordance, because HealthKit lets only the writer change them.
struct ForeignMealsSection: View {
    let meals: [ForeignMeal]

    var body: some View {
        Section("Also in Health") {
            ForEach(meals) { meal in
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(meal.name)
                        Text("\(meal.sourceName) · \(meal.start.formatted(date: .omitted, time: .shortened))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    ValueText(meal.nutrition.energy, unit: .kilocalorie)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityHint("Written by another app")
            }
        }
    }
}

#if DEBUG
#Preview("Also in Health", traits: .fixedLayout(width: 393, height: 260)) {
    List {
        ForeignMealsSection(
            meals: DayHealthSummary.make(from: PreviewHealth.defaultForeignSamples, localEntryIDs: []).meals
        )
    }
    .listStyle(.insetGrouped)
}

#Preview("Accessibility 5", traits: .fixedLayout(width: 393, height: 420)) {
    List {
        ForeignMealsSection(
            meals: DayHealthSummary.make(from: PreviewHealth.defaultForeignSamples, localEntryIDs: []).meals
        )
    }
    .listStyle(.insetGrouped)
    .environment(\.dynamicTypeSize, .accessibility5)
}
#endif
