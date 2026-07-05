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

    // MARK: - M3: sidebar + board CRUD

    static let boardDetail = "board-detail"
    static let newBoardButton = "new-board-button"
    static let boardNameField = "board-name-field"
    static let boardEmojiField = "board-emoji-field"
    static let createBoardConfirm = "create-board-confirm"
    static let renameBoardField = "rename-board-field"
    static let renameBoardConfirm = "rename-board-confirm"
    static let deleteBoardConfirm = "delete-board-confirm"

    // MARK: - M4: lists UI

    /// The list header's `InlineEditableText` (display text AND, while renaming, its `TextField`
    /// — only one exists at a time, see that view's doc comment). Distinct from `list(_:)`, which
    /// is the whole column's `.contain` container, so the two never collide as sibling queries.
    static func listHeader(_ name: String) -> String { "list-header-\(name)" }
    static func listCardCount(_ name: String) -> String { "list-count-\(name)" }
    static let newListField = "new-list-field"
    static let deleteListConfirm = "delete-list-confirm"
}
