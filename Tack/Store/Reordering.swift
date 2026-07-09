import Foundation

/// Pure ordering math used by BoardStore to keep sibling positions contiguous.
/// No SwiftData/SwiftUI imports — everything here is a plain, total, deterministic function.
enum Reordering {
    /// Moves the element currently at `from` to end up at `to` in the returned array.
    /// Both indices are clamped into valid range; `from == to` (after clamping) is the identity.
    /// - Parameters:
    ///   - from: index of the element to move, in the ORIGINAL array. Clamped to `0...count-1`.
    ///   - to: the element's target index in the RESULTING array (same length as input). Clamped to `0...count-1`.
    static func movedWithin<Element>(_ items: [Element], from: Int, to: Int) -> [Element] {
        guard !items.isEmpty else { return items }
        let sourceIndex = clamp(from, lower: 0, upper: items.count - 1)
        var result = items
        let element = result.remove(at: sourceIndex)
        let destinationIndex = clamp(to, lower: 0, upper: result.count)
        result.insert(element, at: destinationIndex)
        return result
    }

    /// SwiftUI `.onMove` convention (same as the stdlib overlay's `move(fromOffsets:toOffset:)`):
    /// `fromOffsets` are offsets into the ORIGINAL array; `toOffset` is the insertion offset in
    /// the ORIGINAL (pre-removal) array — so for a single element, `toOffset == from` and
    /// `toOffset == from + 1` are both the identity. Total: out-of-range source offsets are
    /// dropped, `toOffset` is clamped into `0...count`. Implemented by hand (not via the
    /// Foundation/SwiftUI overlay method) to keep this file UI-framework-free; the semantics
    /// are pinned by ReorderingTests.
    static func movedWithin<Element>(_ items: [Element], fromOffsets source: IndexSet, toOffset destination: Int) -> [Element] {
        let sourceOffsets = source.filter { items.indices.contains($0) } // ascending: IndexSet iterates in order
        guard !sourceOffsets.isEmpty else { return items }
        let clampedDestination = clamp(destination, lower: 0, upper: items.count)
        // Insertion index in the post-removal array: the destination minus however many
        // moving elements sat before it.
        let insertionIndex = clampedDestination - sourceOffsets.filter { $0 < clampedDestination }.count
        let moving = sourceOffsets.map { items[$0] }
        let sourceSet = Set(sourceOffsets)
        var result = items.enumerated().filter { !sourceSet.contains($0.offset) }.map(\.element)
        result.insert(contentsOf: moving, at: insertionIndex)
        return result
    }

    /// M-F: reorders the members of `subset` among the SLOTS they currently occupy in `items`,
    /// leaving every non-member at its exact index — the sectioned-sidebar reorder primitive
    /// (Board.position stays ONE global sequence; a per-area `.onMove` hands offsets into ITS
    /// section's rows, i.e. into `items.filter { subset.contains($0) }`, using the same SwiftUI
    /// pre-removal convention as `movedWithin(fromOffsets:toOffset:)`). Total: out-of-range
    /// offsets follow that overload's rules, a subset covering all of `items` IS that overload
    /// (pinned by ReorderingTests), and foreign subset members are simply never encountered.
    static func movedWithinSubset<Element: Hashable>(
        _ items: [Element], subset: Set<Element>,
        fromOffsets source: IndexSet, toOffset destination: Int
    ) -> [Element] {
        let members = items.filter { subset.contains($0) }
        let reordered = movedWithin(members, fromOffsets: source, toOffset: destination)
        var iterator = reordered.makeIterator()
        return items.map { subset.contains($0) ? (iterator.next() ?? $0) : $0 }
    }

    /// Returns the array with the element at `index` removed. Out-of-range `index` is a no-op.
    static func removed<Element>(_ items: [Element], at index: Int) -> [Element] {
        guard items.indices.contains(index) else { return items }
        var result = items
        result.remove(at: index)
        return result
    }

    /// Returns the array with `element` inserted at `index`, clamped into `0...count`.
    static func inserted<Element>(_ element: Element, into items: [Element], at index: Int) -> [Element] {
        var result = items
        let clampedIndex = clamp(index, lower: 0, upper: result.count)
        result.insert(element, at: clampedIndex)
        return result
    }

    /// Self-healing: maps arbitrary (possibly gappy/duplicated) integer positions onto a
    /// contiguous `0..<n` range, preserving the relative order implied by the input values.
    /// Ties are broken by original array order (stable).
    static func normalized(_ positions: [Int]) -> [Int] {
        guard !positions.isEmpty else { return [] }
        let rankedIndices = positions.enumerated()
            .sorted { $0.element < $1.element }
            .map(\.offset)
        var result = [Int](repeating: 0, count: positions.count)
        for (rank, originalIndex) in rankedIndices.enumerated() {
            result[originalIndex] = rank
        }
        return result
    }

    private static func clamp(_ value: Int, lower: Int, upper: Int) -> Int {
        max(lower, min(value, upper))
    }
}
