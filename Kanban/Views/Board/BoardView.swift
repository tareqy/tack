import SwiftUI

/// The real board surface (M4), replacing `BoardPlaceholderView`: a header showing the selected
/// board's emoji + name, followed by a horizontal scroll of `ListColumnView`s and a trailing
/// `AddListButton`. Card content within each column is read-only in this milestone — creating,
/// editing, deleting, and dragging cards arrive in M5.
struct BoardView: View {
    let board: Board
    let store: BoardStore

    /// Fixed so DropMath (and the visual layout) have a deterministic column width to reason
    /// about the midline against — same rationale as the M2 spike's fixed `rowHeight`.
    static let columnWidth: CGFloat = 280

    @State private var targetedListID: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            columnsScrollView
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding()
    }

    private var header: some View {
        Text("\(board.emoji ?? "🗂️") \(board.name)")
            .font(.largeTitle)
            // `.combine` (not `.contain`): same trap as the placeholder this view replaces — see
            // `RootView` for the full write-up of why `board-detail` must stay a `.combine` leaf,
            // not a `.contain` ancestor of the columns below it.
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier(AccessibilityID.boardDetail)
    }

    private var columnsScrollView: some View {
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: 12) {
                ForEach(board.sortedLists) { list in
                    ListColumnView(
                        board: board,
                        list: list,
                        store: store,
                        columnWidth: Self.columnWidth,
                        targetedListID: $targetedListID
                    )
                }
                AddListButton(board: board, store: store, columnWidth: Self.columnWidth)
            }
            .padding(.vertical, 4)
        }
    }
}
