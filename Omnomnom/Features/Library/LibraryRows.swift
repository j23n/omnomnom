import Foundation
import SwiftUI

/// Which editor sheet the Library shows; a `nil` payload creates a new item.
enum LibraryEditor: Identifiable {
    case recipe(Recipe?)
    case food(Food?)

    var id: String {
        switch self {
        case .recipe(let recipe): "recipe-\(recipe?.id.uuidString ?? "new")"
        case .food(let food): "food-\(food?.id.uuidString ?? "new")"
        }
    }
}

/// Name, servings and energy per serving of one recipe.
struct RecipeRow: View {
    let recipe: Recipe

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(recipe.name)
            HStack(spacing: 6) {
                Text(Formatters.servings(recipe.servings))
                Text("\(Formatters.amount(recipe.perServing.energy, unit: .kilocalorie)) per serving")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// Name and energy per 100 g of one custom food or product, with the brand of a product.
struct CustomFoodRow: View {
    let food: Food

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(food.name)
            HStack(spacing: 6) {
                if let brand = food.brand {
                    Text(brand)
                }
                Text("\(Formatters.amount(food.per100g.energy, unit: .kilocalorie)) per 100 g")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}
