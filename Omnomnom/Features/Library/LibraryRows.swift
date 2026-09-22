import DeveloperToolsSupport
import Foundation
import SwiftData
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

/// Name, servings and energy per serving of one recipe, with its photo when it has one.
struct RecipeRow: View {
    let recipe: Recipe

    var body: some View {
        HStack(spacing: 12) {
            PhotoThumbnail(data: recipe.photo?.data, size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(recipe.name)
                HStack(spacing: 6) {
                    Text(Formatters.servings(recipe.servings))
                    Text("\(Formatters.amount(recipe.perServing.energy, unit: .kilocalorie)) per serving")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// Name and energy per 100 g of one custom food or product, with the brand of a
/// product and the user's photo when there is one.
struct CustomFoodRow: View {
    let food: Food

    var body: some View {
        HStack(spacing: 12) {
            PhotoThumbnail(data: food.photo?.data, size: 44)
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
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

#if DEBUG
#Preview("Library rows", traits: .sizeThatFitsLayout) {
    let container = PreviewStore.container(seed: .library)
    return VStack(alignment: .leading, spacing: 16) {
        ForEach(PreviewStore.recipes(in: container)) { recipe in
            RecipeRow(recipe: recipe)
        }
        ForEach(PreviewStore.foods(in: container).filter { $0.kind != .bundled }) { food in
            CustomFoodRow(food: food)
        }
    }
    .padding()
    .modelContainer(container)
}
#endif
