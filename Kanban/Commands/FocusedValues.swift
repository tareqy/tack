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
    /// Opens the inline add-list editor (ghost column) on the active board.
    let newList: () -> Void
    /// Deletes the selected card with no dialog (undoable). No-op when nothing is selected.
    let deleteSelectedCard: () -> Void
    /// Moves the selected card within/across lists (⌘-arrows). No-op at clamped edges.
    let moveSelectedCard: (MoveDirection) -> Void
    /// Moves the SELECTION (bare arrows). No-op when nothing is selected.
    let moveSelection: (MoveDirection) -> Void
    /// Whether ⌘←/⌘→ can currently move the selected card (there is an adjacent list) — drives the
    /// Card ▸ Move Card Left/Right enablement.
    let canMoveSelectedCard: (MoveDirection) -> Bool
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
}

// MARK: - FocusedValueKeys

private struct FocusedBoardKey: FocusedValueKey { typealias Value = Board }
private struct FocusedListKey: FocusedValueKey { typealias Value = BoardList }
private struct SelectedCardKey: FocusedValueKey { typealias Value = Card }
private struct BoardActionsKey: FocusedValueKey { typealias Value = BoardActions }
private struct BoardSelectionActionsKey: FocusedValueKey { typealias Value = BoardSelectionActions }

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
}
