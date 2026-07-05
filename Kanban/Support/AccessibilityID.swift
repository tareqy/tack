enum AccessibilityID {
    static let rootView = "root-view"

    static func board(_ name: String) -> String { "board-\(name)" }
    static func list(_ name: String) -> String { "list-\(name)" }
    static func card(_ title: String) -> String { "card-\(title)" }
    static func addCardButton(list: String) -> String { "add-card-\(list)" }
    static let addListButton = "add-list"
    static let sidebarFilterField = "sidebar-filter"
    static let cardDetailSheet = "card-detail"
    static func dueDateBadge(card: String) -> String { "due-badge-\(card)" }
    static func labelChip(_ color: String) -> String { "label-chip-\(color)" }
    static let emptyStateCreateBoardButton = "empty-create-board"
}
