import Foundation
import Testing
@testable import Omnomnom

/// Choosing which bundled foods answer a camera pointed at food.
struct VisualFoodMatchTests {
    private func food(_ id: Int, _ name: String) -> BundledFood {
        BundledFood(id: id, name: name, category: nil, per100g: Nutrition(energy: 50), popularity: 0)
    }

    @Test func theBestMatchForEachLabelComesFirst() {
        let foods = VisualFoodMatch.best(from: [
            (label: "apple", foods: [food(1, "Apple pie filling, canned"), food(2, "Apple raw")]),
        ])
        #expect(foods.map(\.name) == ["Apple raw", "Apple pie filling, canned"])
    }

    @Test func aFoodFoundByTwoLabelsAppearsOnceAtItsBetterScore() {
        // "fruit" says almost nothing about "Bananas, raw" and would leave it under the
        // dried fruit. "banana" says a great deal, and that is the score it keeps.
        let banana = food(1, "Bananas, raw")
        let dried = food(2, "Dried fruit mix")
        #expect(VisualFoodMatch.best(from: [(label: "fruit", foods: [banana, dried])]).map(\.id)
            == [2, 1])

        let both = VisualFoodMatch.best(from: [
            (label: "fruit", foods: [banana, dried]),
            (label: "banana", foods: [banana]),
        ])
        #expect(both.map(\.id) == [1, 2])
        #expect(both.filter { $0.id == 1 }.count == 1)
    }

    @Test func labelsThatFindNothingAreHarmless() {
        let foods = VisualFoodMatch.best(from: [
            (label: "tower", foods: []),
            (label: "apple", foods: [food(1, "Apple raw")]),
        ])
        #expect(foods.map(\.id) == [1])
    }

    @Test func nothingFoundIsNoResults() {
        #expect(VisualFoodMatch.best(from: []).isEmpty)
        #expect(VisualFoodMatch.best(from: [(label: "tower", foods: [])]).isEmpty)
    }

    @Test func theSameSceneAlwaysAnswersTheSameWay() {
        // Three rows no label explains, so all three score the same; ids break the tie
        // rather than a dictionary's iteration order.
        let unexplained = [food(7, "Lentil soup"), food(3, "Butter"), food(5, "Rye bread")]
        let first = VisualFoodMatch.best(from: [(label: "tower", foods: unexplained)])
        #expect(first.map(\.id) == [3, 5, 7])
        for _ in 0..<5 {
            #expect(VisualFoodMatch.best(from: [(label: "tower", foods: unexplained)]).map(\.id) == [3, 5, 7])
        }
    }

    @Test func onlyAScreenfulGoesBack() {
        let many = (1...40).map { food($0, "Apple variety \($0)") }
        #expect(VisualFoodMatch.best(from: [(label: "apple", foods: many)]).count == VisualFoodMatch.limit)
        #expect(VisualFoodMatch.best(from: [(label: "apple", foods: many)], limit: 3).count == 3)
    }

    @Test func aLabelIsScoredLikeAnyOtherQuery() {
        // The same scorer the typed search uses, so the camera and the keyboard agree.
        let viaLabel = VisualFoodMatch.best(from: [
            (label: "oat", foods: [food(1, "Oat whole grain, raw"), food(2, "Overnight oats")]),
        ])
        #expect(viaLabel.map(\.id) == [1, 2])
        #expect(SearchRelevance.score(name: "Oat whole grain, raw", query: "oat")
            > SearchRelevance.score(name: "Overnight oats", query: "oat"))
    }
}

/// The slot an app intent leaves a food in.
@MainActor
struct AppRouterTests {
    private let choice = FoodChoice(
        source: .bundled(id: 1), name: "Apple raw", perUnit: Nutrition(energy: 52)
    )

    @Test func aFoodWaitsUntilItIsTaken() {
        let router = AppRouter()
        #expect(router.pendingChoice == nil)
        router.open(choice)
        #expect(router.pendingChoice == choice)
        router.clearPendingChoice()
        #expect(router.pendingChoice == nil)
    }

    @Test func aSecondFoodReplacesOneNobodyActedOn() {
        let router = AppRouter()
        let other = FoodChoice(source: .bundled(id: 2), name: "Bananas, raw", perUnit: Nutrition(energy: 89))
        router.open(choice)
        router.open(other)
        #expect(router.pendingChoice == other)
    }
}
