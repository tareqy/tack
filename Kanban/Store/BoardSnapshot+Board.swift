import Foundation

/// Bridges a live SwiftData `Board` to the pure `BoardSnapshot` the navigation math consumes.
/// Kept OUT of `SelectionNavigation.swift` so that file stays free of any model dependency.
extension BoardSnapshot {
    /// Builds the VISIBLE snapshot (final-review cross-milestone seam): a collapsed list
    /// contributes ZERO `cardIDs` (its cards aren't on screen), and when `activeLabelFilter` is
    /// non-empty only the cards it keeps (OR semantics, via `LabelFilter`) appear — exactly what
    /// `ListColumnView` renders. Every list is still present (indices align with
    /// `board.sortedLists`), carrying its `isCollapsed` flag, so `SelectionNavigation.moveTarget`
    /// can tell a collapsed list (never a move destination) from an empty expanded one. With the
    /// default empty filter and no collapsed lists this is identical to the pre-review full snapshot.
    init(board: Board, activeLabelFilter: Set<LabelColor> = []) {
        self.init(lists: board.sortedLists.map { list in
            let visible = list.isCollapsed ? [] : LabelFilter.visibleCards(list.sortedCards, active: activeLabelFilter)
            return ListSnapshot(id: list.id, cardIDs: visible.map(\.id), isCollapsed: list.isCollapsed)
        })
    }
}
