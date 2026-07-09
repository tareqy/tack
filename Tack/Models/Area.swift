import Foundation
import SwiftData

/// M-F: an opt-in sidebar group of boards ("Area"). Single level, no nesting, no completion
/// semantics (PRD B-07/D-03). `position` is the area's order among areas (creation order —
/// no reorder UI in v1); `isCollapsed` is model state exactly like `BoardList.isCollapsed`
/// (undoable via `BoardStore.setAreaCollapsed`, exported in formatVersion 5). The `boards`
/// relationship is the app's FIRST explicit `.nullify`: deleting an Area releases its boards
/// to ungrouped — it never deletes boards (see `BoardStore.deleteArea`). Additive entity in
/// TackSchemaV1 — a new table is a lightweight migration, the ChecklistItem posture; an M-F
/// store opened by an older build simply ignores the table.
@Model
final class Area {
    @Attribute(.unique) var id: UUID
    var name: String
    var position: Int
    var isCollapsed: Bool

    @Relationship(deleteRule: .nullify, inverse: \Board.area)
    var boards: [Board]

    init(
        id: UUID = UUID(),
        name: String,
        position: Int,
        isCollapsed: Bool = false,
        boards: [Board] = []
    ) {
        self.id = id
        self.name = name
        self.position = position
        self.isCollapsed = isCollapsed
        self.boards = boards
    }

    var sortedBoards: [Board] { boards.sorted { $0.position < $1.position } }
}
