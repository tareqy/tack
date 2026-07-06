import Testing
import Foundation
@testable import Kanban

/// Full matrix for the pure keyboard-navigation math (`SelectionNavigation.next` /
/// `.moveTarget`). Snapshots are built directly from plain UUIDs — no ModelContainer.
@Suite("SelectionNavigation")
struct SelectionNavigationTests {

    /// Builds a snapshot from lists of card counts, returning both the snapshot and the flat
    /// id grid so tests can name specific cards as `ids[list][card]`.
    private func makeBoard(_ counts: [Int]) -> (BoardSnapshot, [[UUID]]) {
        let ids = counts.map { count in (0..<count).map { _ in UUID() } }
        let lists = ids.map { BoardSnapshot.ListSnapshot(id: UUID(), cardIDs: $0) }
        return (BoardSnapshot(lists: lists), ids)
    }

    // MARK: - Within-list up/down

    @Test("down within a list moves to the next card")
    func downWithinList() {
        let (board, ids) = makeBoard([3])
        #expect(SelectionNavigation.next(selectedCardID: ids[0][0], direction: .down, board: board) == ids[0][1])
        #expect(SelectionNavigation.next(selectedCardID: ids[0][1], direction: .down, board: board) == ids[0][2])
    }

    @Test("up within a list moves to the previous card")
    func upWithinList() {
        let (board, ids) = makeBoard([3])
        #expect(SelectionNavigation.next(selectedCardID: ids[0][2], direction: .up, board: board) == ids[0][1])
        #expect(SelectionNavigation.next(selectedCardID: ids[0][1], direction: .up, board: board) == ids[0][0])
    }

    @Test("down from the last card of the only list clamps (stays)")
    func downClampsAtBottomOfOnlyList() {
        let (board, ids) = makeBoard([3])
        #expect(SelectionNavigation.next(selectedCardID: ids[0][2], direction: .down, board: board) == ids[0][2])
    }

    @Test("up from the first card of the only list clamps (stays)")
    func upClampsAtTopOfOnlyList() {
        let (board, ids) = makeBoard([3])
        #expect(SelectionNavigation.next(selectedCardID: ids[0][0], direction: .up, board: board) == ids[0][0])
    }

    // MARK: - Cross-list at boundaries

    @Test("down from last card crosses to the first card of the next list")
    func downCrossesToNextList() {
        let (board, ids) = makeBoard([2, 2])
        #expect(SelectionNavigation.next(selectedCardID: ids[0][1], direction: .down, board: board) == ids[1][0])
    }

    @Test("up from first card crosses to the last card of the previous list")
    func upCrossesToPreviousList() {
        let (board, ids) = makeBoard([2, 2])
        #expect(SelectionNavigation.next(selectedCardID: ids[1][0], direction: .up, board: board) == ids[0][1])
    }

    @Test("down crossing SKIPS an empty list in between")
    func downSkipsEmptyListDown() {
        let (board, ids) = makeBoard([1, 0, 1])
        #expect(SelectionNavigation.next(selectedCardID: ids[0][0], direction: .down, board: board) == ids[2][0])
    }

    @Test("up crossing SKIPS an empty list in between")
    func upSkipsEmptyListUp() {
        let (board, ids) = makeBoard([1, 0, 1])
        #expect(SelectionNavigation.next(selectedCardID: ids[2][0], direction: .up, board: board) == ids[0][0])
    }

    @Test("down from the last card of the last non-empty list clamps")
    func downClampsWhenNoFurtherNonEmptyList() {
        let (board, ids) = makeBoard([1, 0])
        #expect(SelectionNavigation.next(selectedCardID: ids[0][0], direction: .down, board: board) == ids[0][0])
    }

    // MARK: - Left / right index clamping

    @Test("right moves to the same-index card in the next non-empty list")
    func rightSameIndex() {
        let (board, ids) = makeBoard([3, 3])
        #expect(SelectionNavigation.next(selectedCardID: ids[0][2], direction: .right, board: board) == ids[1][2])
    }

