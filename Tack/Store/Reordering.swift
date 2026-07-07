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
