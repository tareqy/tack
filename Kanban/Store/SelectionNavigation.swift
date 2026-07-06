import Foundation

/// The four directional intents shared by keyboard selection-navigation (View menu ↑/↓) and
/// keyboard card-moving (Card menu ⌘-arrows). Named `MoveDirection` because it drives BOTH
/// "move the selection" and "move the selected card".
enum MoveDirection: Equatable {
    case up, down, left, right
}

/// A plain, SwiftData-free snapshot of a board's lists and their cards' ids, in position order.
/// Built at the call site from `board.sortedLists` / `sortedCards` (see `BoardSnapshot(board:)`),
/// so all the navigation math below is a pure function of value types — unit-testable without a
/// ModelContainer.
struct BoardSnapshot: Equatable {
    struct ListSnapshot: Equatable {
        let id: UUID
        let cardIDs: [UUID]
    }
    let lists: [ListSnapshot]
}

/// Pure keyboard navigation math. No SwiftUI/SwiftData — every function maps value inputs to
/// value outputs so the full matrix can be exhaustively unit-tested.
enum SelectionNavigation {
    /// Where the SELECTION should move for a bare-arrow keypress (View ▸ Select Next/Previous).
    ///
    /// - up/down: within the current list, clamped; at an end, cross to the previous/next
    ///   NON-EMPTY list — up from the first card lands on the LAST card of the previous non-empty
    ///   list, down from the last lands on the FIRST card of the next non-empty list. If there is
    ///   no such list, the selection stays put (clamp).
    /// - left/right: the card at the SAME row index in the previous/next non-empty list, clamped
    ///   to that list's `count - 1`. No such list → stay put.
    /// - nil selection (or an id no longer on the board) + any direction → the first card of the
    ///   first non-empty list (keyboard entry point).
    /// - Board with no cards at all → nil.
    static func next(selectedCardID: UUID?, direction: MoveDirection, board: BoardSnapshot) -> UUID? {
        let lists = board.lists

        guard let selectedCardID,
              let listIndex = lists.firstIndex(where: { $0.cardIDs.contains(selectedCardID) }),
              let cardIndex = lists[listIndex].cardIDs.firstIndex(of: selectedCardID) else {
            return firstCardOfFirstNonEmptyList(lists)
        }

        let cards = lists[listIndex].cardIDs

        switch direction {
        case .up:
            if cardIndex > 0 { return cards[cardIndex - 1] }
            if let prev = previousNonEmptyList(before: listIndex, in: lists) {
                return lists[prev].cardIDs.last
            }
            return selectedCardID
        case .down:
            if cardIndex < cards.count - 1 { return cards[cardIndex + 1] }
            if let next = nextNonEmptyList(after: listIndex, in: lists) {
                return lists[next].cardIDs.first
            }
            return selectedCardID
        case .left:
            if let prev = previousNonEmptyList(before: listIndex, in: lists) {
                let dest = lists[prev].cardIDs
                return dest[min(cardIndex, dest.count - 1)]
            }
            return selectedCardID
        case .right:
            if let next = nextNonEmptyList(after: listIndex, in: lists) {
                let dest = lists[next].cardIDs
                return dest[min(cardIndex, dest.count - 1)]
            }
            return selectedCardID
        }
    }

    /// Where the selected CARD should be moved for a ⌘-arrow keypress (Card ▸ Move Card …).
    /// Returns `(listIndex, insertIndex)` for `store.moveCard(_, to: lists[listIndex], at: insertIndex)`.
    ///
    /// - up/down: swap within the current list (target = neighbour's index). At the top edge for
    ///   up, or the bottom edge for down, returns nil (clamped — the move is a no-op).
    /// - left/right: the LITERALLY adjacent list (index ± 1, empty lists included as valid
    ///   destinations), inserting at `min(currentRowIndex, destinationCount)` so a shorter
    ///   destination appends. nil at the edge lists (no adjacent list that way).
    /// - nil selection (or an id no longer on the board) → nil.
    static func moveTarget(selectedCardID: UUID?, direction: MoveDirection, board: BoardSnapshot) -> (listIndex: Int, insertIndex: Int)? {
        let lists = board.lists
        guard let selectedCardID,
              let listIndex = lists.firstIndex(where: { $0.cardIDs.contains(selectedCardID) }),
              let cardIndex = lists[listIndex].cardIDs.firstIndex(of: selectedCardID) else {
            return nil
        }

        let cards = lists[listIndex].cardIDs

        switch direction {
        case .up:
            guard cardIndex > 0 else { return nil }
            return (listIndex, cardIndex - 1)
        case .down:
            guard cardIndex < cards.count - 1 else { return nil }
            return (listIndex, cardIndex + 1)
        case .left:
            guard listIndex > 0 else { return nil }
            let destCount = lists[listIndex - 1].cardIDs.count
            return (listIndex - 1, min(cardIndex, destCount))
        case .right:
            guard listIndex < lists.count - 1 else { return nil }
            let destCount = lists[listIndex + 1].cardIDs.count
            return (listIndex + 1, min(cardIndex, destCount))
        }
    }

    // MARK: - Private

    private static func firstCardOfFirstNonEmptyList(_ lists: [BoardSnapshot.ListSnapshot]) -> UUID? {
        lists.first(where: { !$0.cardIDs.isEmpty })?.cardIDs.first
    }

    private static func previousNonEmptyList(before index: Int, in lists: [BoardSnapshot.ListSnapshot]) -> Int? {
        guard index > 0 else { return nil }
        return (0..<index).reversed().first { !lists[$0].cardIDs.isEmpty }
    }

    private static func nextNonEmptyList(after index: Int, in lists: [BoardSnapshot.ListSnapshot]) -> Int? {
        guard index < lists.count - 1 else { return nil }
        return ((index + 1)..<lists.count).first { !lists[$0].cardIDs.isEmpty }
    }
}

/// Which board the sidebar should select after the current one is deleted (M3 carry-over,
/// extracted to a pure helper). `boards` includes the board being deleted, each paired with its
/// `position`.
///
/// - Delete a middle board → the survivor immediately after it by position.
/// - Delete the last board → the new last survivor (the one immediately before it).
/// - Delete the only board → nil.
enum NextBoardSelection {
    static func resolve(afterDeleting deletedID: UUID, boards: [(id: UUID, position: Int)]) -> UUID? {
        let survivors = boards
            .filter { $0.id != deletedID }
            .sorted { $0.position < $1.position }
        guard let deleted = boards.first(where: { $0.id == deletedID }) else {
            return survivors.first?.id
        }
        let next = survivors.first { $0.position > deleted.position } ?? survivors.last
        return next?.id
    }
}

/// Which list a New Card (⌘N) should be created on: the list containing the selected card
/// ("focused list"), else the first list of the board, else nil (no lists).
enum NewCardTarget {
    static func resolve(selectedCardID: UUID?, board: BoardSnapshot) -> UUID? {
        if let selectedCardID,
           let list = board.lists.first(where: { $0.cardIDs.contains(selectedCardID) }) {
            return list.id
        }
        return board.lists.first?.id
    }
}