    @Test("left moves to the same-index card in the previous non-empty list")
    func leftSameIndex() {
        let (board, ids) = makeBoard([3, 3])
        #expect(SelectionNavigation.next(selectedCardID: ids[1][1], direction: .left, board: board) == ids[0][1])
    }

    @Test("right clamps the row index to the shorter destination's last card")
    func rightClampsToShorterList() {
        let (board, ids) = makeBoard([3, 2])
        // From row 2 of a 3-card list into a 2-card list → clamps to index 1.
        #expect(SelectionNavigation.next(selectedCardID: ids[0][2], direction: .right, board: board) == ids[1][1])
    }

    @Test("right skips an empty list and clamps into the next non-empty one")
    func rightSkipsEmptyList() {
        let (board, ids) = makeBoard([2, 0, 1])
        #expect(SelectionNavigation.next(selectedCardID: ids[0][1], direction: .right, board: board) == ids[2][0])
    }

    /// M11 carried cleanup (M7 minor): the left-direction mirror of `rightSkipsEmptyList`, using
    /// the exact same board shape reversed — a 2-card list, an empty list, then a 1-card list —
    /// so `previousNonEmptyList` must both SKIP the empty middle list AND clamp the row index into
    /// the shorter destination, just like the right-direction case already covers.
    @Test("left skips an empty list and clamps into the previous non-empty one")
    func leftSkipsEmptyList() {
        let (board, ids) = makeBoard([1, 0, 2])
        #expect(SelectionNavigation.next(selectedCardID: ids[2][1], direction: .left, board: board) == ids[0][0])
    }

    @Test("left at the first list clamps (stays)")
    func leftAtFirstListStays() {
        let (board, ids) = makeBoard([2, 2])
        #expect(SelectionNavigation.next(selectedCardID: ids[0][0], direction: .left, board: board) == ids[0][0])
    }

    @Test("right at the last list clamps (stays)")
    func rightAtLastListStays() {
        let (board, ids) = makeBoard([2, 2])
        #expect(SelectionNavigation.next(selectedCardID: ids[1][0], direction: .right, board: board) == ids[1][0])
    }

    // MARK: - nil-selection entry & empty board

    @Test("nil selection + any direction enters at the first card of the first non-empty list")
    func nilSelectionEntersFirstCard() {
        let (board, ids) = makeBoard([0, 2, 1])
        for direction in [MoveDirection.up, .down, .left, .right] {
            #expect(SelectionNavigation.next(selectedCardID: nil, direction: direction, board: board) == ids[1][0])
        }
    }

    @Test("a stale (not-found) id is treated like nil selection")
    func staleIDEntersFirstCard() {
        let (board, ids) = makeBoard([1, 1])
        #expect(SelectionNavigation.next(selectedCardID: UUID(), direction: .down, board: board) == ids[0][0])
    }

    @Test("empty board (no cards anywhere) → nil")
    func emptyBoardReturnsNil() {
        let (board, _) = makeBoard([0, 0])
        #expect(SelectionNavigation.next(selectedCardID: nil, direction: .down, board: board) == nil)
    }

    @Test("single-list board: up/down clamp, left/right stay")
    func singleListBoard() {
        let (board, ids) = makeBoard([2])
        #expect(SelectionNavigation.next(selectedCardID: ids[0][0], direction: .left, board: board) == ids[0][0])
        #expect(SelectionNavigation.next(selectedCardID: ids[0][0], direction: .right, board: board) == ids[0][0])
        #expect(SelectionNavigation.next(selectedCardID: ids[0][0], direction: .down, board: board) == ids[0][1])
        #expect(SelectionNavigation.next(selectedCardID: ids[0][1], direction: .up, board: board) == ids[0][0])
    }

    // MARK: - moveTarget

