import Foundation
import SwiftData

/// M-E: one checklist row (user-facing name: "Action Item") of a card — the model graph's third
/// cascade level (Board → BoardList → Card → ChecklistItem). `position` is the row's order within
/// its card, contiguous 0..<n, maintained by `BoardStore.applyCardEdits`' checklist diff (v1 has
/// no reorder UI: insertion order IS the order). Additive entity in TackSchemaV1 — a new table is
/// a lightweight migration, the same no-version-bump posture as the additive optional fields
/// (`durationMinutes`/`about`); an M-E store opened by an older build simply ignores the table.
@Model
final class ChecklistItem {
    @Attribute(.unique) var id: UUID
    var text: String
    var isDone: Bool
    var position: Int
    var card: Card?

    init(
        id: UUID = UUID(),
        text: String,
        isDone: Bool = false,
        position: Int,
        card: Card? = nil
    ) {
        self.id = id
        self.text = text
        self.isDone = isDone
        self.position = position
        self.card = card
    }
}
