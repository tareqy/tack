import Testing
import Foundation
@testable import Tack

/// Pure "which list does ⌘N open the add-card editor on" logic.
@Suite("NewCardTarget")
struct NewCardTargetTests {

    private func makeBoard(_ counts: [Int]) -> (BoardSnapshot, [[UUID]]) {
        let ids = counts.map { count in (0..<count).map { _ in UUID() } }
        let lists = ids.map { BoardSnapshot.ListSnapshot(id: UUID(), cardIDs: $0) }
        return (BoardSnapshot(lists: lists), ids)
    }

    @Test("selected card in list B → list B")
    func selectedCardResolvesToItsList() {
        let (board, ids) = makeBoard([2, 2, 2])
        let targetListID = board.lists[1].id
        #expect(NewCardTarget.resolve(selectedCardID: ids[1][0], board: board) == targetListID)
    }

    @Test("no selection → the first list")
    func noSelectionResolvesToFirstList() {
        let (board, _) = makeBoard([2, 2])
        #expect(NewCardTarget.resolve(selectedCardID: nil, board: board) == board.lists.first?.id)
    }

    @Test("no selection but an empty first list still targets the first list")
    func noSelectionTargetsFirstListEvenIfEmpty() {
        let (board, _) = makeBoard([0, 2])
        #expect(NewCardTarget.resolve(selectedCardID: nil, board: board) == board.lists[0].id)
    }

    @Test("stale selection id (not on board) → the first list")
    func staleSelectionResolvesToFirstList() {
        let (board, _) = makeBoard([2, 2])
        #expect(NewCardTarget.resolve(selectedCardID: UUID(), board: board) == board.lists.first?.id)
    }

    @Test("no lists → nil")
    func noListsReturnsNil() {
        let board = BoardSnapshot(lists: [])
        #expect(NewCardTarget.resolve(selectedCardID: nil, board: board) == nil)
    }

    // MARK: - Collapse-aware matrix (final review)

    /// Builds a snapshot from `(cardCount, isCollapsed)` specs. A collapsed list carries NO
    /// `cardIDs` here — matching `BoardSnapshot(board:)`'s visible-snapshot contract — so
    /// `cardCount` on a collapsed list is only its structural presence, not selectable ids.
    private func makeBoard(_ specs: [(count: Int, collapsed: Bool)]) -> (BoardSnapshot, [[UUID]]) {
        let ids = specs.map { spec in spec.collapsed ? [] : (0..<spec.count).map { _ in UUID() } }
        let lists = zip(specs, ids).map { spec, listIDs in
            BoardSnapshot.ListSnapshot(id: UUID(), cardIDs: listIDs, isCollapsed: spec.collapsed)
        }
        return (BoardSnapshot(lists: lists), ids)
    }

    @Test("no selection, first list collapsed → the first NON-collapsed list")
    func noSelectionSkipsCollapsedFirstList() {
        let (board, _) = makeBoard([(0, true), (2, false)])
        #expect(NewCardTarget.resolve(selectedCardID: nil, board: board) == board.lists[1].id)
    }

    @Test("selected card in an expanded list → that list even when an earlier list is collapsed")
    func selectedExpandedListWinsOverEarlierCollapsed() {
        let (board, ids) = makeBoard([(0, true), (2, false)])
        #expect(NewCardTarget.resolve(selectedCardID: ids[1][0], board: board) == board.lists[1].id)
    }

    @Test("a selection not in any visible (expanded) list falls back to the first non-collapsed list")
    func selectionInCollapsedListFallsBackToFirstExpanded() {
        // list 0 is collapsed (no visible cardIDs), list 1 expanded: a stale/collapsed-list
        // selection id resolves to the first expanded list.
        let (board, _) = makeBoard([(3, true), (2, false)])
        #expect(NewCardTarget.resolve(selectedCardID: UUID(), board: board) == board.lists[1].id)
    }

    @Test("all lists collapsed → nil (New Card disabled)")
    func allCollapsedReturnsNil() {
        let (board, _) = makeBoard([(2, true), (3, true)])
        #expect(NewCardTarget.resolve(selectedCardID: nil, board: board) == nil)
    }
}
