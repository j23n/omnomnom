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

/// One Library row, whichever kind of item it stands for: the photo, the name, one quiet
/// line of figures, the tags, and a chevron, reading as a single button. The two kinds
/// differ only in the caption they compute and in what the row opens, so both are passed
/// in rather than branched on here.
struct LibraryRow: View {
    let photo: Data?
    let name: String
    let caption: String
    let tags: [Tag]?
    let hint: String

    var body: some View {
        HStack(spacing: 12) {
            PhotoThumbnail(data: photo, size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                ValueText(caption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TagLine(tags: tags)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(hint)
    }
}

/// Name, servings and energy per serving of one recipe, with its photo when it has one
/// and its tags when it carries any. The row opens the recipe editor, so it carries a
/// chevron and reads as a button.
struct RecipeRow: View {
    let recipe: Recipe

    /// "4 servings · 150 kcal per serving", wrapping as one line of text.
    private var caption: String {
        [
            Formatters.servings(recipe.servings),
            "\(Formatters.amount(recipe.perServing.energy, unit: .kilocalorie)) per serving"
        ].joined(separator: " · ")
    }

    var body: some View {
        LibraryRow(
            photo: recipe.photo?.data, name: recipe.name, caption: caption,
            tags: recipe.tags, hint: "Opens the recipe"
        )
    }
}

/// Name and energy per 100 of one custom food or product, in the food's own unit, with
/// the brand of a product, the user's photo when there is one and the tags when it
/// carries any. The row opens the food editor, so it carries a chevron and reads as a
/// button.
struct CustomFoodRow: View {
    let food: Food

    /// "Whole Earth · 588 kcal per 100 g", wrapping as one line of text.
    private var caption: String {
        var parts: [String] = []
        if let brand = food.brand {
            parts.append(brand)
        }
        parts.append("\(Formatters.amount(food.per100g.energy, unit: .kilocalorie)) \(food.measure.referenceText)")
        return parts.joined(separator: " · ")
    }

    var body: some View {
        LibraryRow(
            photo: food.photo?.data, name: food.name, caption: caption,
            tags: food.tags, hint: "Opens the food"
        )
    }
}

/// The tags on a row, one quiet line under the figures; nothing at all when there are
/// none. Names only: chips here would compete with the row's own tap target.
struct TagLine: View {
    let tags: [Tag]?

    private var names: [String] {
        (tags ?? []).map(\.name).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    var body: some View {
        if !names.isEmpty {
            Text(names.joined(separator: " · "))
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(2)
        }
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

#Preview("Accessibility 5", traits: .sizeThatFitsLayout) {
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
    .environment(\.dynamicTypeSize, .accessibility5)
}
#endif
