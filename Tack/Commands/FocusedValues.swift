import SwiftUI

/// Card-level command surface published to the menu bar by `BoardView` via `focusedSceneValue`.
/// Its mere PRESENCE means a board is on screen (BoardView is only in the tree when a board is
/// selected), so the menu keys "New Card"/"New List" enablement off `boardActions != nil`.
///
/// Selection is carried here (`selectedCard`) rather than relying on NSResponder focus: commands
/// act on the exported selection, per the M7 brief ("do NOT fight SwiftUI focus"). "Focused list"
/// is the list of the selected card (see `focusedList`), which is why ⌘N targets it.
struct BoardActions {
    /// The board-local single-card selection, resolved to the live `Card` (nil when none).
    let selectedCard: Card?
    /// Opens the inline add-card editor on the focused list (list of the selected card), else the
    /// first list of the active board.
    let newCard: () -> Void
    /// Whether ⌘N / File ▸ "New Card" currently has anywhere to open its inline editor — false
    /// when every list on the active board is collapsed (`NewCardTarget.resolve(...) == nil`, see
    /// that type's doc comment). Drives the New Card menu item's `.disabled(...)` alongside the
    /// existing `boardActions == nil` gate.
    let canCreateCard: Bool
    /// Opens the inline add-list editor (ghost column) on the active board.
    let newList: () -> Void
    /// Deletes the selected card with no dialog (NOT undoable since M-E — see
    /// `BoardStore.deleteCard`). No-op when nothing is selected.
    let deleteSelectedCard: () -> Void
    /// Opens the configured card-detail presentation for the selected card (Card ▸ "Open Card"
    /// / ⌘O). No-op when nothing is selected.
    let openSelectedCard: () -> Void
    /// Moves the selected card within/across lists (⌘-arrows). No-op at clamped edges.
    let moveSelectedCard: (MoveDirection) -> Void
    /// Moves the SELECTION (bare arrows). No-op when nothing is selected.
    let moveSelection: (MoveDirection) -> Void
    /// Whether ⌘←/⌘→ can currently move the selected card (there is an adjacent list) — drives the
    /// Card ▸ Move Card Left/Right enablement.
    let canMoveSelectedCard: (MoveDirection) -> Bool
    /// ⌘F / View ▸ "Filter by Label": shows/hides the label filter bar (LB-03). PURE VIEW STATE on
    /// `BoardView` — never a `BoardStore` mutation. Hiding ALWAYS clears the active filter (see
    /// `BoardView.toggleLabelFilterBar`). Esc-to-hide is handled separately, directly on
    /// `BoardView` via `.onExitCommand` (a bare-Escape `Commands` shortcut does not fire — see that
    /// call site's doc comment), so it is NOT exposed here.
    let toggleLabelFilterBar: () -> Void
    /// M-C: whether View ▸ "Filter by Label" (⌘F) applies to the current board surface. The
    /// label filter bar is board-canvas-only in v1 — `ListBoardView` publishes real boardActions
    /// but passes `false` here so the menu item disables HONESTLY instead of staying enabled and
    /// firing a silent no-op (the same enabled-but-inert trap E-02's manual gate flagged for
    /// Export). Defaulted `true` so `BoardView`'s construction is untouched — a defaulted `var` is
    /// required here, not a `let`: a defaulted `let` is excluded from the memberwise init, so
    /// every existing call site (including `BoardView`'s) would fail to compile without it.
    var canFilter: Bool = true
    /// M-C fix: whether Card ▸ "Move Card Up"/"Move Card Down" (⌘-arrow) apply to the current
    /// board surface. List mode has no positional insert semantics — a computed due-date bucket
    /// has no "up"/"down" to move a card into — so `ListBoardView` passes `false` here to disable
    /// the items HONESTLY instead of leaving them enabled-but-inert (found in the M-C whole-branch
    /// review: selecting a card in list mode left Move Up/Down enabled and silently did nothing).
    /// Defaulted `true` so `BoardView`'s construction is untouched — same defaulted-`var`-not-`let`
    /// reasoning as `canFilter` above (a defaulted `let` drops out of the memberwise init).
    var canMoveCards: Bool = true
    /// M-C fix: whether File ▸ "New List" (⌥⌘N) applies to the current board surface. Same trap
    /// shape as `canMoveCards` — list mode has nowhere on the canvas to open the inline add-list
    /// editor — so `ListBoardView` passes `false` here. Defaulted `true` so `BoardView`'s
    /// construction is untouched — same defaulted-`var`-not-`let` reasoning as `canFilter`.
    var canCreateList: Bool = true
    /// M-D: whether View ▸ Select Next/Previous/Left/Right (bare arrows) apply to the current
    /// board surface. Calendar mode has no arrow-key selection model in v1 — a month grid wants
    /// 2D day-cell navigation, not the card-list walk `SelectionNavigation` implements, and
    /// faking one would be worse than none — so `CalendarBoardView` passes `false` to disable
    /// the four items HONESTLY instead of leaving them enabled-but-inert (the
    /// canFilter/canMoveCards/canCreateList precedent, one more time). Defaulted `true` so
    /// `BoardView`'s and `ListBoardView`'s constructions are untouched — same
    /// defaulted-`var`-not-`let` reasoning as `canFilter` (a defaulted `let` drops out of the
    /// memberwise init).
    var canNavigateSelection: Bool = true
}

