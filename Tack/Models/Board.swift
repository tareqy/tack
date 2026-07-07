import Foundation
import SwiftData

@Model
final class Board {
    @Attribute(.unique) var id: UUID
    var name: String
    var emoji: String?
    var position: Int          // sidebar order; user-reorderable via drag (B-06)
    var themeName: String      // "default" until Phase B
    var customThemeHex: String?
    var createdAt: Date

    @Relationship(deleteRule: .cascade, inverse: \BoardList.board)
    var lists: [BoardList]

    init(
        id: UUID = UUID(),
        name: String,
        emoji: String? = nil,
        position: Int,
        themeName: String = "default",
        customThemeHex: String? = nil,
        createdAt: Date = .now,
        lists: [BoardList] = []
    ) {
        self.id = id
        self.name = name
        self.emoji = emoji
        self.position = position
        self.themeName = themeName
        self.customThemeHex = customThemeHex
        self.createdAt = createdAt
        self.lists = lists
    }

    var sortedLists: [BoardList] { lists.sorted { $0.position < $1.position } }
}
