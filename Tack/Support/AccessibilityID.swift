enum AccessibilityID {
    static let rootView = "root-view"

    /// E-01 export e2e marker (test-only, present only under `--export-to`). Detached
    /// `.accessibilityRepresentation` `Text` (the `boardThemeValue` pattern) exposing the app's
    /// own write→read→decode self-check of the exported JSON: `"<board names>|<To Do card titles>"`
    /// (comma-joined). Sandbox blocks the UI-test runner from reading the app's container file
    /// directly, so the app decodes the file it wrote and publishes the result for the test to
    /// assert (see `RootView.runExportSelfCheckIfNeeded`).
    static let exportSelfCheck = "export-self-check"

    /// E-02 import e2e marker (test-only, present only under `--import-from`). Same detached
    /// `.accessibilityRepresentation` pattern as `exportSelfCheck`. Value grammar (STABLE tokens,
    /// never localized copy): "ok|<all post-import board names in position order>|<first board's
    /// first-list card titles>" — computed from LIVE post-import store state, the only oracle that
    /// distinguishes add from replace when names duplicate; "error|<ImportError.caseName>" on any
    /// failure; "cancelled" when the ask-mode dialog is dismissed.
    static let importSelfCheck = "import-self-check"

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
    static let emptyStateImportButton = "empty-import-boards"

    // MARK: - M3: sidebar + board CRUD

    static let boardDetail = "board-detail"
    static let newBoardButton = "new-board-button"
    static let boardNameField = "board-name-field"
    static let boardEmojiField = "board-emoji-field"
    static let createBoardConfirm = "create-board-confirm"
    static let editBoardNameField = "edit-board-name-field"
    static let editBoardEmojiField = "edit-board-emoji-field"
    static let editBoardAboutField = "edit-board-about-field"
    static let editBoardConfirm = "edit-board-confirm"
    static let boardAboutField = "board-about-field"
    static let boardAboutSubtitle = "board-about-subtitle"
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

    /// M-B time-slot controls. The toggle/time-field/duration-menu trio exists only while a due
    /// date is staged; the field and menu additionally require the toggle on.
    static let dueTimeToggle = "due-time-toggle"
    static let dueTimeField = "due-time-field"
    static let dueDurationField = "due-duration-field"

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
    static let themeColorWell = "theme-color-well"

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

    // MARK: - M-C: list view + view-mode seam

    /// The toolbar's segmented Board/List switcher. The identifier lives on the Picker control
    /// itself; its two segments carry accessibility LABELS only ("Board"/"List") — giving
    /// segments their own ids under an id'd ancestor is exactly the M2 ancestor-shadowing shape,
    /// so tests reach segments as labeled radio buttons INSIDE this element instead.
    static let viewModePicker = "view-mode-picker"
    /// Detached marker (the `boardThemeValue` pattern: sibling `Color.clear` +
    /// `.accessibilityRepresentation` Text, never an ancestor of queried children) exposing the
    /// SELECTED board's view mode as its value: "board" or "list" (`BoardViewMode` raw values —
    /// wire format). Absent when no board is selected.
    static let viewModeValue = "view-mode-value"

    /// A List View bucket-section header ("list-section-overdue" … "list-section-no-date"; slugs
    /// from `ListBucket.sectionSlug`). Lives on the header `HStack` — a SIBLING of the section's
    /// rows, never a container around them (ancestor ids shadow children). The "list-section-"
    /// prefix can only collide with `list(_:)`'s "list-" if a board list is literally named
    /// "section-…" — not in any fixture; accepted.
    static func listSection(_ slug: String) -> String { "list-section-\(slug)" }
    /// A List View card row (`.contain` container, like `card(_:)`). Prefixed "listrow-", NOT
    /// "card-": `cardIdentifiersByPosition` counts `BEGINSWITH "card-"` and must never see rows.
    static func listRow(_ title: String) -> String { "listrow-\(title)" }
    /// The row's label-dots representation Text (the `cardLabels` pattern, list-mode flavored —
    /// distinct prefix so a global identifier search stays unambiguous).
    static func listRowLabels(_ title: String) -> String { "listrow-labels-\(title)" }

    // MARK: - M-D: calendar view

    /// The month header ("July 2026" visible). Machine value is POSIX "yyyy-MM" via an
    /// `.accessibilityRepresentation` Text carrying this id (the `boardThemeValue`/`DueDateBadge`
    /// pattern) — tests assert the displayed month without locale-dependent month names.
    static let calendarMonthTitle = "calendar-month-title"
    static let calendarPrevButton = "calendar-prev"
    static let calendarTodayButton = "calendar-today"
    static let calendarNextButton = "calendar-next"
    /// A day cell OF THE DISPLAYED MONTH: "calendar-day-<yyyy-MM-dd>" (POSIX, LOCAL time zone —
    /// the DueDateBadge.isoDateFormatter rationale). An `.accessibilityElement(children:
    /// .contain)` container (the proven `card(_:)` shape), so chip ids inside stay queryable via
    /// `cell.descendants`. Dimmed adjacent-month cells get NO id: they are non-interactive, and a
    /// date-keyed id on them would let a boundary-week test grab the wrong month's cell.
    static func calendarDay(_ isoDay: String) -> String { "calendar-day-\(isoDay)" }
    /// A day cell's compact card chip. Prefixed "calchip-", never "card-"
    /// (`cardIdentifiersByPosition` counts `BEGINSWITH "card-"`). The id lives on the chip's
    /// representation Text, whose value is "<HH:mm>|<title>" for timed cards (POSIX HH:mm — the
    /// DueDateBadge wire-time grammar) and "<title>" otherwise.
    static func calendarChip(_ title: String) -> String { "calchip-\(title)" }
    /// The No-Date rail's header HStack — a SIBLING of the rail rows, never a container around
    /// them (the `listSection` discipline).
    static let calendarNoDateHeader = "calendar-nodate-header"
    /// A No-Date rail row (`.contain` container, the `listRow(_:)` shape): "calrow-<title>".
    static func calendarNoDateRow(_ title: String) -> String { "calrow-\(title)" }

    // MARK: - M-E: checklists (Action Items)

    /// Card-detail checklist row controls. INDEX-keyed — the app's only index-keyed ids — because
    /// staged rows are anonymous until saved (a nil-id draft has no UUID and text is user-mutable
    /// mid-test). Index = the row's position in the staged drafts array, stable within a sheet
    /// (v1 has no reorder UI).
    static func checkItemToggle(_ index: Int) -> String { "checkitem-toggle-\(index)" }
    static func checkItemText(_ index: Int) -> String { "checkitem-text-\(index)" }
    static func checkItemDelete(_ index: Int) -> String { "checkitem-delete-\(index)" }
    static let checkItemAdd = "checkitem-add"
    /// The card face's done/total fraction — a representation Text (the `cardLabels`/DueDateBadge
    /// pattern) whose value is "<done>/<total>". Prefixed "checklist-", never "card-"
    /// (`cardIdentifiersByPosition` counts `BEGINSWITH "card-"`). Present only when total > 0.
    static func cardChecklist(_ title: String) -> String { "checklist-\(title)" }

    // MARK: - M-F: areas (sidebar board groups)

    /// An area's section header (`.contain` container, the `card(_:)` shape — the chevron
    /// Button inside keeps its own queryable id; `.combine` would swallow it, the atomic-button
    /// pitfall). Prefixed "area-", colliding with no existing prefix; note `BEGINSWITH "area-"`
    /// would also match `area-toggle-…`/`area-name-field` — no order-scan helper counts this
    /// prefix (the SidebarReorderUITests posture), don't add one.
    static func area(_ name: String) -> String { "area-\(name)" }
    /// The header's collapse/expand chevron. One id for both states (exactly one chevron exists
    /// per header — the `collapseListButton` discipline).
    static func areaToggle(_ name: String) -> String { "area-toggle-\(name)" }
    static let areaNameField = "area-name-field"
    static let areaSheetConfirm = "area-sheet-confirm"
    static let deleteAreaConfirm = "delete-area-confirm"
}
