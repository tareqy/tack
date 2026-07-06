import Foundation

/// Bridges a live SwiftData `Board` to the pure `BoardSnapshot` the navigation math consumes.
/// Kept OUT of `SelectionNavigation.swift` so that file stays free of any model dependency.
extension BoardSnapshot {
    init(board: Board) {
        self.init(lists: board.sortedLists.map { list in
            ListSnapshot(id: list.id, cardIDs: list.sortedCards.map(\.id))
        })
    }
}