    @Test("moveTarget up swaps with the card above")
    func moveTargetUp() {
        let (board, ids) = makeBoard([3])
        let target = SelectionNavigation.moveTarget(selectedCardID: ids[0][2], direction: .up, board: board)
        #expect(target?.listIndex == 0)
        #expect(target?.insertIndex == 1)
    }

    @Test("moveTarget down swaps with the card below")
    func moveTargetDown() {
        let (board, ids) = makeBoard([3])
        let target = SelectionNavigation.moveTarget(selectedCardID: ids[0][0], direction: .down, board: board)
        #expect(target?.listIndex == 0)
        #expect(target?.insertIndex == 1)
    }

    @Test("moveTarget up at the top edge is clamped to nil")
    func moveTargetUpClampedNil() {
        let (board, ids) = makeBoard([3])
        #expect(SelectionNavigation.moveTarget(selectedCardID: ids[0][0], direction: .up, board: board) == nil)
    }

    @Test("moveTarget down at the bottom edge is clamped to nil")
    func moveTargetDownClampedNil() {
        let (board, ids) = makeBoard([3])
        #expect(SelectionNavigation.moveTarget(selectedCardID: ids[0][2], direction: .down, board: board) == nil)
    }

    @Test("moveTarget right inserts at the same index in a longer adjacent list")
    func moveTargetRightSameIndex() {
        let (board, ids) = makeBoard([3, 3])
        let target = SelectionNavigation.moveTarget(selectedCardID: ids[0][1], direction: .right, board: board)
        #expect(target?.listIndex == 1)
        #expect(target?.insertIndex == 1)
    }

    @Test("moveTarget right APPENDS when the adjacent list is shorter")
    func moveTargetRightAppendsShorter() {
        let (board, ids) = makeBoard([3, 1])
        // Row 2 into a 1-card list → min(2, 1) = 1 (append after its single card).
        let target = SelectionNavigation.moveTarget(selectedCardID: ids[0][2], direction: .right, board: board)
        #expect(target?.listIndex == 1)
        #expect(target?.insertIndex == 1)
    }

    @Test("moveTarget left into an EMPTY adjacent list inserts at 0")
    func moveTargetLeftIntoEmpty() {
        let (board, ids) = makeBoard([0, 2])
        let target = SelectionNavigation.moveTarget(selectedCardID: ids[1][1], direction: .left, board: board)
        #expect(target?.listIndex == 0)
        #expect(target?.insertIndex == 0)
    }

    @Test("moveTarget does NOT skip an empty adjacent list (literal index ± 1)")
    func moveTargetLiteralAdjacency() {
        let (board, ids) = makeBoard([1, 0, 1])
        // Right from list 0 lands in the empty list 1 (index 1), not the far list 2.
        let target = SelectionNavigation.moveTarget(selectedCardID: ids[0][0], direction: .right, board: board)
        #expect(target?.listIndex == 1)
        #expect(target?.insertIndex == 0)
    }

    @Test("moveTarget left at the first list → nil")
    func moveTargetLeftEdgeNil() {
        let (board, ids) = makeBoard([2, 2])
        #expect(SelectionNavigation.moveTarget(selectedCardID: ids[0][0], direction: .left, board: board) == nil)
    }

    @Test("moveTarget right at the last list → nil")
    func moveTargetRightEdgeNil() {
        let (board, ids) = makeBoard([2, 2])
        #expect(SelectionNavigation.moveTarget(selectedCardID: ids[1][0], direction: .right, board: board) == nil)
    }

    @Test("moveTarget with nil selection → nil")
    func moveTargetNilSelection() {
        let (board, _) = makeBoard([2, 2])
        #expect(SelectionNavigation.moveTarget(selectedCardID: nil, direction: .down, board: board) == nil)
    }

    // MARK: - Visibility: collapsed lists (final-review cross-milestone seam)

