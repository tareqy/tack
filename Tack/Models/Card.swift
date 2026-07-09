import Foundation
import SwiftData

@Model
final class Card {
    @Attribute(.unique) var id: UUID
    var title: String
    var details: String?       // NOT "description" — collides with NSObject
    var position: Int
    var dueDate: Date?          // startOfDay when includesTime == false; the raw slot start (M-B) when true
    var includesTime: Bool
    /// M-B: length of the time slot in minutes (nil = a point-in-time due, no slot). Only
    /// meaningful when `includesTime == true`; the store/sanitizer normalize it to nil otherwise
    /// and never persist a non-positive value. Additive optional in TackSchemaV1 (the
    /// `isCollapsed`/`Board.about` precedent — no schema version bump, no migration stage).
    var durationMinutes: Int?
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
        durationMinutes: Int? = nil,
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
        self.durationMinutes = durationMinutes
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.list = list
        self.labels = labels
    }
}
