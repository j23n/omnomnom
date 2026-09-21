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
                AddFoodSheet(day: model.selectedDay) { result in
                    model.handle(result)
                }
            }
            .safeAreaInset(edge: .bottom) {
                if let banner = model.banner {
                    BannerView(message: banner) { model.banner = nil }
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

/// Non-blocking notice at the bottom of Today, dismissed by tap.
private struct BannerView: View {
    let message: String
    let dismiss: () -> Void

    var body: some View {
        Button(action: dismiss) {
            HStack {
                Text(message)
                    .font(.footnote)
                    .multilineTextAlignment(.leading)
                Spacer()
                Image(systemName: "xmark")
                    .font(.footnote)
            }
            .padding()
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Notice: \(message). Double tap to dismiss.")
    }
}
