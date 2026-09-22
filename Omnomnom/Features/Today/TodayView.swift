import Foundation
import SwiftData
import SwiftUI

/// Date header, daily totals, entries grouped by meal slot, add button.
struct TodayView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var model: TodayViewModel

    /// Starts from `model`; previews pass one with a banner or the unauthorized notice already up.
    init(model: TodayViewModel = TodayViewModel()) {
        _model = State(initialValue: model)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                DayHeader(model: model)
                DayEntriesView(day: model.selectedDay, model: model)
            }
            .navigationTitle("Today")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        model.isAddPresented = true
                    } label: {
                        Label("Add food", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $model.isAddPresented) {
                AddFoodSheet(mode: .log(
                    day: model.selectedDay,
                    onLogged: { model.handle($0) },
                    onMessage: { model.banner = $0 }
                ))
            }
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 8) {
                    if model.showsUnauthorizedNotice {
                        UnauthorizedNoticeView { model.showsUnauthorizedNotice = false }
                    }
                    if let banner = model.banner {
                        BannerView(message: banner) { model.banner = nil }
                    }
                }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    model.sceneBecameActive()
                }
            }
        }
    }
}

/// Previous / next day arrows around a tappable date that opens a graphical picker.
private struct DayHeader: View {
    @Bindable var model: TodayViewModel

    var body: some View {
        HStack {
            Button {
                model.showPreviousDay()
            } label: {
                Image(systemName: "chevron.left")
            }
            .accessibilityLabel("Previous day")
            Spacer()
            Button(model.dayTitle) {
                model.isDatePickerPresented = true
            }
            .font(.headline)
            .popover(isPresented: $model.isDatePickerPresented) {
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
            Spacer()
            Button {
                model.showNextDay()
            } label: {
                Image(systemName: "chevron.right")
            }
            .accessibilityLabel("Next day")
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }
}

#if DEBUG
#Preview("Empty day") {
    TodayView()
        .previewEnvironment(seed: .empty)
}

#Preview("First run") {
    TodayView()
        .previewEnvironment(seed: .firstRun)
}

#Preview("Typical day") {
    TodayView()
        .previewEnvironment(seed: .typicalDay)
}

#Preview("Health states") {
    TodayView()
        .previewEnvironment(seed: .healthStates)
}

#Preview("With foreign samples") {
    TodayView()
        .previewEnvironment(seed: .typicalDay, health: PreviewHealth())
}

#Preview("Accessibility 5") {
    TodayView()
        .previewEnvironment(seed: .typicalDay)
        .environment(\.dynamicTypeSize, .accessibility5)
}

#Preview("Dark") {
    TodayView()
        .previewEnvironment(seed: .typicalDay)
        .preferredColorScheme(.dark)
}

#Preview("Banner") {
    let model = TodayViewModel()
    model.banner = LogResult(entryID: UUID(), written: [], healthError: nil, storeError: nil).bannerMessage
    return TodayView(model: model)
        .previewEnvironment(seed: .typicalDay)
}

#Preview("Unauthorized notice") {
    let model = TodayViewModel()
    model.showsUnauthorizedNotice = true
    return TodayView(model: model)
        .previewEnvironment(seed: .healthStates)
}

#Preview("Past day") {
    let model = TodayViewModel()
    model.selectedDay = Calendar.current.date(byAdding: .day, value: -1, to: .now) ?? .now
    return TodayView(model: model)
        .previewEnvironment(seed: .typicalDay)
}

#Preview("Banner and notice stacked") {
    let model = TodayViewModel()
    model.banner = LogResult(entryID: UUID(), written: [], healthError: nil, storeError: nil).bannerMessage
    model.showsUnauthorizedNotice = true
    return TodayView(model: model)
        .previewEnvironment(seed: .healthStates)
}
#endif
