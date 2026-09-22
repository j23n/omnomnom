import Foundation
import SwiftData

/// A photo the user took or picked, kept on this device with the thing it shows: the
/// entries logged from one estimate (they share the picture of the plate), a recipe,
/// or a custom food or product. Exactly one of the three links is set. The bytes are
/// a JPEG no larger than `PhotoData.storedPixelSize` on its long side, held in external
/// storage. Never sent to Health, never fetched from Open Food Facts.
///
/// Schema rules as for the other models: no unique attributes, every attribute
/// defaulted or optional, relationships optional. The entries inverse is declared
/// here; the recipe and food inverses are declared on `Recipe` and `Food`, which own
/// the cascade.
@Model
final class Photo {
    var id: UUID = UUID()
    var createdAt: Date = Date.now
    @Attribute(.externalStorage) var data: Data?

    /// Entries that show this photo as their own; deleting the last of them deletes the photo.
    @Relationship(deleteRule: .nullify, inverse: \LogEntry.photo)
    var entries: [LogEntry]?
    var recipe: Recipe?
    var food: Food?

    /// Relate to entries, a `Recipe` or a `Food` after `context.insert(photo)`, not here.
    init(data: Data) {
        self.id = UUID()
        self.createdAt = Date.now
        self.data = data
    }

    /// The photo a recipe or food should hold after an edit: `current` when its bytes
    /// already equal `data`, a new inserted row when `data` differs, `nil` when `data`
    /// is `nil`. A replaced or removed photo is deleted from `context`; the caller
    /// assigns the result to the relationship and saves.
    static func replacing(_ current: Photo?, with data: Data?, in context: ModelContext) -> Photo? {
        if let current, current.data == data {
            return current
        }
        if let current {
            context.delete(current)
        }
        guard let data else { return nil }
        let photo = Photo(data: data)
        context.insert(photo)
        return photo
    }
}
