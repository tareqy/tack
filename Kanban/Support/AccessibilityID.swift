enum AccessibilityID {
    static let rootView = "root-view"

    /// E-01 export e2e marker (test-only, present only under `--export-to`). Detached
    /// `.accessibilityRepresentation` `Text` (the `boardThemeValue` pattern) exposing the app's
    /// own write→read→decode self-check of the exported JSON: `"<board names>|<To Do card titles>"`
    /// (comma-joined). Sandbox blocks the UI-test runner from reading the app's container file
    /// directly, so the app decodes the file it wrote and publishes the result for the test to
    /// assert (see `RootView.runExportSelfCheckIfNeeded`).
    static let exportSelfCheck = "export-self-check"

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

    // MARK: - M5: cards UI

    /// The card's title `InlineEditableText` (display text AND, while renaming, its `TextField`).
    /// Deliberately NOT prefixed `card-`: the whole card row's `.contain` container carries
    /// `card(title)`, and `cardIdentifiersByPosition` (the canonical order assertion) matches
    /// `identifier BEGINSWITH "card-"` — a `card-`-prefixed title would double-count every row.
    static func cardTitle(_ title: String) -> String { "cardtitle-\(title)" }
    /// The single inline "+ Add card" TextField (only one is ever open at a time, like `newListField`).
    static let newCardField = "new-card-field"

    // MARK: - M6: card detail sheet

    /// The card face's label-dots container (`accessibilityValue` = comma-joined color names,
    /// ordered by `LabelColor.allCases`), distinct from `labelChip(_:)` which is the detail sheet's
    /// per-color toggle chip.
    static func cardLabels(_ title: String) -> String { "card-labels-\(title)" }
    static let cardDetailTitleField = "detail-title-field"
    static let cardDetailDescriptionField = "detail-description-field"
    static let dueQuickToday = "due-quick-today"
    static let dueQuickTomorrow = "due-quick-tomorrow"
    static let dueQuickNextWeek = "due-quick-nextweek"
    static let dueDatePickerField = "due-date-picker"
    static let dueClear = "due-clear"

    // MARK: - M8: board themes

    static let themeButton = "theme-button"
    static func themeSwatch(_ name: String) -> String { "theme-swatch-\(name)" }
    static let themeHexField = "theme-hex-field"
    /// Detached marker (the `rootView` / `cardLabels` pattern) exposing the board's RESOLVED theme
    /// as `accessibilityValue`: a preset's raw name (e.g. "ocean") or "custom:<HEX>" when a custom
    /// hex color is in effect. Kept separate from `boardDetail` itself — that element's combined
    /// value is the board's emoji+name text (see `BoardView.header`), so folding the theme into it
    /// would clobber the existing regression assertions that check for the board's name there.
    static let boardThemeValue = "board-theme-value"

    // MARK: - M9: list collapse/expand

    /// The collapse-toggle chevron: the (expanded) header's "collapse" button AND the (collapsed)
    /// pill's "expand" button share this ONE identifier — exactly one of the two exists at a time
    /// (mutually exclusive branches in `ListColumnView.body`), so there is no collision, and callers
    /// address "the chevron for this list" uniformly regardless of state.
    static func collapseListButton(_ name: String) -> String { "collapse-list-\(name)" }

    /// Detached marker (the `boardThemeValue` / `cardLabels` pattern) exposing a column's collapse
    /// state as `accessibilityValue`: "collapsed" or "expanded". Kept SEPARATE from the `list(_:)`
    /// container itself for the same reason M8 kept `boardThemeValue` separate from `boardDetail`:
    /// a plain `.accessibilityValue` on a SwiftUI `.contain` container is empty under XCUITest on
    /// macOS (verified again in M9's first UI run), whereas an `.accessibilityRepresentation` `Text`
    /// reliably surfaces its value. The `list(_:)` container keeps its own `.accessibilityValue` for
    /// real VoiceOver; tests read the machine-readable state off this marker.
    static func listCollapseState(_ name: String) -> String { "list-state-\(name)" }

    // MARK: - M11: label filter bar

    /// `LabelFilterBar`'s per-color toggle chip. Distinct from `labelChip(_:)` (the card-detail
    /// `LabelPicker`'s chip, "label-chip-") by prefix — the two views are never on screen together,
    /// but the different prefix keeps a global identifier search unambiguous regardless.
    static func filterChip(_ color: String) -> String { "filter-chip-\(color)" }
    /// The filter bar's "Clear" button — present only while a filter is active (`LabelFilterBar`).
    static let filterClear = "filter-clear"
}
