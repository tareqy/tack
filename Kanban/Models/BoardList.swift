import Foundation
import SwiftData

// Named BoardList (not "List") to avoid colliding with SwiftUI.List.
@Model
final class BoardList {
    @Attribute(.unique) var id: UUID
    var name: String
    var position: Int
    var isCollapsed: Bool      // Phase B (M9) uses this; field ships in V1 to avoid a migration.
    var createdAt: Date
    var board: Board?

    @Relationship(deleteRule: .cascade, inverse: \Card.list)
    var cards: [Card]

    init(
        id: UUID = UUID(),
        name: String,
        position: Int,
        isCollapsed: Bool = false,
        createdAt: Date = .now,
        board: Board? = nil,
        cards: [Card] = []
    ) {
        self.id = id
        self.name = name
        self.position = position
        self.isCollapsed = isCollapsed
        self.createdAt = createdAt
        self.board = board
        self.cards = cards
    }

    var sortedCards: [Card] { cards.sorted { $0.position < $1.position } }
}
