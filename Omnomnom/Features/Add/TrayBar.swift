import DeveloperToolsSupport
import SwiftUI

/// The tray: how much is in it, what it comes to, and the one button that logs it.
///
/// What it is for is the visit that gathers four foods. One at a time, every food cost a
/// sheet, a weight and a closed screen, so the second food meant opening the screen again.
/// Here a tap puts a food in the tray and the screen stays exactly where it is.
///
/// The summary is a button of its own and leads to the screen a typed line is signed off
/// on, which is where an amount gets changed. Log takes the amounts as they stand — what
/// this person last had of each food, or 100 g of one they have never had — because the
/// common case for gathering four foods is four usual amounts.
///
/// It says that nothing is logged yet, in those words. A row that goes quietly into a tray
/// looks exactly like a row that was logged, and the difference is worth a line.
struct TrayBar: View {
    let tray: LineResolution
    let onReview: () -> Void
    let onLog: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onReview) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(Self.title(tray))
                            .font(.subheadline.weight(.medium))
                        Text("Not logged yet. Tap to change amounts.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Image(systemName: "chevron.forward")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens the tray, where the amounts are set")
            Button("Log", action: onLog)
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .buttonBorderShape(.capsule)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .readableColumn(ReadableColumn.control)
        .animation(.default, value: tray.rows.count)
    }

    /// "3 foods · 740 kcal", or the one food's own name, which says more than "1 food".
    static func title(_ tray: LineResolution) -> String {
        let what = tray.rows.count == 1
            ? (tray.rows.first?.displayName ?? "1 food")
            : "\(tray.rows.count) foods"
        guard let energy = tray.total.energy else { return what }
        return "\(what) · \(Formatters.amount(energy, unit: .kilocalorie))"
    }
}

#if DEBUG
private func trayRow(_ name: String, kcal: Double, amount: Double) -> ResolvedRow {
    ResolvedRow(
        name: name,
        choice: FoodChoice(
            source: .bundled(id: abs(name.hashValue % 10_000)),
            name: name,
            perUnit: Nutrition(energy: kcal, protein: 9, carbohydrates: 60, fatTotal: 7)
        ),
        amount: amount,
        baseAmount: amount,
        origin: .chosen,
        confidence: .settled
    )
}

private func tray(_ rows: [ResolvedRow]) -> LineResolution {
    LineResolution(line: "", rows: rows, wasChecked: false)
}

#Preview("One food", traits: .sizeThatFitsLayout) {
    TrayBar(tray: tray([trayRow("Oat flakes", kcal: 372, amount: 45)]), onReview: {}, onLog: {})
}

#Preview("Four foods", traits: .sizeThatFitsLayout) {
    TrayBar(
        tray: tray([
            trayRow("Oat flakes", kcal: 372, amount: 45),
            trayRow("Banana", kcal: 89, amount: 120),
            trayRow("Milk, semi-skimmed", kcal: 47, amount: 200),
            trayRow("Coffee, black", kcal: 2, amount: 250)
        ]),
        onReview: {}, onLog: {}
    )
}

#Preview("A food with no energy figure", traits: .sizeThatFitsLayout) {
    let row = ResolvedRow(
        name: "Chewing gum",
        choice: FoodChoice(source: .bundled(id: 9), name: "Chewing gum", perUnit: Nutrition()),
        amount: 3,
        origin: .chosen,
        confidence: .settled
    )
    return TrayBar(tray: tray([row]), onReview: {}, onLog: {})
}

#Preview("A long name", traits: .sizeThatFitsLayout) {
    TrayBar(
        tray: tray([trayRow("Bolognese-style pasta (spaghetti, tagliatelle…)", kcal: 131, amount: 320)]),
        onReview: {}, onLog: {}
    )
}

#Preview("Accessibility 5", traits: .sizeThatFitsLayout) {
    TrayBar(
        tray: tray([
            trayRow("Oat flakes", kcal: 372, amount: 45),
            trayRow("Banana", kcal: 89, amount: 120)
        ]),
        onReview: {}, onLog: {}
    )
    .environment(\.dynamicTypeSize, .accessibility5)
}

#Preview("iPad width", traits: .fixedLayout(width: 1024, height: 120)) {
    TrayBar(
        tray: tray([trayRow("Oat flakes", kcal: 372, amount: 45)]),
        onReview: {}, onLog: {}
    )
}
#endif
