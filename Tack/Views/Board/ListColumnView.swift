import SwiftUI

/// One list column: header (name + card-count badge, draggable for board-level list reordering,
/// double-click-to-rename via `InlineEditableText`, context menu to delete) and an interactive
/// stack of its `CardView`s, an inline "+ Add card" row, and a footer drop/append zone.
///
/// Follows the exact container/row accessibility structure proven by the M2 spike
/// (`Views/Spike/SpikeBoardView.swift`): the column is one `.contain` container
/// (`AccessibilityID.list(name)`) and each card row keeps its own individually-queryable
/// identifier underneath it — nesting an ancestor `.contain` id does NOT swallow a descendant's
/// own `.accessibilityIdentifier`, as the spike's card rows already prove.
///
/// COEXISTENCE (M4 → M5, both rules established EMPIRICALLY against real XCUITest drags):
/// 1. A differently-typed CHILD drop destination shadows its ancestor's: it consumes drops of
///    every drag type that land on its region but only handles its own — an unconditional footer
///    CardTransfer target covering the column body swallowed the ListTransfer drops landing there
///    (regressed `testReorderLists` in the first M5 run).
/// 2. Two different-typed `.dropDestination`s stacked on ONE view do NOT dispatch by payload type
///    either — the first modifier shadows the second, so a container-level CardTransfer target
///    behind the ListTransfer one simply never fired (regressed every cross-list card drop in the
///    second run).
/// The working split: the column CONTAINER owns the list-reorder ListTransfer destination (drops
/// on header/edges); `CardView` rows own precise before/after CardTransfer destinations; and the
/// footer owns ONE dual-import `ColumnDropPayload` destination that appends cards AND forwards
/// body-landing list drops to the same reorder routing — so neither payload is ever swallowed.
/// `testListDragStillWorksWithCardDestinations` + the card drag suites are the regression gates.
struct ListColumnView: View {
    let board: Board
    let list: BoardList
    let store: BoardStore
    let columnWidth: CGFloat
    @Binding var targetedListID: UUID?
    @Binding var selectedCardID: UUID?
    let onOpenCard: (Card) -> Void
    let onDeleteCard: (Card) -> Void
    let onDeleteList: (BoardList) -> Void
    /// Command trigger from BoardView (⌘N): when it equals this list's id, open the inline
    /// add-card editor. This column resets it to nil after handling so the same list can retrigger.
    @Binding var addCardListID: UUID?
    /// M11 (LB-03): the label filter bar's active color set, threaded down from `BoardView` as a
    /// plain value (not a `Binding` — this view only ever READS it for rendering, never mutates
    /// it). Drives `visibleCards` below. Empty means "no filter" (every card renders).
    let activeLabelFilter: Set<LabelColor>

    /// Same fixed row height as the M2 spike, so its DropMath reasoning carries over unchanged.
    private let rowHeight: CGFloat = 44

    /// Width of the collapsed pill (M9). Narrow enough that `testCollapseExpandRoundTrip`'s
    /// `frame.width < 100` assertion holds with margin, yet wide enough for the chevron + count
    /// badge + rotated name. The pill's list-reorder routing uses THIS width for its DropMath
    /// midline (not `columnWidth`) so a drop on its left/right half still resolves before/after
    /// correctly at pill scale.
    private let collapsedWidth: CGFloat = 44

    @State private var isPresentingDeleteConfirm = false
    @State private var isAddingCard = false
    @State private var newCardDraft = ""
    @FocusState private var isAddCardFocused: Bool
    @State private var isFooterTargeted = false
    @State private var isPillTargeted = false
    @State private var isPillHovering = false
    /// Context-menu "Rename List" trigger, forwarded into the header's `InlineEditableText` —
    /// the exact `beginEditSignal` pattern `CardView`'s "Rename Card" already uses.
    @State private var beginRenameList = false

    // MARK: - M11: label filter (rendering only — see the type doc's DROP MATH note below)

    /// This list's cards after the active filter (`LabelFilter`, OR semantics) — what `cardList`
    /// actually renders. Empty `activeLabelFilter` ⇒ identical to `list.sortedCards`.
    private var visibleCards: [Card] { LabelFilter.visibleCards(list.sortedCards, active: activeLabelFilter) }

