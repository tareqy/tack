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
///
/// VISIBILITY (final review, cross-milestone seam): `BoardSnapshot(board:)` builds the VISIBLE
/// snapshot — a collapsed list contributes ZERO `cardIDs` (its cards aren't on screen), and, when
/// a label filter is active, only cards matching the filter appear. Keyboard selection navigation
/// and ⌘-arrow moves both consume this snapshot, so both agree with what the user actually sees:
/// arrows traverse only visible cards, and a card can never be keyboard-moved INTO a collapsed
/// list. `isCollapsed` is carried per list (not merely inferred from an empty `cardIDs`) so
/// `moveTarget` can distinguish a collapsed list — never a valid move destination — from an
/// empty-but-expanded one, which still is (you can move a card into an empty open list).
struct BoardSnapshot: Equatable {
    struct ListSnapshot: Equatable {
        let id: UUID
        let cardIDs: [UUID]
        /// Whether the list is collapsed (a narrow pill on screen). Collapsed lists carry no
        /// `cardIDs` here; this flag keeps them distinguishable from empty expanded lists for
        /// `moveTarget`'s destination-skipping. Defaulted so pure-logic tests that don't exercise
        /// collapse keep constructing snapshots positionally.
        let isCollapsed: Bool

        init(id: UUID, cardIDs: [UUID], isCollapsed: Bool = false) {
            self.id = id
            self.cardIDs = cardIDs
            self.isCollapsed = isCollapsed
        }
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
    /// `listIndex` indexes the FULL `board.sortedLists` (the snapshot keeps every list, including
    /// collapsed ones, so the returned index maps straight back at the call site).
    ///
    /// - up/down: swap within the current list (target = neighbour's index). At the top edge for
    ///   up, or the bottom edge for down, returns nil (clamped — the move is a no-op).
    /// - left/right: the nearest adjacent list in that direction that is NOT collapsed — an
    ///   empty EXPANDED list is a valid destination (you can move a card into it), but a collapsed
    ///   list is skipped over (a card can't be keyboard-moved into a collapsed column; visual
    ///   adjacency is among the OPEN columns), mirroring how selection nav skips it. Inserts at
    ///   `min(currentRowIndex, destinationCount)` so a shorter destination appends. nil when there
    ///   is no non-collapsed list that way.
    /// - nil selection (or an id no longer on the board / in a collapsed-or-filtered-out list) → nil.
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
            guard let dest = nearestNonCollapsedList(before: listIndex, in: lists) else { return nil }
            return (dest, min(cardIndex, lists[dest].cardIDs.count))
        case .right:
            guard let dest = nearestNonCollapsedList(after: listIndex, in: lists) else { return nil }
            return (dest, min(cardIndex, lists[dest].cardIDs.count))
        }
    }

    // MARK: - Private

    private static func firstCardOfFirstNonEmptyList(_ lists: [BoardSnapshot.ListSnapshot]) -> UUID? {
        lists.first(where: { !$0.cardIDs.isEmpty })?.cardIDs.first
    }

    /// The closest list index strictly before `index` that is not collapsed (empty expanded lists
    /// qualify — they're valid move destinations; collapsed ones are skipped). nil if none.
    private static func nearestNonCollapsedList(before index: Int, in lists: [BoardSnapshot.ListSnapshot]) -> Int? {
        (0..<index).reversed().first { !lists[$0].isCollapsed }
    }

    /// The closest list index strictly after `index` that is not collapsed. nil if none.
    private static func nearestNonCollapsedList(after index: Int, in lists: [BoardSnapshot.ListSnapshot]) -> Int? {
        guard index < lists.count - 1 else { return nil }
        return ((index + 1)..<lists.count).first { !lists[$0].isCollapsed }
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

/// Which list a New Card (⌘N) should be created on. Collapse-aware — a New Card can't open its
/// inline editor on a collapsed list (the column shows only a pill), so:
/// - a selected card whose list is EXPANDED → that list (it's visible in the snapshot, so
///   `cardIDs.contains` finds it — collapsed lists contribute no `cardIDs`);
/// - otherwise (no/stale selection, or the selected card's list is collapsed) → the first
///   NON-collapsed list;
/// - all lists collapsed, or no lists → nil, which disables the New Card command.
enum NewCardTarget {
    static func resolve(selectedCardID: UUID?, board: BoardSnapshot) -> UUID? {
        if let selectedCardID,
           let list = board.lists.first(where: { $0.cardIDs.contains(selectedCardID) }) {
            return list.id
        }
        return board.lists.first(where: { !$0.isCollapsed })?.id
    }
}
