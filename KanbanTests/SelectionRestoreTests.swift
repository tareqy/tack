import Testing
import Foundation
@testable import Kanban

@Suite("SelectionRestore")
struct SelectionRestoreTests {
    private func board(_ name: String, position: Int, id: UUID = UUID()) -> Board {
        Board(id: id, name: name, position: position)
    }

    @Test("saved id matches an existing board -> that board")
    func savedIDMatchesReturnsThatBoard() {
        let targetID = UUID()
        let a = board("Alpha", position: 0)
        let b = board("Beta", position: 1, id: targetID)
        let c = board("Gamma", position: 2)

        let result = SelectionRestore.resolve(savedID: targetID, boards: [a, b, c])
        #expect(result?.id == b.id)
    }

    @Test("saved id is stale (no matching board) -> first by position")
    func staleSavedIDFallsBackToFirstByPosition() {
        let a = board("Alpha", position: 0)
        let b = board("Beta", position: 1)

        let result = SelectionRestore.resolve(savedID: UUID(), boards: [a, b])
        #expect(result?.id == a.id)
    }

    @Test("no boards -> nil regardless of saved id")
    func noBoardsReturnsNil() {
        #expect(SelectionRestore.resolve(savedID: UUID(), boards: []) == nil)
        #expect(SelectionRestore.resolve(savedID: nil, boards: []) == nil)
    }

    @Test("nil saved id -> first by position")
    func nilSavedIDReturnsFirstByPosition() {
        let a = board("Alpha", position: 0)
        let b = board("Beta", position: 1)

        let result = SelectionRestore.resolve(savedID: nil, boards: [b, a])
        #expect(result?.id == a.id)
    }

    @Test("first-by-position ignores input array order")
    func firstByPositionIgnoresArrayOrder() {
        let a = board("Alpha", position: 5)
        let b = board("Beta", position: 2)
        let c = board("Gamma", position: 9)

        let result = SelectionRestore.resolve(savedID: nil, boards: [a, c, b])
        #expect(result?.id == b.id)
    }
}
