import SwiftUI

/// One list column: header (name + card-count badge, draggable for board-level list reordering,
/// double-click-to-rename via `InlineEditableText`, context menu to delete) and a read-only stack
/// of its cards. Card interactions (create/edit/delete/drag) arrive in M5 — this milestone renders
/// them as plain rows.
///
/// Follows the exact container/row accessibility structure proven by the M2 spike
/// (`Views/Spike/SpikeBoardView.swift`): the column is one `.contain` container
/// (`AccessibilityID.list(name)`) and each card row keeps its own individually-queryable
/// identifier underneath it — nesting an ancestor `.contain` id does NOT swallow a descendant's
/// own `.accessibilityIdentifier`, as the spike's card rows already prove.
struct ListColumnView: View {
    let board: Board
    let list: BoardList
    let store: BoardStore
    let columnWidth: CGFloat
    @Binding var targetedListID: UUID?

    /// Same fixed row height as the M2 spike, so its DropMath reasoning carries over unchanged
    /// once M5 adds card drag/drop to this view.
    private let rowHeight: CGFloat = 44

    @State private var isPresentingDeleteConfirm = false

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
        // NOTE for M5: once cards can be dragged INTO/WITHIN a column, this view will also need a
        // `.dropDestination(for: CardTransfer.self)` (an append/reorder target for cards) living
        // alongside this list-reorder destination. SwiftUI dispatches drop payloads by
        // Transferable type, so the two coexist without either swallowing the other's drops — see
        // the M2 spike's per-row + footer dual `CardTransfer` destinations for the pattern, and
        // confirm `DragAndDropUITests` (which exercises `CardTransfer` against `SpikeBoardView`,
        // unaffected by this file) stays green after adding it.
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

    // MARK: - Cards (read-only in M4)

    private var cardList: some View {
        ScrollView {
            VStack(spacing: 8) {
                ForEach(list.sortedCards) { card in
                    cardRow(card)
                }
            }
        }
    }

    private func cardRow(_ card: Card) -> some View {
        Text(card.title)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: rowHeight)
            .padding(.horizontal, 10)
            .background(Color.secondary.opacity(0.18), in: RoundedRectangle(cornerRadius: 6))
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier(AccessibilityID.card(card.title))
    }

    private var insertionIndicator: some View {
        RoundedRectangle(cornerRadius: 1.5)
            .fill(Color.accentColor)
            .frame(width: 3)
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
