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

    // MARK: - movedWithin(fromOffsets:toOffset:) — SwiftUI .onMove convention
    // `toOffset` is the insertion offset in the PRE-REMOVAL array (what SwiftUI's
    // .onMove hands its handler), NOT the element's index in the resulting array.

    @Test("onMove: dragging the first row just below the second arrives as toOffset 2 and swaps them")
    func onMoveDownByOne() {
        let result = Reordering.movedWithin(ids, fromOffsets: IndexSet(integer: 0), toOffset: 2)
        #expect(result == [b, a, c, d])
    }

    @Test("onMove: move first to end (toOffset == count)")
    func onMoveFirstToEnd() {
        let result = Reordering.movedWithin(ids, fromOffsets: IndexSet(integer: 0), toOffset: 4)
        #expect(result == [b, c, d, a])
    }

    @Test("onMove: move last to front")
    func onMoveLastToFront() {
        let result = Reordering.movedWithin(ids, fromOffsets: IndexSet(integer: 3), toOffset: 0)
        #expect(result == [d, a, b, c])
    }

    @Test("onMove: toOffset == source offset is identity")
    func onMoveIdentitySameOffset() {
        let result = Reordering.movedWithin(ids, fromOffsets: IndexSet(integer: 1), toOffset: 1)
        #expect(result == ids)
    }

    @Test("onMove: toOffset == source offset + 1 is ALSO identity (pre-removal convention)")
    func onMoveIdentityNextOffset() {
        let result = Reordering.movedWithin(ids, fromOffsets: IndexSet(integer: 1), toOffset: 2)
        #expect(result == ids)
    }

    @Test("onMove: multi-element IndexSet moves all, preserving their relative order")
    func onMoveMultiElement() {
        let result = Reordering.movedWithin(ids, fromOffsets: IndexSet([0, 2]), toOffset: 4)
        #expect(result == [b, d, a, c])
    }

    @Test("onMove: out-of-range source offsets are dropped, valid ones still move")
    func onMoveInvalidSourceDropped() {
        let result = Reordering.movedWithin(ids, fromOffsets: IndexSet([0, 99]), toOffset: 4)
        #expect(result == [b, c, d, a])
    }

    @Test("onMove: entirely out-of-range source set is identity")
    func onMoveAllInvalidSourceIdentity() {
        let result = Reordering.movedWithin(ids, fromOffsets: IndexSet(integer: 99), toOffset: 0)
        #expect(result == ids)
    }

    @Test("onMove: negative toOffset clamps to start")
    func onMoveNegativeDestinationClamps() {
        let result = Reordering.movedWithin(ids, fromOffsets: IndexSet(integer: 3), toOffset: -5)
        #expect(result == [d, a, b, c])
    }

    @Test("onMove: oversized toOffset clamps to end")
    func onMoveOversizedDestinationClamps() {
        let result = Reordering.movedWithin(ids, fromOffsets: IndexSet(integer: 0), toOffset: 99)
        #expect(result == [b, c, d, a])
    }

    @Test("onMove: empty array is a no-op")
    func onMoveEmptyArray() {
        let result = Reordering.movedWithin([UUID](), fromOffsets: IndexSet(integer: 0), toOffset: 0)
        #expect(result.isEmpty)
    }

    // MARK: - movedWithinSubset (M-F)

    @Test("movedWithinSubset reorders members among their own slots; non-members keep exact indices")
    func movedWithinSubsetReordersMembersAmongTheirSlots() {
        // Slots: a(0) X(1) b(2) c(3) Y(4). Section = [a,b,c]; move c (offset 2) to front (offset 0).
        let result = Reordering.movedWithinSubset(["a", "X", "b", "c", "Y"],
                                                  subset: ["a", "b", "c"],
                                                  fromOffsets: IndexSet(integer: 2), toOffset: 0)
        #expect(result == ["c", "X", "a", "b", "Y"],
                "members permute across their OWN slots (0,2,3); X and Y never move")
    }

    @Test("movedWithinSubset with the full set matches movedWithin(fromOffsets:toOffset:)")
    func movedWithinSubsetFullSetMatchesMovedWithin() {
        let items = ["a", "b", "c", "d"]
        for from in 0..<4 {
            for to in 0...4 {
                let viaSubset = Reordering.movedWithinSubset(items, subset: Set(items),
                                                             fromOffsets: IndexSet(integer: from), toOffset: to)
                let direct = Reordering.movedWithin(items, fromOffsets: IndexSet(integer: from), toOffset: to)
                #expect(viaSubset == direct, "full-set subsequence reorder IS the flat reorder (from \(from) to \(to))")
            }
        }
    }

    @Test("movedWithinSubset is total: empty or foreign subsets and out-of-range offsets are the identity")
    func movedWithinSubsetEmptyOrForeignSubsetIsIdentity() {
        let items = ["a", "b", "c"]
        #expect(Reordering.movedWithinSubset(items, subset: [], fromOffsets: IndexSet(integer: 0), toOffset: 2) == items)
        #expect(Reordering.movedWithinSubset(items, subset: ["z"], fromOffsets: IndexSet(integer: 0), toOffset: 1) == items)
        #expect(Reordering.movedWithinSubset(items, subset: ["a", "c"], fromOffsets: IndexSet(integer: 9), toOffset: 0) == items,
                "out-of-range source offsets are dropped (the movedWithin convention)")
    }
}
