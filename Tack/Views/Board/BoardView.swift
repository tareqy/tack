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
    let isCardDetailSheetPresented: Bool
    let onOpenCard: (Card) -> Void
    let onDeleteCard: (Card) -> Void
    let onDeleteList: (BoardList) -> Void
    /// BoardView owns a label-filter Esc handler. When the filter is already hidden, forward Esc
    /// so RootView can preserve the inspector's presentation-level Cancel behavior.
    let onExitCardDetail: () -> Void

    /// Fixed so DropMath (and the visual layout) have a deterministic column width to reason
    /// about the midline against — same rationale as the M2 spike's fixed `rowHeight`.
    static let columnWidth: CGFloat = 280

    @State private var targetedListID: UUID?
    /// Board-local single-card selection. Exported to the menu via `focusedSceneValue` (M7) for the
    /// ⌘⌫/⌘-arrow/arrow commands, but still owned here as simple @State.
    @State private var selectedCardID: UUID?

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
                .padding(.horizontal, 16)
            if isFilterBarVisible {
                LabelFilterBar(active: $activeLabelFilter)
                    .padding(.horizontal, 16)
            }
            columnsScrollView
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // Vertical inset only: the horizontal inset moved into the scroll view's content margins
        // so columns scroll edge-to-edge under it instead of clipping at an invisible boundary.
        .padding(.vertical, 16)
        // HIG: the window title reflects the shown content (feeds the Window menu, Mission
        // Control, and window cycling); RootView resets it to "Tack" on the no-board branches.
        .navigationTitle(board.name)
        // M8: the resolved board theme washes the whole surface; `.padding()` above reports the
        // full offered size back up (it just insets its child), so attaching `.background` here —
        // AFTER frame+padding — covers the entire board area edge-to-edge rather than only the
        // inset content region. Columns keep their own `Color.secondary.opacity` backing
        // (ListColumnView) on top, so content legibility is unaffected by the wash underneath.
        .background(themeBackground)
        .overlay(alignment: .topLeading) { themeValueMarker }
        // Exported focus state (M7). `focusedBoard`/`selectedCard`/`focusedList` are the documented
        // focus values; `boardActions` is what `AppCommands` actually reads (its presence == a board
        // is shown, driving New Card/New List enablement). "Focused list" = the selected card's list.
        //
        // `boardActions` goes NIL only for the modal sheet: macOS matches menu key equivalents
        // before that sheet's responder chain, so an enabled ⌘⌫ could mutate behind it. The
        // nonmodal inspector deliberately keeps the board surface usable; focused text inputs
        // still publish the shared command guard that blocks conflicting mutations while typing.
        .focusedSceneValue(\.focusedBoard, board)
        .focusedSceneValue(\.selectedCard, selectedCard)
        .focusedSceneValue(\.focusedList, selectedCard?.list)
        .focusedSceneValue(\.boardActions, isCardDetailSheetPresented ? nil : boardActions)
        // M11: the filter is per-board view state (see the property's doc comment) — clear it
        // whenever the board identity changes so switching boards never carries a stale filter
        // over (`testFilterResetsOnBoardSwitch`). The bar's OWN visibility is left as the user set
        // it — only the active color set is board-scoped.
        .onChange(of: board.id) { _, _ in activeLabelFilter = [] }
        // Final review (visibility seam): when the selected card stops being visible — its list is
        // collapsed, or a label filter now hides it — drop the selection, so keyboard nav/commands
        // never act on an off-screen card. Keyed to the deliberate visibility triggers ONLY (the
        // active filter set and the set of collapsed lists), NOT the derived card-id set: the
        // latter also churns on card add/remove and on transient SwiftData re-renders, which would
        // clear a still-valid selection mid keyboard-navigation.
        .onChange(of: activeLabelFilter) { _, _ in clearSelectionIfInvisible() }
        .onChange(of: collapsedListIDs) { _, _ in clearSelectionIfInvisible() }
        // M11: Esc hides + clears the filter bar — via `.onExitCommand`, the SAME mechanism every
        // other Esc-cancel in this app uses (inline rename/add-card/add-list fields, the
        // card-detail editor's own `.onExitCommand`), NOT a `Commands` keyboard
        // shortcut (a bare, no-modifier `.keyboardShortcut(.escape, modifiers: [])` empirically
        // never fires — see `AppCommands`'s "Filter by Label" doc comment). Being responder-chain
        // based is exactly what makes this respect the brief's guard for free: a focused editor's
        // OWN closer `.onExitCommand` wins before this one sees the key; a modal card-detail sheet
        // is a separate key window, and a focused inspector editor is the nearer responder. No
        // explicit `textInputFocused`/`isSheet` check is needed. The
        // `isFilterBarVisible` guard is still explicit: with the bar already hidden there is
        // nothing to do, and this must not swallow an Esc meant for anything else.
        .onExitCommand {
            if isFilterBarVisible {
                isFilterBarVisible = false
                activeLabelFilter = []
            } else {
                onExitCardDetail()
            }
        }
    }

    private var header: some View {
        // M-A: the about subtitle is a SIBLING of the combined emoji+name element below, not a
        // child inside it — `.combine` collapses its children into one atomic AX element, which
        // would swallow the subtitle's own identifier (see CLAUDE.md: ancestor ids shadow
        // children; combined elements are atomic under AX). Keeping it outside lets XCUITest
        // resolve `boardAboutSubtitle` independently while `boardDetail` stays untouched.
        VStack(alignment: .leading, spacing: 2) {
            // Emoji and name as separate runs: interpolated into one largeTitle string, the emoji
            // rendered at full 26pt and outweighed the board name; here the name carries the weight
            // and the emoji sits a step down, on the shared baseline.
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(board.emoji ?? "🗂️")
                    .font(.title2)
                Text(board.name)
                    .font(.largeTitle.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            // `.combine` (not `.contain`): same trap as the placeholder this view replaces — see
            // `RootView` for the full write-up of why `board-detail` must stay a `.combine` leaf,
            // not a `.contain` ancestor of the columns below it.
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier(AccessibilityID.boardDetail)

            if let about = board.about, !about.isEmpty {
                Text(about)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .accessibilityIdentifier(AccessibilityID.boardAboutSubtitle)
            }
        }
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
                        onOpenCard: onOpenCard,
                        onDeleteCard: onDeleteCard,
                        onDeleteList: onDeleteList,
                        addCardListID: $addCardListID,
                        activeLabelFilter: activeLabelFilter
                    )
                }
                if board.sortedLists.isEmpty {
                    Text("This board is empty — add a list to get started.")
                        .foregroundStyle(.secondary)
                        .padding(.top, 8)
                }
                AddListButton(board: board, store: store, columnWidth: Self.columnWidth, openEditorToken: addListToken)
            }
        }
        .contentMargins(.horizontal, 16, for: .scrollContent)
    }

    // MARK: - M8: theme

    private var themeBackground: Color {
        switch ThemeResolution.resolve(themeName: board.themeName, customHex: board.customThemeHex) {
        case .preset(let theme): theme.backgroundColor
        // Custom hex is a WASH like every preset, not an opaque appearance-fixed paint: a literal
        // pale hex in dark mode (or dark hex in light mode) was the app's one path to illegible
        // primary text. The stored hex and the `boardThemeValue` marker are untouched.
        case .custom(let color): color.opacity(0.15)
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

    /// The VISIBLE snapshot the keyboard commands reason about: collapsed lists contribute no
    /// cards and, when a filter is active, only matching cards appear — so arrow navigation and
    /// ⌘-arrow moves both track exactly what's on screen (see `BoardSnapshot(board:activeLabelFilter:)`).
    private var snapshot: BoardSnapshot { BoardSnapshot(board: board, activeLabelFilter: activeLabelFilter) }

    /// Every card id currently visible on the board (collapsed lists + filtered-out cards excluded).
    private var visibleCardIDs: Set<UUID> { Set(snapshot.lists.flatMap(\.cardIDs)) }

    /// The ids of the currently-collapsed lists — the deliberate collapse/expand trigger the
    /// selection-visibility onChange keys off (changes only when a list is collapsed or expanded).
    private var collapsedListIDs: Set<UUID> { Set(board.sortedLists.filter(\.isCollapsed).map(\.id)) }

    /// Drops `selectedCardID` if the selected card is no longer visible (its list collapsed, or a
    /// filter now hides it). Called only from the filter/collapse onChange handlers above.
    private func clearSelectionIfInvisible() {
        guard let id = selectedCardID, !visibleCardIDs.contains(id) else { return }
        selectedCardID = nil
    }

    /// The live `Card` for the current selection (nil when none / stale).
    private var selectedCard: Card? {
        guard let selectedCardID else { return nil }
        return board.sortedLists.flatMap { $0.sortedCards }.first { $0.id == selectedCardID }
    }

    private var boardActions: BoardActions {
        BoardActions(
            selectedCard: selectedCard,
            newCard: openNewCardEditor,
            canCreateCard: NewCardTarget.resolve(selectedCardID: selectedCardID, board: snapshot) != nil,
            newList: openNewListEditor,
            deleteSelectedCard: deleteSelectedCard,
            openSelectedCard: openSelectedCard,
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
        onDeleteCard(card)
    }

    /// ⌘O / Card ▸ "Open Card": routes the selected card through RootView's configured detail
    /// presenter (the same path a double-click on the card body uses).
    private func openSelectedCard() {
        guard let card = selectedCard else { return }
        onOpenCard(card)
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
