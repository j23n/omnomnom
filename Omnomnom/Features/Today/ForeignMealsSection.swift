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
                        HStack(spacing: 6) {
                            Text(meal.sourceName)
                            Text(meal.start, style: .time)
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(Formatters.amount(meal.nutrition.energy, unit: .kilocalorie))
                        .font(.body.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityHint("Written by another app")
            }
        }
    }
}
