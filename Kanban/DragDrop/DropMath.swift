import Foundation
import CoreGraphics

/// Pure drag-and-drop insertion math. No SwiftUI/SwiftData imports — everything here is a
/// plain, total, deterministic function so it can be unit-tested in isolation (this is the
/// riskiest arithmetic in the drag pipeline: the same-list downward off-by-one).
enum DropMath {

    /// Which side of a target row a drop lands on.
    enum InsertionEdge {
        case before
        case after
    }

    /// Resolves whether a pointer at `locationY` within a row of height `rowHeight` is asking
    /// to insert before or after that row. The midline is the boundary; a point exactly on (or
    /// below) the midline belongs to the bottom half and resolves to `.after`.
    static func insertionEdge(locationY: CGFloat, rowHeight: CGFloat) -> InsertionEdge {
        edge(location: locationY, extent: rowHeight)
    }

    /// The horizontal twin of `insertionEdge(locationY:rowHeight:)`, for list-column reordering
    /// (M4): resolves whether a pointer at `locationX` within a column of width `columnWidth` is
    /// asking to insert before or after that column. Same midline-is-the-boundary semantics as the
    /// vertical case (a point exactly on the midline resolves to `.after`).
    static func insertionEdge(locationX: CGFloat, columnWidth: CGFloat) -> InsertionEdge {
        edge(location: locationX, extent: columnWidth)
    }

    /// Axis-agnostic midline test shared by both orientations above: a `location` in `0...extent`
    /// resolves to `.before` in the top/left half, `.after` in the bottom/right half (midline
    /// inclusive of `.after`).
    private static func edge(location: CGFloat, extent: CGFloat) -> InsertionEdge {
        location < extent / 2 ? .before : .after
    }

    /// Converts a "drop onto the row at `rowIndex`, on its `edge` side" gesture into the integer
    /// index to hand to `BoardStore.moveCard(_:to:at:)`.
    ///
    /// - Parameter movingFromIndexInSameList: the moving card's current index **when the drop is
    ///   within its own list**, or `nil` for a cross-list move. Same-list is where the classic
    ///   off-by-one lives: because the card first leaves its slot, every target below the source
    ///   shifts up by one, so we subtract one from `rowIndex` before applying the edge. Cross-list
    ///   needs no such compensation — the destination array doesn't contain the moving card.
    ///
    /// The returned index matches the semantics each `moveCard` branch expects: for same-list it is
    /// the target index in the same-length reordered array (`Reordering.movedWithin`); for cross-list
    /// it is the insertion index into the destination array excluding the card (`Reordering.inserted`).
    static func destinationIndex(rowIndex: Int, edge: InsertionEdge, movingFromIndexInSameList: Int?) -> Int {
        let base: Int
        if let fromIndex = movingFromIndexInSameList, rowIndex > fromIndex {
            base = rowIndex - 1
        } else {
            base = rowIndex
        }
        return edge == .after ? base + 1 : base
    }
}
