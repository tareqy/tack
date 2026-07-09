import Foundation
import SwiftData

@Model
final class Board {
    @Attribute(.unique) var id: UUID
    var name: String
    var emoji: String?
    /// Optional free-text purpose note ("what this board is for"). Named `about`,
    /// NOT `description` — that collides with NSObject on @Model classes (Card.details precedent).
    var about: String?
    var position: Int          // sidebar order; user-reorderable via drag (B-06)
    var themeName: String      // "default" until Phase B
    var customThemeHex: String?
    var createdAt: Date

    @Relationship(deleteRule: .cascade, inverse: \BoardList.board)
    var lists: [BoardList]

    /// M-F: the containing Area, nil = ungrouped (the default — grouping is opt-in). The plain
    /// optional side of Area's `.nullify` relationship (the Card.list shape). NOTE this is the
    /// first to-one added on the parent side of the graph (the FK column lands on Board's own
    /// table) — still additive-optional in shape, but Task 4's human checklist includes opening
    /// a pre-M-F store to smoke the migration. `position` stays GLOBAL across all boards
    /// regardless of area (PRD §6.2, M-F): the sidebar groups at render time.
    var area: Area?

    init(
        id: UUID = UUID(),
        name: String,
        emoji: String? = nil,
        about: String? = nil,
        position: Int,
        themeName: String = "default",
        customThemeHex: String? = nil,
        createdAt: Date = .now,
        lists: [BoardList] = [],
        area: Area? = nil
    ) {
        self.id = id
        self.name = name
        self.emoji = emoji
        self.about = about
        self.position = position
        self.themeName = themeName
        self.customThemeHex = customThemeHex
        self.createdAt = createdAt
        self.lists = lists
        self.area = area
    }

    var sortedLists: [BoardList] { lists.sorted { $0.position < $1.position } }
}
