import SwiftUI

/// One card row: selectable (single click), renamable (double-click title OR context-menu "Rename
/// Card"), draggable, and a per-row drop target for reordering/cross-list moves. Productionizes the
/// M2 spike's `cardRow` (`Views/Spike/SpikeBoardView.swift`) — the draggable/dropDestination/
/// insertion-indicator/index-passing structure is copied from there unchanged; this view adds the
/// selection ring, inline rename, and context menu on top.
///
/// Accessibility mirrors the spike's proven shape with ONE deliberate difference: the row is a
/// `.contain` container (not `.combine`), so the title's `InlineEditableText` keeps its own
/// individually-queryable identifier underneath for the rename flow. The container still carries
/// `card(title)`; the title carries the non-`card-`-prefixed `cardTitle(title)` so the order
/// assertion (`identifier BEGINSWITH "card-"`) never double-counts a row.
struct CardView: View {
    let board: Board
    let list: BoardList
    let card: Card
    let store: BoardStore
    @Binding var selectedCardID: UUID?

    /// Same fixed row height as the M2 spike, so its DropMath midline reasoning carries over.
    private let rowHeight: CGFloat = 44

    @State private var isDropTargeted = false
    @State private var beginRename = false

    private var isSelected: Bool { selectedCardID == card.id }

    var body: some View {
        InlineEditableText(
            card.title,
            beginEditOn: .doubleClick,
            accessibilityID: AccessibilityID.cardTitle(card.title),
            beginEditSignal: $beginRename
        ) { newTitle in
            store.updateTitle(card, newTitle)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: rowHeight)
        .padding(.horizontal, 10)
        .background(Color.secondary.opacity(0.18), in: RoundedRectangle(cornerRadius: 6))
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(Color.accentColor, lineWidth: 2)
                .opacity(isSelected ? 1 : 0)
        }
        .overlay(alignment: .top) {
            InsertionIndicator()
                .opacity(isDropTargeted ? 1 : 0)
        }
        .contentShape(Rectangle())
        // Single click selects. Double-click lands on the title's own `.doubleClick` gesture
        // (a descendant gesture, which SwiftUI prioritizes over this ancestor one), so a rename
        // click never leaks into selection and vice-versa.
        .onTapGesture { selectedCardID = card.id }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AccessibilityID.card(card.title))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .draggable(CardTransfer(cardID: card.id))
        .dropDestination(for: CardTransfer.self) { items, location in
            guard let transfer = items.first else { return false }
            let edge = DropMath.insertionEdge(locationY: location.y, rowHeight: rowHeight)
            return dropOnRow(transfer: transfer, edge: edge)
        } isTargeted: { isDropTargeted = $0 }
        .contextMenu { contextMenu }
    }

    // MARK: - Context menu

    @ViewBuilder
    private var contextMenu: some View {
        Button("Rename Card") { beginRename = true }

        let others = board.sortedLists.filter { $0.id != list.id }
        if !others.isEmpty {
            Menu("Move to List") {
                ForEach(others) { other in
                    Button(other.name) {
                        // Cross-list append: destination array excludes the card, so "end" is count.
                        store.moveCard(card, to: other, at: other.cards.count)
                    }
                }
            }
        }

        // No confirmation (PRD v1.1 C-05: undoable via the store, Finder ⌘⌫ pattern).
        Button("Delete Card", role: .destructive) {
            if isSelected { selectedCardID = nil }
            store.deleteCard(card)
        }
    }

    // MARK: - Drop routing (copied from the spike's `dropOnRow`)

    private func dropOnRow(transfer: CardTransfer, edge: DropMath.InsertionEdge) -> Bool {
        isDropTargeted = false
        guard let movingCard = findCard(transfer.cardID) else { return false }
        let destinationCards = list.sortedCards
        guard let rowIndex = destinationCards.firstIndex(where: { $0.id == card.id }) else { return false }

        let sameList = movingCard.list?.id == list.id
        let fromIndex: Int? = sameList ? destinationCards.firstIndex(where: { $0.id == movingCard.id }) : nil
        let index = DropMath.destinationIndex(rowIndex: rowIndex, edge: edge, movingFromIndexInSameList: fromIndex)
        store.moveCard(movingCard, to: list, at: index)
        return true
    }

    private func findCard(_ id: UUID) -> Card? {
        board.sortedLists.flatMap { $0.sortedCards }.first { $0.id == id }
    }
}
