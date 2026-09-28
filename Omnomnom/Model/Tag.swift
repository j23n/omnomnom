import Foundation
import SwiftData

/// A label the user puts on recipes and foods: "breakfast", "meal prep", "Leo's".
///
/// Flat, not a hierarchy. A folder would force one home per item and then ask where
/// porridge lives when it is both breakfast and meal prep. The thing actually wanted —
/// type "breakfast", get everything for breakfast — a label gives without the filing,
/// and an item can carry as many as it deserves.
///
/// Schema rules as for `Food`: no unique attributes, every attribute defaulted or
/// optional, relationships optional with the inverses declared here. A name therefore
/// cannot be unique in the store, so `named(_:in:)` is the only way one is created.
@Model
final class Tag {
    var id: UUID = UUID()
    var name: String = ""
    var createdAt: Date = Date.now

    @Relationship(deleteRule: .nullify, inverse: \Recipe.tags)
    var recipes: [Recipe]?

    @Relationship(deleteRule: .nullify, inverse: \Food.tags)
    var foods: [Food]?

    init(name: String) {
        self.id = UUID()
        self.name = name
        self.createdAt = Date.now
    }

    /// How many things carry this tag, for the Library's filter row.
    var itemCount: Int {
        (recipes?.count ?? 0) + (foods?.count ?? 0)
    }

    /// Whether nothing carries it any more, in which case it is not worth keeping.
    var isOrphaned: Bool {
        itemCount == 0
    }

    /// Every tag, by name.
    static func all(in context: ModelContext) throws -> [Tag] {
        try context.fetch(FetchDescriptor<Tag>(sortBy: [SortDescriptor(\Tag.name)]))
    }

    /// The tag with this name, ignoring case and surrounding space, creating and
    /// inserting one when there is none. `nil` when the name is blank.
    ///
    /// The comparison is done here rather than in a predicate because the store cannot
    /// hold a unique index and there are never enough tags for it to matter.
    static func named(_ name: String, in context: ModelContext) throws -> Tag? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let existing = try all(in: context).first(where: { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            return existing
        }
        let tag = Tag(name: trimmed)
        context.insert(tag)
        return tag
    }

    /// Tags whose name contains `text`, so searching "breakfast" finds what is filed
    /// under it as well as what is called it.
    static func matching(_ text: String, in context: ModelContext) throws -> [Tag] {
        try context.fetch(FetchDescriptor<Tag>(
            predicate: #Predicate<Tag> { $0.name.localizedStandardContains(text) },
            sortBy: [SortDescriptor(\Tag.name)]
        ))
    }

    /// Deletes tags nothing carries any more. Called after an editor saves, so removing
    /// the last use of a tag removes the tag, and the filter row never offers an empty one.
    static func removeOrphans(in context: ModelContext) throws {
        for tag in try all(in: context) where tag.isOrphaned {
            context.delete(tag)
        }
    }
}
