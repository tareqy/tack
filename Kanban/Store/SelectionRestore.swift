import Foundation

/// Pure decision logic for which board the sidebar should select when it appears (fresh launch
/// or relaunch). No SwiftUI/SwiftData imports — `savedID` and `boards` are plain values so this
/// is unit-testable without a ModelContainer.
enum SelectionRestore {
    /// - Saved id matches one of `boards` (by `Board.id`): that board wins, so the user's
    ///   selection survives a relaunch.
    /// - Otherwise (saved id is nil, or stale — points at a board that no longer exists): the
    ///   first board by `position`.
    /// - No boards at all: nil.
    ///
    /// Looks up the minimum by `position` rather than assuming `boards` is pre-sorted, so callers
    /// (and tests) don't have to sort before calling.
    static func resolve(savedID: UUID?, boards: [Board]) -> Board? {
        if let savedID, let match = boards.first(where: { $0.id == savedID }) {
            return match
        }
        return boards.min { $0.position < $1.position }
    }
}
