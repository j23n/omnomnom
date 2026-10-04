import SwiftUI

/// Which three figures sit beside energy on Today.
///
/// A width constraint and nothing else: four large figures is what a phone holds at the
/// type sizes people use. Which three a person wants is not a decision this app is in a
/// position to make for them — someone watching carbohydrates and someone watching fiber
/// are both using it correctly — so it is a choice rather than a default dressed up as
/// one. Trends charts all eight regardless.
struct HeadlinePickerView: View {
    @AppStorage(HeadlineNutrients.key) private var raw = HeadlineNutrients.encode(HeadlineNutrients.standard)

    private var chosen: [Nutrient] { HeadlineNutrients.decode(raw) }

    var body: some View {
        List {
            Section {
                ForEach(HeadlineNutrients.selectable, id: \.self) { nutrient in
                    Button {
                        toggle(nutrient)
                    } label: {
                        HStack {
                            Text(nutrient.displayName)
                            Spacer()
                            if chosen.contains(nutrient) {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.tint)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(chosen.contains(nutrient) ? [.isSelected] : [])
                }
            } header: {
                Text("Beside energy")
            } footer: {
                Text("Energy always leads. Pick three to sit beside it; the other four stay in the smaller row, and Trends charts all eight.")
            }
        }
        .navigationTitle("Headline figures")
    }

    /// Selecting a fourth drops the one chosen longest ago, so the row is always full and
    /// nobody has to deselect before selecting.
    private func toggle(_ nutrient: Nutrient) {
        var next = chosen
        if let index = next.firstIndex(of: nutrient) {
            guard next.count > 1 else { return }
            next.remove(at: index)
        } else {
            next.append(nutrient)
            if next.count > HeadlineNutrients.count { next.removeFirst() }
        }
        raw = HeadlineNutrients.encode(next)
    }
}

#if DEBUG
#Preview("Headline figures") {
    NavigationStack {
        HeadlinePickerView()
    }
}
#endif
