import Foundation
import SwiftData

/// The one list of what the local store holds.
///
/// The app, the previews and the tests each used to carry their own copy, which is a
/// footgun with a delay on it: adding a model and forgetting one of them fails at
/// container creation, in whichever of the three nobody ran first. One list means a new
/// model is registered everywhere by being added here.
nonisolated enum StoreSchema {
    static let models: [any PersistentModel.Type] = [
        Food.self,
        LogEntry.self,
        Recipe.self,
        RecipeIngredient.self,
        Photo.self,
        Tag.self,
        Phrase.self,
        PhraseItem.self,
        DayRecord.self,
    ]

    static var schema: Schema { Schema(models) }
}
