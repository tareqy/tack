import SwiftUI
import SwiftData

/// M2 de-risking spike: the minimum viable board that exercises the real drag-and-drop pipeline
/// end-to-end (Transferable payload -> DropMath -> BoardStore.moveCard -> on-disk persistence) so
/// XCUITest can prove it drives reliably. Deliberately ugly: two columns of card titles, an
/// insertion indicator line, and nothing else. Production board UI is M4/M5.
struct SpikeBoardView: View {
    let board: Board
    let store: BoardStore

    /// Fixed so DropMath has a deterministic row height to reason about the midline against.
    private let rowHeight: CGFloat = 44

    @State private var targetedCardID: UUID?
    @State private var targetedListID: UUID?

    var body: some View {
        HStack(alignment: .top, spacing: 24) {
            ForEach(board.sortedLists) { list in
                columnView(list)
            }
        }
        .padding(24)
        .frame(minWidth: 640, minHeight: 560, alignment: .topLeading)
    }

    // MARK: - Column

    private func columnView(_ list: BoardList) -> some View {
        VStack(spacing: 8) {
            Text(list.name)
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)

            ScrollView {
                VStack(spacing: 8) {
                    ForEach(list.sortedCards) { card in
                        cardRow(card, in: list)
                    }
                    footerDropZone(list)
                }
                .frame(maxWidth: .infinity)
                .padding(8)
            }
        }
        .frame(width: 240, height: 460)
        .padding(8)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AccessibilityID.list(list.name))
    }

    // MARK: - Card row (drag source + per-row drop target)

    private func cardRow(_ card: Card, in list: BoardList) -> some View {
        Text(card.title)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: rowHeight)
            .padding(.horizontal, 10)
            .background(Color.secondary.opacity(0.18), in: RoundedRectangle(cornerRadius: 6))
            .overlay(alignment: .top) {
                insertionIndicator
                    .opacity(targetedCardID == card.id ? 1 : 0)
            }
            .contentShape(Rectangle())
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier(AccessibilityID.card(card.title))
            .draggable(CardTransfer(cardID: card.id))
            .dropDestination(for: CardTransfer.self) { items, location in
                guard let transfer = items.first else { return false }
                let edge = DropMath.insertionEdge(locationY: location.y, rowHeight: rowHeight)
                return dropOnRow(transfer: transfer, targetCard: card, targetList: list, edge: edge)
            } isTargeted: { isTargeted in
                setTargetedCard(card.id, isTargeted)
            }
    }

    // MARK: - Footer drop zone (append target that fills the rest of the column)

    private func footerDropZone(_ list: BoardList) -> some View {
        Color.clear
            .frame(maxWidth: .infinity, minHeight: 260)
            .overlay(alignment: .top) {
                insertionIndicator
                    .opacity(targetedListID == list.id ? 1 : 0)
            }
            .contentShape(Rectangle())
            .dropDestination(for: CardTransfer.self) { items, _ in
                guard let transfer = items.first else { return false }
                return dropOnFooter(transfer: transfer, targetList: list)
            } isTargeted: { isTargeted in
                setTargetedList(list.id, isTargeted)
            }
    }

    private var insertionIndicator: some View {
        RoundedRectangle(cornerRadius: 1.5)
            .fill(Color.accentColor)
            .frame(height: 3)
    }

    // MARK: - Drop routing

    private func dropOnRow(transfer: CardTransfer, targetCard: Card, targetList: BoardList, edge: DropMath.InsertionEdge) -> Bool {
        clearTargeting()
        guard let movingCard = findCard(transfer.cardID) else { return false }
        let destinationCards = targetList.sortedCards
        guard let rowIndex = destinationCards.firstIndex(where: { $0.id == targetCard.id }) else { return false }

        let sameList = movingCard.list?.id == targetList.id
        let fromIndex: Int? = sameList ? destinationCards.firstIndex(where: { $0.id == movingCard.id }) : nil
        let index = DropMath.destinationIndex(rowIndex: rowIndex, edge: edge, movingFromIndexInSameList: fromIndex)
        store.moveCard(movingCard, to: targetList, at: index)
        return true
    }

    private func dropOnFooter(transfer: CardTransfer, targetList: BoardList) -> Bool {
        clearTargeting()
        guard let movingCard = findCard(transfer.cardID) else { return false }
        let sameList = movingCard.list?.id == targetList.id
        // Same-list: `moveCard` reorders within the same-length array, so "last" is count-1.
        // Cross-list: `moveCard` inserts into the destination array (which excludes the card),
        // so "append" is count.
        let index = sameList ? targetList.sortedCards.count - 1 : targetList.sortedCards.count
        store.moveCard(movingCard, to: targetList, at: index)
        return true
    }

    // MARK: - Helpers

    private func findCard(_ id: UUID) -> Card? {
        board.sortedLists.flatMap { $0.sortedCards }.first { $0.id == id }
    }

    private func setTargetedCard(_ id: UUID, _ isTargeted: Bool) {
        if isTargeted {
            targetedCardID = id
        } else if targetedCardID == id {
            targetedCardID = nil
        }
    }

    private func setTargetedList(_ id: UUID, _ isTargeted: Bool) {
        if isTargeted {
            targetedListID = id
        } else if targetedListID == id {
            targetedListID = nil
        }
    }

    private func clearTargeting() {
        targetedCardID = nil
        targetedListID = nil
    }
}
