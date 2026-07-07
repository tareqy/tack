import Foundation
import SwiftData

@Model
final class Card {
    @Attribute(.unique) var id: UUID
    var title: String
    var details: String?       // NOT "description" — collides with NSObject
    var position: Int
    var dueDate: Date?          // ALWAYS stored as startOfDay when includesTime == false
    var includesTime: Bool
    var createdAt: Date
    var updatedAt: Date
    var list: BoardList?

    // Many-to-many with CardLabel; inverse declared here only (CardLabel.cards is a plain array).
    @Relationship(inverse: \CardLabel.cards)
    var labels: [CardLabel]

    init(
        id: UUID = UUID(),
        title: String,
        details: String? = nil,
        position: Int,
        dueDate: Date? = nil,
        includesTime: Bool = false,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        list: BoardList? = nil,
        labels: [CardLabel] = []
    ) {
        self.id = id
        self.title = title
        self.details = details
        self.position = position
        self.dueDate = dueDate
        self.includesTime = includesTime
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.list = list
        self.labels = labels
    }
}
