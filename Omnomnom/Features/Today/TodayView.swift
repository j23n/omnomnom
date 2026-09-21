import Foundation
import SwiftData
import SwiftUI

/// Date header, daily totals, entries grouped by meal slot, add button.
struct TodayView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var model = TodayViewModel()

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
                AddFoodSheet(mode: .log(day: model.selectedDay, onLogged: { result in
                    model.handle(result)
                }))
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
