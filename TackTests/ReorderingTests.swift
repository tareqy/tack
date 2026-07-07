import Testing
import Foundation
@testable import Tack

@Suite("Reordering")
struct ReorderingTests {
    let a = UUID()
    let b = UUID()
    let c = UUID()
    let d = UUID()

    var ids: [UUID] { [a, b, c, d] }

    @Test("identity move (from == to) leaves order unchanged")
    func identityMove() {
        let result = Reordering.movedWithin(ids, from: 1, to: 1)
        #expect(result == ids)
    }

    @Test("first to last moves the element to the end")
    func firstToLast() {
        let result = Reordering.movedWithin(ids, from: 0, to: 3)
        #expect(result == [b, c, d, a])
    }

    @Test("last to first moves the element to the start")
    func lastToFirst() {
        let result = Reordering.movedWithin(ids, from: 3, to: 0)
        #expect(result == [d, a, b, c])
    }

    @Test("adjacent move shifts by one position")
    func adjacentMove() {
        let result = Reordering.movedWithin(ids, from: 1, to: 2)
        #expect(result == [a, c, b, d])
    }

    @Test("out-of-range from index clamps to last valid index")
    func outOfRangeFromClamps() {
        let result = Reordering.movedWithin(ids, from: 999, to: 0)
        #expect(result == [d, a, b, c])
    }

    @Test("negative from index clamps to first valid index")
    func negativeFromClamps() {
        let result = Reordering.movedWithin(ids, from: -10, to: 3)
        #expect(result == [b, c, d, a])
    }

    @Test("out-of-range to index clamps to end")
    func outOfRangeToClamps() {
        let result = Reordering.movedWithin(ids, from: 0, to: 999)
        #expect(result == [b, c, d, a])
    }

    @Test("negative to index clamps to start")
    func negativeToClamps() {
        let result = Reordering.movedWithin(ids, from: 3, to: -10)
        #expect(result == [d, a, b, c])
    }

    @Test("empty array is a no-op")
    func emptyArrayNoOp() {
        let result = Reordering.movedWithin([UUID](), from: 0, to: 5)
        #expect(result.isEmpty)
    }

    @Test("removed drops the element at index")
    func removedDropsElement() {
        let result = Reordering.removed(ids, at: 1)
        #expect(result == [a, c, d])
    }

    @Test("removed out of range is a no-op")
    func removedOutOfRangeNoOp() {
        let result = Reordering.removed(ids, at: 99)
        #expect(result == ids)
    }

    @Test("inserted places element at index")
    func insertedPlacesElement() {
        let result = Reordering.inserted(d, into: [a, b, c], at: 1)
        #expect(result == [a, d, b, c])
    }

    @Test("inserted clamps out-of-range index to end")
    func insertedClampsToEnd() {
        let result = Reordering.inserted(d, into: [a, b, c], at: 99)
        #expect(result == [a, b, c, d])
    }

    @Test("normalized heals gaps to contiguous 0..<n preserving order")
    func normalizedHealsGaps() {
        let result = Reordering.normalized([0, 5, 2])
        #expect(result == [0, 2, 1])
    }

    @Test("normalized heals duplicates preserving relative order")
    func normalizedHealsDuplicates() {
        let result = Reordering.normalized([0, 0, 2, 5])
        #expect(result == [0, 1, 2, 3])
    }

    @Test("normalized on already-contiguous positions is identity")
    func normalizedIdentityWhenContiguous() {
        let result = Reordering.normalized([0, 1, 2, 3])
        #expect(result == [0, 1, 2, 3])
    }

    @Test("normalized on empty array is empty")
    func normalizedEmpty() {
        let result = Reordering.normalized([])
        #expect(result.isEmpty)
    }
}
