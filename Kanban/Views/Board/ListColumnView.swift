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

    /// Same fixed row height as the M2 spike, so its DropMath reasoning carries over unchanged.
    private let rowHeight: CGFloat = 44

    @State private var isPresentingDeleteConfirm = false
    @State private var isAddingCard = false
    @State private var newCardDraft = ""
    @FocusState private var isAddCardFocused: Bool
    @State private var isFooterTargeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            Divider()
            cardList
        }
        .padding(8)
        .frame(width: columnWidth, alignment: .topLeading)
        .frame(maxHeight: .infinity)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        .overlay(alignment: .leading) {
            insertionIndicator
                .opacity(targetedListID == list.id ? 1 : 0)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AccessibilityID.list(list.name))
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
        .confirmationDialog(
            "Delete \"\(list.name)\"? Its \(list.cards.count) cards will be deleted.",
            isPresented: $isPresentingDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                store.deleteList(list)
            }
            .accessibilityIdentifier(AccessibilityID.deleteListConfirm)
            Button("Cancel", role: .cancel) {}
        }
    }

    // MARK: - Header (drag source, rename, delete)

    private var header: some View {
        HStack(spacing: 8) {
            InlineEditableText(
                list.name,
                beginEditOn: .doubleClick,
                font: .headline,
                accessibilityID: AccessibilityID.listHeader(list.name)
            ) { newName in
                store.renameList(list, to: newName)
            }
            Spacer(minLength: 4)
            Text("\(list.cards.count)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.secondary.opacity(0.2), in: Capsule())
                .accessibilityIdentifier(AccessibilityID.listCardCount(list.name))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .contextMenu {
            Button("Delete List", role: .destructive) {
                isPresentingDeleteConfirm = true
            }
        }
        // Single click must NOT enter rename mode (see `InlineEditableText`'s `.doubleClick`
        // trigger above) — it's reserved for starting this drag instead.
        .draggable(ListTransfer(listID: list.id))
    }

    // MARK: - Cards

    private var cardList: some View {
        ScrollView {
            VStack(spacing: 8) {
                ForEach(list.sortedCards) { card in
                    CardView(
                        board: board,
                        list: list,
                        card: card,
                        store: store,
                        selectedCardID: $selectedCardID
                    )
                }
                addCardRow
                footerDropZone
            }
            .padding(.vertical, 2)
        }
    }

    /// Inline card creation, pinned below the card stack. A click reveals a `TextField`; Enter
    /// commits via `store.addCard` AND re-opens an empty field (Trello-style rapid entry) — Esc
    /// closes it. Empty/whitespace Enter is a no-op that keeps the field open.
    @ViewBuilder
    private var addCardRow: some View {
        if isAddingCard {
            TextField("Card title", text: $newCardDraft)
                .textFieldStyle(.plain)
                .focused($isAddCardFocused)
                .onSubmit(commitNewCard)
                .onExitCommand(perform: cancelNewCard)
                .onAppear { isAddCardFocused = true }
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: rowHeight)
                .padding(.horizontal, 10)
                .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
                .accessibilityIdentifier(AccessibilityID.newCardField)
        } else {
            Button(action: startAddingCard) {
                Label("Add card", systemImage: "plus")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: rowHeight)
                    .padding(.horizontal, 10)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .accessibilityIdentifier(AccessibilityID.addCardButton(list: list.name))
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
            .overlay(alignment: .top) {
                InsertionIndicator()
                    .opacity(isFooterTargeted ? 1 : 0)
            }
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

    private var insertionIndicator: some View {
        RoundedRectangle(cornerRadius: 1.5)
            .fill(Color.accentColor)
            .frame(width: 3)
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

    // MARK: - Drop routing

    private func handleDrop(transfer: ListTransfer, location: CGPoint) -> Bool {
        setTargeted(false)
        guard let movingList = board.sortedLists.first(where: { $0.id == transfer.listID }) else { return false }
        let siblings = board.sortedLists
        guard let rowIndex = siblings.firstIndex(where: { $0.id == list.id }) else { return false }
        let fromIndex = siblings.firstIndex(where: { $0.id == movingList.id })
        let edge = DropMath.insertionEdge(locationX: location.x, columnWidth: columnWidth)
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
