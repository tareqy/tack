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

    /// M11 (LB-03): the label filter bar's visibility + active color set. PURE VIEW STATE — never
    /// persisted, never touches `BoardStore` — reset whenever the displayed board changes (see the
    /// `.onChange(of: board.id)` below), since `BoardView` is NOT recreated across a board switch
    /// (`RootView.detailContent` swaps only the `board:` argument, so `@State` would otherwise leak
    /// a Groceries-board filter onto the Work board).
    @State private var isFilterBarVisible = false
    @State private var activeLabelFilter: Set<LabelColor> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            if isFilterBarVisible {
                LabelFilterBar(active: $activeLabelFilter)
            }
            columnsScrollView
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding()
        // M8: the resolved board theme washes the whole surface; `.padding()` above reports the
        // full offered size back up (it just insets its child), so attaching `.background` here —
        // AFTER frame+padding — covers the entire board area edge-to-edge rather than only the
        // inset content region. Columns keep their own `Color.secondary.opacity` backing
        // (ListColumnView) on top, so content legibility is unaffected by the wash underneath.
        .background(themeBackground)
        .overlay(alignment: .topLeading) { themeValueMarker }
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
        // M11: the filter is per-board view state (see the property's doc comment) — clear it
        // whenever the board identity changes so switching boards never carries a stale filter
        // over (`testFilterResetsOnBoardSwitch`). The bar's OWN visibility is left as the user set
        // it — only the active color set is board-scoped.
        .onChange(of: board.id) { _, _ in activeLabelFilter = [] }
        // M11: Esc hides + clears the filter bar — via `.onExitCommand`, the SAME mechanism every
        // other Esc-cancel in this app uses (inline rename/add-card/add-list fields, the
        // card-detail sheet's own `.onExitCommand { dismiss() }`), NOT a `Commands` keyboard
        // shortcut (a bare, no-modifier `.keyboardShortcut(.escape, modifiers: [])` empirically
        // never fires — see `AppCommands`'s "Filter by Label" doc comment). Being responder-chain
        // based is exactly what makes this respect the brief's guard for free: a focused editor's
        // OWN closer `.onExitCommand` wins before this one ever sees the key, and the card-detail
        // sheet is a separate key window entirely, so this handler is simply unreachable while
        // either is active — no explicit `textInputFocused`/`isSheet` check needed. The
        // `isFilterBarVisible` guard is still explicit: with the bar already hidden there is
        // nothing to do, and this must not swallow an Esc meant for anything else.
        .onExitCommand {
            guard isFilterBarVisible else { return }
            isFilterBarVisible = false
            activeLabelFilter = []
        }
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
                        addCardListID: $addCardListID,
                        activeLabelFilter: activeLabelFilter
                    )
                }
                AddListButton(board: board, store: store, columnWidth: Self.columnWidth, openEditorToken: addListToken)
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: - M8: theme

    private var themeBackground: Color {
        switch ThemeResolution.resolve(themeName: board.themeName, customHex: board.customThemeHex) {
        case .preset(let theme): theme.backgroundColor
        case .custom(let color): color
        }
    }

    /// The value XCUITest reads off `AccessibilityID.boardThemeValue`: a preset's raw name (e.g.
    /// "ocean") or "custom:<HEX>" — see that identifier's doc comment for why this is a dedicated
    /// marker rather than folded into `board-detail`.
    private var themeExposedValue: String {
        switch ThemeResolution.resolve(themeName: board.themeName, customHex: board.customThemeHex) {
        case .preset(let theme): theme.rawValue
        case .custom: "custom:\(board.customThemeHex ?? "")"
        }
    }

    /// Zero-sized and non-hit-testing so it never affects layout or intercepts clicks — the same
    /// "detached marker" shape as `RootView.rootView` and the M6 `.accessibilityRepresentation`
    /// pattern (`CardView.labelDots`/`DueDateBadge`) combined: a representation `Text` is what
    /// XCUITest reliably surfaces a `.value` from; a plain view's `.accessibilityValue` was
    /// verified empty in M6.
    private var themeValueMarker: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .allowsHitTesting(false)
            .accessibilityRepresentation {
                Text(themeExposedValue)
                    .accessibilityIdentifier(AccessibilityID.boardThemeValue)
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
            canMoveSelectedCard: canMoveSelectedCard,
            toggleLabelFilterBar: toggleLabelFilterBar
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

    /// ⌘F / View ▸ "Filter by Label": flips bar visibility. Hiding ALWAYS clears the active filter
    /// — showing never needs to (it can only ever be non-empty while the bar is already visible) —
    /// so re-showing the bar always starts from "no filter". Esc (see the `.onExitCommand` above)
    /// performs the exact same hide-and-clear, just via a different trigger.
    private func toggleLabelFilterBar() {
        isFilterBarVisible.toggle()
        if !isFilterBarVisible {
            activeLabelFilter = []
        }
    }
}