/// Board-navigation command surface published by `RootView`: always present (RootView is always in
/// the tree), so "New Board" is always enabled and ⌘1–⌘9 enablement keys off `boardNames.count`.
struct BoardSelectionActions {
    /// Opens the new-board sheet.
    let newBoard: () -> Void
    /// Selects the nth board by position (1-based, matching ⌘1…⌘9). Out-of-range is a no-op.
    let selectBoard: (Int) -> Void
    /// Board names in position order — for the ⌘1–⌘9 menu titles and their enablement.
    let boardNames: [String]
    /// E-01 / ⇧⌘E — File ▸ "Export All Boards…": builds the export document from every board and
    /// presents the save panel (RootView owns the `.fileExporter`). Enablement keys off
    /// `boardNames` being non-empty (nothing to export with no boards).
    let exportAllBoards: () -> Void
    /// E-02 / ⇧⌘I — File ▸ "Import Boards…": presents the JSON open panel (RootView hosts the
    /// `.fileImporter` — a `Commands` value can't present one, same constraint as the exporter).
    /// Always enabled, including at zero boards: restore-into-an-empty-app is the headline case.
    let importBoards: () -> Void
    /// M-C: sets the selected board's view mode (View ▸ as Board ⌥⌘B / as List ⌥⌘L; the toolbar
    /// switcher writes through `RootView`'s binding to the same map). No-op when no board is
    /// selected — the backstop behind the menu items' `.disabled` gate.
    let setViewMode: (BoardViewMode) -> Void
}

// MARK: - FocusedValueKeys

private struct FocusedBoardKey: FocusedValueKey { typealias Value = Board }
private struct FocusedListKey: FocusedValueKey { typealias Value = BoardList }
private struct SelectedCardKey: FocusedValueKey { typealias Value = Card }
private struct BoardActionsKey: FocusedValueKey { typealias Value = BoardActions }
private struct BoardSelectionActionsKey: FocusedValueKey { typealias Value = BoardSelectionActions }
private struct TextInputFocusedKey: FocusedValueKey { typealias Value = Bool }

extension FocusedValues {
    /// The board currently shown in the detail pane.
    var focusedBoard: Board? {
        get { self[FocusedBoardKey.self] }
        set { self[FocusedBoardKey.self] = newValue }
    }
    /// The list containing the selected card (the "focused list" that ⌘N and Return target), or nil.
    var focusedList: BoardList? {
        get { self[FocusedListKey.self] }
        set { self[FocusedListKey.self] = newValue }
    }
    /// The selected card, or nil.
    var selectedCard: Card? {
        get { self[SelectedCardKey.self] }
        set { self[SelectedCardKey.self] = newValue }
    }
    /// Card-level command closures + selection, published by BoardView.
    var boardActions: BoardActions? {
        get { self[BoardActionsKey.self] }
        set { self[BoardActionsKey.self] = newValue }
    }
    /// Board-navigation command closures, published by RootView.
    var boardSelectionActions: BoardSelectionActions? {
        get { self[BoardSelectionActionsKey.self] }
        set { self[BoardSelectionActionsKey.self] = newValue }
    }
    /// `true` while a text-input view (any TextField/TextEditor tagged with
    /// `reportsTextInputFocus()`) holds keyboard focus; nil otherwise. AppCommands gates the
    /// mutating card commands (⌘⌫, ⌘-arrows) and the bare-arrow selection commands on this, so a
    /// menu key-equivalent can never mutate/steer the board behind an open editor.
    ///
    /// This is a focus-system signal by DESIGN, not a responder-chain sniff: on this macOS/SwiftUI
    /// version the AppKit first responder while editing any SwiftUI text field is a private
    /// `SwiftUI.KeyViewProxy` that is neither an `NSTextView` nor an `NSTextInputClient`, and it is
    /// the first responder even when NO editor is open — so `firstResponder is NSTextView` (the
    /// classic field-editor check) can never discriminate (verified empirically via a
    /// responder-chain dump from inside the running app). `@FocusedValue` is also exactly the
    /// change signal SwiftUI Commands re-evaluate enablement on, which responder changes are not.
    var textInputFocused: Bool? {
        get { self[TextInputFocusedKey.self] }
        set { self[TextInputFocusedKey.self] = newValue }
    }
}

extension View {
    /// Marks a text-input view so that, while it holds keyboard focus, the command layer sees
    /// `textInputFocused == true` and disables/no-ops the mutating card commands (see
    /// `FocusedValues.textInputFocused`). Apply to EVERY TextField/TextEditor reachable while a
    /// board can be on screen: the inline add-card/add-list/rename editors, the board sheets'
    /// fields, and the sidebar filter.
    func reportsTextInputFocus() -> some View {
        focusedValue(\.textInputFocused, true)
    }
}