    /// Builds a snapshot from `(cardCount, isCollapsed)` specs. A collapsed list carries NO
    /// `cardIDs` (matching `BoardSnapshot(board:)`'s visible-snapshot contract).
    private func makeBoard(_ specs: [(count: Int, collapsed: Bool)]) -> (BoardSnapshot, [[UUID]]) {
        let ids = specs.map { spec in spec.collapsed ? [] : (0..<spec.count).map { _ in UUID() } }
        let lists = zip(specs, ids).map { spec, listIDs in
            BoardSnapshot.ListSnapshot(id: UUID(), cardIDs: listIDs, isCollapsed: spec.collapsed)
        }
        return (BoardSnapshot(lists: lists), ids)
    }

    @Test("selection nav skips a collapsed list entirely (down/up cross over it)")
    func navSkipsCollapsedListUpDown() {
        let (board, ids) = makeBoard([(1, false), (2, true), (1, false)])
        // Down from the only card of list 0 crosses the collapsed list 1 to list 2's first card.
        #expect(SelectionNavigation.next(selectedCardID: ids[0][0], direction: .down, board: board) == ids[2][0])
        // Up mirrors it.
        #expect(SelectionNavigation.next(selectedCardID: ids[2][0], direction: .up, board: board) == ids[0][0])
    }

    @Test("selection nav left/right skips a collapsed list to the next visible one")
    func navSkipsCollapsedListLeftRight() {
        let (board, ids) = makeBoard([(1, false), (1, true), (1, false)])
        #expect(SelectionNavigation.next(selectedCardID: ids[0][0], direction: .right, board: board) == ids[2][0])
        #expect(SelectionNavigation.next(selectedCardID: ids[2][0], direction: .left, board: board) == ids[0][0])
    }

    @Test("moveTarget skips a collapsed adjacent list into the next open list (can't move into collapsed)")
    func moveTargetSkipsCollapsedList() {
        let (board, ids) = makeBoard([(2, false), (1, true), (1, false)])
        // Right from list 0's second card: collapsed list 1 is skipped; lands in open list 2,
        // clamped to its end (min(1, 1) = 1).
        let right = SelectionNavigation.moveTarget(selectedCardID: ids[0][1], direction: .right, board: board)
        #expect(right?.listIndex == 2)
        #expect(right?.insertIndex == 1)
        // Left mirrors it: from list 2's card, collapsed list 1 is skipped back to open list 0.
        let left = SelectionNavigation.moveTarget(selectedCardID: ids[2][0], direction: .left, board: board)
        #expect(left?.listIndex == 0)
        #expect(left?.insertIndex == 0)
    }

    @Test("moveTarget still allows moving into an EMPTY expanded adjacent list (collapse ≠ empty)")
    func moveTargetIntoEmptyExpandedStillWorks() {
        let (board, ids) = makeBoard([(2, false), (0, false)])
        let target = SelectionNavigation.moveTarget(selectedCardID: ids[0][0], direction: .right, board: board)
        #expect(target?.listIndex == 1)
        #expect(target?.insertIndex == 0)
    }

    @Test("moveTarget returns nil when every list that way is collapsed")
    func moveTargetNilWhenOnlyCollapsedThatWay() {
        let (board, ids) = makeBoard([(2, false), (1, true), (1, true)])
        #expect(SelectionNavigation.moveTarget(selectedCardID: ids[0][0], direction: .right, board: board) == nil)
    }

    // MARK: - Visibility: active label filter (navigation over the filtered snapshot)

    @Test("navigation over a filtered snapshot traverses only the visible cards")
    func navOverFilteredSnapshot() {
        // A single list whose middle card is filtered OUT (only cards 0 and 2 are visible): down
        // from the first visible card lands on the next VISIBLE card, skipping the hidden one.
        let visibleA = UUID(), visibleB = UUID()
        let board = BoardSnapshot(lists: [.init(id: UUID(), cardIDs: [visibleA, visibleB])])
        #expect(SelectionNavigation.next(selectedCardID: visibleA, direction: .down, board: board) == visibleB)
        #expect(SelectionNavigation.next(selectedCardID: visibleB, direction: .up, board: board) == visibleA)
    }
}
