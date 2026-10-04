import SwiftUI

/// What kind of day this is, and the one tap that settles it.
///
/// Marking a day complete is the whole mechanism behind a defensible average: Trends
/// means over complete days only and says so. Without it every mean silently divides by
/// days holding nothing.
///
/// It says what is there and never what share of something it is. "19 of 30 days" and
/// "63 per cent" are the same fact, and the second grades the user's diligence — a worse
/// failure than grading their diet, since the app's claim to stay a logging tool is that
/// it does not grade, and diligence is not even the thing being measured. So no
/// percentage, no ratio, no progress bar, and nothing that reads as a target.
struct DayCoverageRow: View {
    let state: DayState
    /// False on a day the sampling cadence did not ask about, where the app stays quiet.
    /// The figures are still shown and a day marked complete still counts; what goes is
    /// the prompt.
    var isAsked = true
    let onToggle: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(state.note)
                .font(.footnote)
                .foregroundStyle(.secondary)
            Spacer(minLength: 12)
            if state != .empty, isAsked || state == .complete {
                Button(action: onToggle) {
                    Text(state == .complete ? "Marked" : "That's everything")
                        .font(.footnote)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityLabel(
                    state == .complete
                        ? "Marked as everything for this day. Tap to unmark."
                        : "Mark this day as everything you ate."
                )
            }
        }
        .accessibilityElement(children: .contain)
    }
}

#if DEBUG
#Preview("Every state", traits: .sizeThatFitsLayout) {
    List {
        ForEach(DayState.allCases, id: \.self) { state in
            DayCoverageRow(state: state) {}
        }
    }
}

#Preview("Accessibility 5", traits: .sizeThatFitsLayout) {
    List {
        DayCoverageRow(state: .partial) {}
        DayCoverageRow(state: .complete) {}
    }
    .environment(\.dynamicTypeSize, .accessibility5)
}
#endif
