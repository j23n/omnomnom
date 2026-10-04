import AppIntents
import Foundation

/// Opens the app on a food the system was showing.
///
/// Visual intelligence runs this when someone taps one of the app's results, in this
/// process, with no view of its own to push. So it reads the food's values and leaves
/// the choice on `AppRouter` for Today to pick up and open the Quantity sheet with.
///
/// The entity carries only enough text to be drawn, so the values are read again here
/// rather than trusted from it. A food whose id no longer exists — the bundled database
/// is replaced wholesale by an app update — opens the app and nothing more, which is
/// what the system would have done anyway.
///
/// Not `nonisolated`, for the same reason as the two queries: `@Parameter` and
/// `@Dependency` are property wrappers and so mutable stored properties. `perform()`
/// keeps its explicit annotation, which the type now also supplies, because it is the
/// isolation the body actually needs to reach `AppRouter`.
struct OpenFoodIntent: OpenIntent {
    static let title: LocalizedStringResource = "Open Food"

    @Parameter(title: "Food", requestValueDialog: "Which food?")
    var target: FoodEntity

    @Dependency private var repository: FoodRepository
    @Dependency private var router: AppRouter

    @MainActor
    func perform() async throws -> some IntentResult {
        if let food = try? await repository.food(id: target.id) {
            router.open(FoodChoice(bundled: food))
        }
        return .result()
    }
}