    /// The header/pill count badge text: plain total ("3") with no active filter, "visible/total"
    /// ("1/3") once a filter hides at least one card in this list. Same `AccessibilityID
    /// .listCardCount` identifier either way — only the exposed VALUE format changes.
    private var countLabel: String {
        let total = list.cards.count
        guard !activeLabelFilter.isEmpty else { return "\(total)" }
        return "\(visibleCards.count)/\(total)"
    }

    // M9: a column renders as either the full expanded column or a narrow collapsed pill, per
    // `list.isCollapsed`. BOTH branches carry the SAME `.contain` container id
    // (`AccessibilityID.list(name)`) so tests address a column uniformly either way, and each also
    // sets its own `.accessibilityValue` for real VoiceOver. Because a `.contain` container's value
    // is empty under XCUITest, the machine-readable collapse state is ALSO published through a
    // detached `.accessibilityRepresentation` marker overlay (the proven `boardThemeValue`
    // pattern), which tests read. The expanded branch is the FROZEN M4→M5 drop architecture,
    // unchanged except for an additive header collapse chevron and the accessibilityValue.
    var body: some View {
        Group {
            if list.isCollapsed {
                collapsedPill
            } else {
                expandedColumn
            }
        }
        .overlay(alignment: .topLeading) { collapseStateMarker }
        // ⌘N routing: BoardView sets `addCardListID` to the target list; the matching column opens
        // its inline editor and clears the token (so re-triggering the same list fires again).
        // Handled HERE, on the always-present outer view, rather than inside `expandedColumn` —
        // otherwise a token targeting a collapsed column (whose expanded branch isn't in the tree)
        // would never be consumed and would WEDGE, blocking every later ⌘N to that same list.
        // `NewCardTarget.resolve` already steers ⌘N away from collapsed lists, but clearing the
        // token unconditionally on match makes a stale token impossible regardless.
        .onChange(of: addCardListID) { _, newValue in
            guard newValue == list.id else { return }
            addCardListID = nil
            if !list.isCollapsed { startAddingCard() }
        }
        // Attached to the always-present outer view (not `expandedColumn`) so BOTH branches can
        // present it — the collapsed pill's context menu offers Delete List too.
        .confirmationDialog(
            "Delete “\(list.name)”?",
            isPresented: $isPresentingDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                onDeleteList(list)
            }
            .accessibilityIdentifier(AccessibilityID.deleteListConfirm)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(deleteListMessage)
        }
    }

    /// HIG dialog anatomy: short question in the title, consequence in the message — with real
    /// pluralization instead of "Its 1 cards will be deleted."
    private var deleteListMessage: String {
        switch list.cards.count {
        case 0: "This list is empty. You can't undo this."
        case 1: "This also deletes its 1 card. You can't undo this."
        default: "This also deletes its \(list.cards.count) cards. You can't undo this."
        }
    }

    /// Zero-sized, non-hit-testing marker whose `.accessibilityRepresentation` `Text` reliably
    /// surfaces the collapse state as a value under XCUITest — the same shape as
    /// `BoardView.themeValueMarker`. Read via `AccessibilityID.listCollapseState(name)`.
    private var collapseStateMarker: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .allowsHitTesting(false)
            .accessibilityRepresentation {
                Text(list.isCollapsed ? "collapsed" : "expanded")
                    .accessibilityIdentifier(AccessibilityID.listCollapseState(list.name))
            }
    }

    // MARK: - Expanded column (frozen M4→M5 drop architecture)

    private var expandedColumn: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            Divider()
            cardList
        }
        .padding(8)
        .frame(width: columnWidth, alignment: .topLeading)
        .frame(maxHeight: .infinity)
        .background(Color.columnSurface, in: RoundedRectangle(cornerRadius: 10))
        // Whole-column targeted stroke (matching the collapsed pill's treatment) instead of the
        // old leading-edge bar: `isTargeted` can't know which side DropMath will resolve, so a
        // left-edge line previewed the WRONG side for right-half drops. "This column is the
        // reference" is the honest feedback, and expanded/collapsed become consistent.
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.accentColor, lineWidth: 2)
                .opacity(targetedListID == list.id ? 1 : 0)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AccessibilityID.list(list.name))
        .accessibilityValue("expanded")
        // COEXISTENCE (empirically established — see the type doc for the full story): the column
        // CONTAINER owns ONLY this list-reorder destination, catching list drops on the header and
        // column edges. Do NOT stack a CardTransfer destination here (the first-applied modifier
        // shadows the second; it never fires). Card drops are handled by `CardView` rows (precise
        // before/after) and the footer's dual-import `ColumnDropPayload` destination (append).
        .dropDestination(for: ListTransfer.self) { items, location in
            guard let transfer = items.first else { return false }
            return handleDrop(transfer: transfer, location: location)
        } isTargeted: { isTargeted in
            setTargeted(isTargeted)
        }
    }

    // MARK: - Collapsed pill (M9)

    /// The narrow, full-height stand-in for a collapsed column: a chevron to expand, the live card
    /// count, and the rotated list name. Clicking anywhere on the pill (or the chevron) expands it.
    /// It stays a valid drop target via ONE dual-import `ColumnDropPayload` destination — the SAME
    /// frozen pattern the expanded footer uses: card drops append to this list, list drops route
    /// through the shared reorder `handleDrop` (at pill width, so its before/after midline is
    /// correct). No typed stacked destinations — that shape was disproven in M5.
    private var collapsedPill: some View {
        VStack(spacing: 10) {
            Button(action: expand) {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .padding(.vertical, 4)
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
            }
            .buttonStyle(HoverHighlightButtonStyle())
            .help("Expand list")
            .accessibilityIdentifier(AccessibilityID.collapseListButton(list.name))
            .accessibilityLabel("Expand \(list.name)")

            // M11: collapsed pills show FILTERED counts too — same `countLabel` as the expanded
            // header below (and the same quiet no-capsule treatment).
            Text(countLabel)
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .accessibilityIdentifier(AccessibilityID.listCardCount(list.name))

            // Rotated name. `fixedSize` gives it its ideal (unwrapped) size in layout; the -90°
            // rotation is a render-only transform, so the name's horizontal layout claim overflows
            // the fixed 44pt pill width harmlessly and draws as vertical text. Marked AX-hidden —
            // the name is already carried by the container's identifier, and hiding it keeps the
            // overflowing layout box out of the container's AX frame so the pill measures at its
            // true ~44pt width.
            Text(list.name)
                .font(.headline)
                .lineLimit(1)
                .fixedSize()
                .rotationEffect(.degrees(-90))
                .frame(maxHeight: .infinity)
                .accessibilityHidden(true)
        }
        .padding(.vertical, 8)
        .frame(width: collapsedWidth, alignment: .top)
        .frame(maxHeight: .infinity)
        .background(Color.columnSurface, in: RoundedRectangle(cornerRadius: 10))
        // Hover wash: the whole pill is clickable (expand), so it should acknowledge the pointer
        // like a card does.
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.primary.opacity(isPillHovering ? 0.05 : 0))
                .allowsHitTesting(false)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.accentColor, lineWidth: 2)
                .opacity(isPillTargeted ? 1 : 0)
        }
        .clipped()
        .contentShape(Rectangle())
        .onHover { isPillHovering = $0 }
        .onTapGesture(perform: expand)
        // A collapsed list must stay fully operable by right-click; rename needs the expanded
        // header's inline editor, so it's expand-first here.
        .contextMenu {
            Button("Expand List", action: expand)
            Divider()
            Button("Delete List", role: .destructive) {
                isPresentingDeleteConfirm = true
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AccessibilityID.list(list.name))
        .accessibilityValue("collapsed")
        // ONE dual-import destination, mirroring the expanded footer exactly: cards append here,
        // list drags forward to the same reorder routing — computed at the pill's own width so the
        // before/after midline lands at the pill's centre, not `columnWidth`'s.
        .dropDestination(for: ColumnDropPayload.self) { items, location in
            guard let payload = items.first else { return false }
            switch payload {
            case .card(let transfer):
                return appendCard(transfer)
            case .list(let transfer):
                return handleDrop(transfer: transfer, location: location, width: collapsedWidth)
            }
        } isTargeted: { isPillTargeted = $0 }
    }

    // MARK: - Header (drag source, rename, delete, collapse)

    private var header: some View {
        HStack(spacing: 8) {
            InlineEditableText(
                list.name,
                beginEditOn: .doubleClick,
                font: .headline,
                accessibilityID: AccessibilityID.listHeader(list.name),
                beginEditSignal: $beginRenameList
            ) { newName in
                store.renameList(list, to: newName)
            }
            Spacer(minLength: 4)
            // M11: plain total ("3") normally; "visible/total" ("1/3") while a label filter is
            // active and hiding at least one card — see `countLabel`. Plain quiet text (no capsule):
            // a passive count dressed as a pill read as a control beside the real chevron button.
            Text(countLabel)
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .accessibilityIdentifier(AccessibilityID.listCardCount(list.name))
            // Collapse chevron — placed TRAILING so it never overlaps the leading rename/drag
            // regions: the name owns double-click-rename, the header body owns the list drag. A
            // Button captures its own click, so tapping the chevron collapses without starting a
            // drag or a rename. The 4pt label padding grows the mouse target past the bare glyph.
            Button(action: collapse) {
                Image(systemName: "chevron.left")
                    .font(.caption.weight(.semibold))
                    .padding(4)
                    .contentShape(Rectangle())
            }
            .buttonStyle(HoverHighlightButtonStyle())
            .help("Collapse list")
            .accessibilityIdentifier(AccessibilityID.collapseListButton(list.name))
            .accessibilityLabel("Collapse \(list.name)")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .contextMenu {
            Button("Rename List") { beginRenameList = true }
            Button("Add Card") { startAddingCard() }
            Button("Collapse List", action: collapse)
            Divider()
            Button("Delete List", role: .destructive) {
                isPresentingDeleteConfirm = true
            }
        }
        // Single click must NOT enter rename mode (see `InlineEditableText`'s `.doubleClick`
        // trigger above) — it's reserved for starting this drag instead.
        .draggable(ListTransfer(listID: list.id))
    }

    // MARK: - Cards

    /// M11 (LB-03): renders `visibleCards` (the filtered set), NOT `list.sortedCards` — but every
    /// DROP-INDEX computation below (`appendCard`, `handleDrop`, and `CardView.dropOnRow`) still
    /// reasons about the FULL `list.sortedCards` / `board.sortedLists`, deliberately unchanged. The
    /// filter is pure rendering state; touching drop math would mean re-deriving indices for a
    /// frozen, empirically-proven M4→M5 architecture for a P2 feature that doesn't need it. Accepted
    /// MVP consequence: with a filter active, a drop that visually lands "between" two now-hidden
    /// cards still resolves against their FULL-list position, which can be a card's-width off from
    /// where it looks like it landed. `BoardStore.moveCard`'s semantics are entirely untouched
    /// either way — this is a rendering-only decision, made once, here.
    private var cardList: some View {
        ScrollView {
            VStack(spacing: 8) {
                ForEach(visibleCards) { card in
                    CardView(
                        board: board,
                        list: list,
                        card: card,
                        store: store,
                        selectedCardID: $selectedCardID,
                        onOpenCard: onOpenCard,
                        onDeleteCard: onDeleteCard
                    )
                }
                addCardRow
                footerDropZone
            }
            .padding(.vertical, 4)
        }
    }

    /// Inline card creation, pinned below the card stack. A click reveals a `TextField`; Enter
    /// commits via `store.addCard` AND re-opens an empty field (Trello-style rapid entry) — Esc
    /// closes it. Empty/whitespace Enter is a no-op that keeps the field open.
    @ViewBuilder
    private var addCardRow: some View {
        if isAddingCard {
            // Styled as the card it is about to become: same surface + hairline as `CardView`.
            TextField("Card title", text: $newCardDraft)
                .textFieldStyle(.plain)
                .focused($isAddCardFocused)
                .reportsTextInputFocus()
                .onSubmit(commitNewCard)
                .onExitCommand(perform: cancelNewCard)
                .onAppear { isAddCardFocused = true }
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: rowHeight)
                .padding(.horizontal, 10)
                .background(Color.cardSurface, in: RoundedRectangle(cornerRadius: 6))
                // Non-hit-testing so caret clicks reach the field (see CardDetailView's hairline).
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.surfaceHairline).allowsHitTesting(false))
                .accessibilityIdentifier(AccessibilityID.newCardField)
        } else {
            Button(action: startAddingCard) {
                Label("Add Card", systemImage: "plus")
                    .font(.callout)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: rowHeight)
                    .padding(.horizontal, 10)
                    .contentShape(Rectangle())
            }
            .buttonStyle(HoverHighlightButtonStyle())
            .accessibilityIdentifier(AccessibilityID.addCardButton(list: list.name))
            // Append-drop preview: the footer's ColumnDropPayload destination appends to the END
            // of the list, which materializes ABOVE this row — so the indicator belongs on this
            // row's top edge, not (as before) below it on the footer zone. Overlay only: no
            // layout shift, and the frozen drop topology is untouched.
            .overlay(alignment: .top) {
                InsertionIndicator()
                    .opacity(isFooterTargeted ? 1 : 0)
            }
        }
    }

    /// The body area beneath the cards: the double-click-to-add-card affordance, the card
    /// append/drop target (also THE drop target for an empty list, which has no `CardView` rows),
    /// and a pass-through for list-reorder drops that land on the column body. Sized tall so that,
    /// for a sparse or empty list, it fills the column body (a double-click or drop near the
    /// column's center lands here rather than on dead ScrollView space).
    ///
    /// ONE `.dropDestination` of the dual-import `ColumnDropPayload` type — NOT a plain
    /// CardTransfer destination, and NOT two stacked typed destinations. Both simpler shapes were
    /// tried and failed against real drags; see `ColumnDropPayload` / the type doc. Cards append;
    /// lists forward to the exact same `handleDrop` routing as the container's own destination
    /// (drop location here is in footer space, whose x differs from column space only by the 8pt
    /// column padding — negligible against the 140pt before/after midline).
    private var footerDropZone: some View {
        Color.clear
            .frame(maxWidth: .infinity, minHeight: 400)
            .contentShape(Rectangle())
            .onTapGesture(count: 2, perform: startAddingCard)
            .dropDestination(for: ColumnDropPayload.self) { items, location in
                guard let payload = items.first else { return false }
                switch payload {
                case .card(let transfer):
                    return appendCard(transfer)
                case .list(let transfer):
                    return handleDrop(transfer: transfer, location: location)
                }
            } isTargeted: { isFooterTargeted = $0 }
    }

    // MARK: - Add-card flow

    private func startAddingCard() {
        newCardDraft = ""
        isAddingCard = true
        isAddCardFocused = true
    }

    private func commitNewCard() {
        let trimmed = newCardDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return } // no-op; stay editing
        store.addCard(to: list, title: trimmed)
        newCardDraft = ""
        isAddCardFocused = true // re-open an empty field for the next card
    }

    private func cancelNewCard() {
        isAddingCard = false
        newCardDraft = ""
    }

    // MARK: - Card drop routing (footer append; copied from the spike's `dropOnFooter`)

    private func appendCard(_ transfer: CardTransfer) -> Bool {
        isFooterTargeted = false
        guard let movingCard = findCard(transfer.cardID) else { return false }
        let sameList = movingCard.list?.id == list.id
        // Same-list: `moveCard` reorders within the same-length array, so "last" is count-1.
        // Cross-list: `moveCard` inserts into the destination array (which excludes the card),
        // so "append" is count.
        let index = sameList ? list.sortedCards.count - 1 : list.sortedCards.count
        store.moveCard(movingCard, to: list, at: index)
        return true
    }

    private func findCard(_ id: UUID) -> Card? {
        board.sortedLists.flatMap { $0.sortedCards }.first { $0.id == id }
    }

    // MARK: - Collapse / expand (M9)

    private func collapse() { store.setCollapsed(list, true) }
    private func expand() { store.setCollapsed(list, false) }

    // MARK: - Drop routing

    /// `width` defaults to this column's `columnWidth` (the expanded container's + footer's callers
    /// pass nothing); the collapsed pill overrides it with its own narrow width so the before/after
    /// midline is computed at the pill's scale, not the full column's.
    private func handleDrop(transfer: ListTransfer, location: CGPoint, width: CGFloat? = nil) -> Bool {
        setTargeted(false)
        guard let movingList = board.sortedLists.first(where: { $0.id == transfer.listID }) else { return false }
        let siblings = board.sortedLists
        guard let rowIndex = siblings.firstIndex(where: { $0.id == list.id }) else { return false }
        let fromIndex = siblings.firstIndex(where: { $0.id == movingList.id })
        let edge = DropMath.insertionEdge(locationX: location.x, columnWidth: width ?? columnWidth)
        let index = DropMath.destinationIndex(rowIndex: rowIndex, edge: edge, movingFromIndexInSameList: fromIndex)
        store.moveList(movingList, to: index)
        return true
    }

    private func setTargeted(_ isTargeted: Bool) {
        if isTargeted {
            targetedListID = list.id
        } else if targetedListID == list.id {
            targetedListID = nil
        }
    }
}
