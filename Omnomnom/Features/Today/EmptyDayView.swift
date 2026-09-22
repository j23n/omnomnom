import DeveloperToolsSupport
import SwiftUI

/// The card for a day without entries, under the mark. On today, with something logged
/// yesterday, it offers to copy those entries; any other day only points at the Add button.
struct EmptyDayView: View {
    let canCopyYesterday: Bool
    let isCopying: Bool
    let copyYesterday: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label {
                Text("Nothing logged")
            } icon: {
                BiteMark()
                    .fill(.tint)
                    .frame(width: 56, height: 56)
            }
        } description: {
            Text("Use Add food below.")
        } actions: {
            if canCopyYesterday {
                Button("Copy yesterday", action: copyYesterday)
                    .buttonStyle(.bordered)
                    .disabled(isCopying)
            }
        }
    }
}

#if DEBUG
#Preview("Nothing to copy", traits: .sizeThatFitsLayout) {
    EmptyDayView(canCopyYesterday: false, isCopying: false) {}
}

#Preview("Yesterday has entries", traits: .sizeThatFitsLayout) {
    EmptyDayView(canCopyYesterday: true, isCopying: false) {}
}

#Preview("Copying, accessibility 5", traits: .sizeThatFitsLayout) {
    EmptyDayView(canCopyYesterday: true, isCopying: true) {}
        .environment(\.dynamicTypeSize, .accessibility5)
}
#endif
