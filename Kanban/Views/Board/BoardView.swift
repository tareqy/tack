import SwiftUI

/// The real board surface: a header showing the selected board's emoji + name, followed by a
/// horizontal scroll of `ListColumnView`s and a trailing `AddListButton`. Cards are fully
/// interactive (M5): create/rename/delete/select plus production drag-and-drop.
///
/// M7 makes this the publisher of the card-level command surface: it exports the selection and a
/// `BoardActions` bundle to the menu bar via `focusedSceneValue`, and it owns two trigger tokens
/// (`addCardListID`, `addListToken`) that let ⌘N / ⌥⌘N open the EXISTING inline editors
/// (`ListColumnView.startAddingCard`, `AddListButton`) rather than creating anything silently.
struct BoardView: View {
    let board: Board
    let store: BoardStore

    /// Fixed so DropMath (and the visual layout) have a deterministic column width to reason
    /// about the midline against — same rationale as the M2 spike's fixed `rowHeight`.
    static let columnWidth: CGFloat = 280

    @State private var targetedListID: UUID?
    /// Board-local single-card selection. Exported to the menu via `focusedSceneValue` (M7) for the
    /// ⌘⌫/⌘-arrow/arrow commands, but still owned here as simple @State.
    @State private var selectedCardID: UUID?
    /// The card currently showing its M6 detail sheet, if any — bound into every `CardView` so
    /// double-click-body / context-menu "Open Card" can set it from anywhere on the board.
    @State private var selectedDetailCard: Card?

    /// Command trigger: set to a list's id to make THAT column open its inline add-card editor
    /// (⌘N). The handling column resets it to nil so the same list can be retriggered.
    @State private var addCardListID: UUID?
    /// Command trigger: bumped to make `AddListButton` open its inline editor (⌥⌘N).
    @State private var addListToken = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            columnsScrollView
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding()
        .sheet(item: $selectedDetailCard) { card in
            CardDetailView(card: card, store: store, onDelete: {
                // Order matters — see CardDetailView.onDelete: close the sheet (nil the item)
                // BEFORE deleting, so no re-render evaluates the sheet against a deleted card.
                selectedDetailCard = nil
                store.deleteCard(card)
            })
        }
        // Exported focus state (M7). `focusedBoard`/`selectedCard`/`focusedList` are the documented
        // focus values; `boardActions` is what `AppCommands` actually reads (its presence == a board
        // is shown, driving New Card/New List enablement). "Focused list" = the selected card's list.
        //
        // The `boardActions` export goes NIL while the card-detail sheet is up: macOS matches menu
        // key equivalents BEFORE the key window's responder chain, so with the sheet open an
        // enabled ⌘⌫ would delete the very card the sheet is editing behind its back, and enabled
        // bare-arrow items would swallow ↑/↓ from the sheet's multi-line description editor and
        // silently move the board selection instead. Nil-ing the whole bundle disables every card
        // command (and ⌘N/⌥⌘N) for the sheet's lifetime.
        .focusedSceneValue(\.focusedBoard, board)
        .focusedSceneValue(\.selectedCard, selectedCard)
        .focusedSceneValue(\.focusedList, selectedCard?.list)
        .focusedSceneValue(\.boardActions, selectedDetailCard == nil ? boardActions : nil)
    }

    private var header: some View {
        Text("\(board.emoji ?? "🗂️") \(board.name)")
            .font(.largeTitle)
            // `.combine` (not `.contain`): same trap as the placeholder this view replaces — see
            // `RootView` for the full write-up of why `board-detail` must stay a `.combine` leaf,
            // not a `.contain` ancestor of the columns below it.
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier(AccessibilityID.boardDetail)
    }

    private var columnsScrollView: some View {
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: 12) {
                ForEach(board.sortedLists) { list in
                    ListColumnView(
                        board: board,
                        list: list,
                        store: store,
                        columnWidth: Self.columnWidth,
                        targetedListID: $targetedListID,
                        selectedCardID: $selectedCardID,
                        selectedDetailCard: $selectedDetailCard,
                        addCardListID: $addCardListID
                    )
                }
                AddListButton(board: board, store: store, columnWidth: Self.columnWidth, openEditorToken: addListToken)
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - Exported command surface

    private var snapshot: BoardSnapshot { BoardSnapshot(board: board) }

    /// The live `Card` for the current selection (nil when none / stale).
    private var selectedCard: Card? {
        guard let selectedCardID else { return nil }
        return board.sortedLists.flatMap { $0.sortedCards }.first { $0.id == selectedCardID }
    }

    private var boardActions: BoardActions {
        BoardActions(
            selectedCard: selectedCard,
            newCard: openNewCardEditor,
            newList: openNewListEditor,
            deleteSelectedCard: deleteSelectedCard,
            moveSelectedCard: moveSelectedCard,
            moveSelection: moveSelection,
            canMoveSelectedCard: canMoveSelectedCard
        )
    }

    /// ⌘N: opens the add-card editor on the focused list (list of the selected card) else the first
    /// list. Drives the existing `ListColumnView` inline editor via the `addCardListID` token.
    private func openNewCardEditor() {
        guard let targetID = NewCardTarget.resolve(selectedCardID: selectedCardID, board: snapshot) else { return }
        addCardListID = targetID
    }

    /// ⌥⌘N: opens the add-list ghost-column editor via `AddListButton`.
    private func openNewListEditor() {
        addListToken += 1
    }

    private func deleteSelectedCard() {
        guard let card = selectedCard else { return }
        selectedCardID = nil
        store.deleteCard(card)
    }

    private func moveSelectedCard(_ direction: MoveDirection) {
        guard let card = selectedCard,
              let target = SelectionNavigation.moveTarget(selectedCardID: card.id, direction: direction, board: snapshot),
              board.sortedLists.indices.contains(target.listIndex) else { return }
        store.moveCard(card, to: board.sortedLists[target.listIndex], at: target.insertIndex)
    }

    private func moveSelection(_ direction: MoveDirection) {
        if let newID = SelectionNavigation.next(selectedCardID: selectedCardID, direction: direction, board: snapshot) {
            selectedCardID = newID
        }
    }

    private func canMoveSelectedCard(_ direction: MoveDirection) -> Bool {
        guard let selectedCardID else { return false }
        return SelectionNavigation.moveTarget(selectedCardID: selectedCardID, direction: direction, board: snapshot) != nil
    }
}
