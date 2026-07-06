import Testing
import Foundation
@testable import Kanban

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
}
