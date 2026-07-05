import Testing
import Foundation
import CoreGraphics
@testable import Kanban

@Suite("DropMath")
struct DropMathTests {

    // MARK: - insertionEdge (midline)

    @Test("location above the midline resolves to .before")
    func aboveMidlineIsBefore() {
        #expect(DropMath.insertionEdge(locationY: 5, rowHeight: 40) == .before)
    }

    @Test("location below the midline resolves to .after")
    func belowMidlineIsAfter() {
        #expect(DropMath.insertionEdge(locationY: 35, rowHeight: 40) == .after)
    }

    @Test("location exactly on the midline resolves to .after (midline belongs to bottom half)")
    func exactlyOnMidlineIsAfter() {
        #expect(DropMath.insertionEdge(locationY: 20, rowHeight: 40) == .after)
    }

    @Test("top edge (y == 0) resolves to .before")
    func topEdgeIsBefore() {
        #expect(DropMath.insertionEdge(locationY: 0, rowHeight: 40) == .before)
    }

    @Test("bottom edge (y == rowHeight) resolves to .after")
    func bottomEdgeIsAfter() {
        #expect(DropMath.insertionEdge(locationY: 40, rowHeight: 40) == .after)
    }

    // MARK: - destinationIndex: cross-list (nil source index)

    @Test("cross-list drop before a row inserts at that row's index")
    func crossListBefore() {
        #expect(DropMath.destinationIndex(rowIndex: 1, edge: .before, movingFromIndexInSameList: nil) == 1)
    }

    @Test("cross-list drop after a row inserts just past that row")
    func crossListAfter() {
        #expect(DropMath.destinationIndex(rowIndex: 1, edge: .after, movingFromIndexInSameList: nil) == 2)
    }

    @Test("cross-list drop before the head row inserts at 0")
    func crossListHead() {
        #expect(DropMath.destinationIndex(rowIndex: 0, edge: .before, movingFromIndexInSameList: nil) == 0)
    }

    @Test("cross-list drop after the tail row appends past the tail")
    func crossListTail() {
        // Destination list has 3 cards (indices 0...2); after index 2 == append at 3.
        #expect(DropMath.destinationIndex(rowIndex: 2, edge: .after, movingFromIndexInSameList: nil) == 3)
    }

    // MARK: - destinationIndex: same-list (the classic off-by-one)

    @Test("same-list downward move after a lower row compensates the removed slot")
    func sameListDownwardAfter() {
        // [A,B,C], move A (from 0) after C (rowIndex 2): base = 2-1 = 1, after -> 2.
        // movedWithin([A,B,C], from: 0, to: 2) == [B,C,A]. Correct tail placement.
        #expect(DropMath.destinationIndex(rowIndex: 2, edge: .after, movingFromIndexInSameList: 0) == 2)
    }

    @Test("same-list downward move before a lower row compensates the removed slot")
    func sameListDownwardBefore() {
        // [A,B,C], move A (from 0) before C (rowIndex 2): base = 1, before -> 1.
        // movedWithin([A,B,C], from: 0, to: 1) == [B,A,C].
        #expect(DropMath.destinationIndex(rowIndex: 2, edge: .before, movingFromIndexInSameList: 0) == 1)
    }

    @Test("same-list upward move before a higher row needs no compensation")
    func sameListUpwardBefore() {
        // [A,B,C], move C (from 2) before A (rowIndex 0): base = 0, before -> 0.
        // movedWithin([A,B,C], from: 2, to: 0) == [C,A,B].
        #expect(DropMath.destinationIndex(rowIndex: 0, edge: .before, movingFromIndexInSameList: 2) == 0)
    }

    @Test("same-list upward move after a higher row needs no compensation")
    func sameListUpwardAfter() {
        // [A,B,C], move C (from 2) after A (rowIndex 0): base = 0, after -> 1.
        // movedWithin([A,B,C], from: 2, to: 1) == [A,C,B].
        #expect(DropMath.destinationIndex(rowIndex: 0, edge: .after, movingFromIndexInSameList: 2) == 1)
    }

    @Test("same-list drop onto own row is a near-identity index")
    func sameListOntoSelf() {
        // rowIndex == fromIndex: base = rowIndex (not >), before -> rowIndex.
        #expect(DropMath.destinationIndex(rowIndex: 1, edge: .before, movingFromIndexInSameList: 1) == 1)
    }

    // MARK: - Composition proofs (DropMath + Reordering produce the intended final order)

    @Test("same-list downward off-by-one composes to the correct final order")
    func compositionSameListDownward() {
        let ids = ["A", "B", "C"]
        // Move A after C.
        let from = 0
        let edge = DropMath.insertionEdge(locationY: 35, rowHeight: 40) // .after
        let to = DropMath.destinationIndex(rowIndex: 2, edge: edge, movingFromIndexInSameList: from)
        let result = Reordering.movedWithin(ids, from: from, to: to)
        #expect(result == ["B", "C", "A"])
    }

    @Test("same-list upward reorder composes to the correct final order")
    func compositionSameListUpward() {
        let ids = ["A", "B", "C"]
        // Move C to the very top (drop on top third of A).
        let from = 2
        let edge = DropMath.insertionEdge(locationY: 5, rowHeight: 40) // .before
        let to = DropMath.destinationIndex(rowIndex: 0, edge: edge, movingFromIndexInSameList: from)
        let result = Reordering.movedWithin(ids, from: from, to: to)
        #expect(result == ["C", "A", "B"])
    }

    @Test("cross-list insertion composes to the correct destination order")
    func compositionCrossList() {
        let destIDs = ["X", "Y"] // destination list WITHOUT the moving card
        let edge = DropMath.insertionEdge(locationY: 30, rowHeight: 40) // .after
        let index = DropMath.destinationIndex(rowIndex: 0, edge: edge, movingFromIndexInSameList: nil)
        let result = Reordering.inserted("M", into: destIDs, at: index)
        #expect(result == ["X", "M", "Y"])
    }
}
