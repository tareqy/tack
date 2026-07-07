import Testing
import Foundation
@testable import Tack

/// Pure carry-over of the M3 sidebar "which board is selected after a delete" logic.
@Suite("NextBoardSelection")
struct NextBoardSelectionTests {

    @Test("delete a middle board → the next board by position")
    func deleteMiddleSelectsNext() {
        let a = (id: UUID(), position: 0)
        let b = (id: UUID(), position: 1)
        let c = (id: UUID(), position: 2)
        #expect(NextBoardSelection.resolve(afterDeleting: b.id, boards: [a, b, c]) == c.id)
    }

    @Test("delete the last board → the previous (new last) board")
    func deleteLastSelectsPrevious() {
        let a = (id: UUID(), position: 0)
        let b = (id: UUID(), position: 1)
        let c = (id: UUID(), position: 2)
        #expect(NextBoardSelection.resolve(afterDeleting: c.id, boards: [a, b, c]) == b.id)
    }

    @Test("delete the only board → nil")
    func deleteOnlyReturnsNil() {
        let a = (id: UUID(), position: 0)
        #expect(NextBoardSelection.resolve(afterDeleting: a.id, boards: [a]) == nil)
    }

    @Test("resolution ignores input array order (keys off position)")
    func ignoresArrayOrder() {
        let a = (id: UUID(), position: 0)
        let b = (id: UUID(), position: 1)
        let c = (id: UUID(), position: 2)
        // Unsorted input; deleting the middle by position still yields c.
        #expect(NextBoardSelection.resolve(afterDeleting: b.id, boards: [c, a, b]) == c.id)
    }

    @Test("delete the first of several → the next by position")
    func deleteFirstSelectsNext() {
        let a = (id: UUID(), position: 0)
        let b = (id: UUID(), position: 1)
        #expect(NextBoardSelection.resolve(afterDeleting: a.id, boards: [a, b]) == b.id)
    }
}
