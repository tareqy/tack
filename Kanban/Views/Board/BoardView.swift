import SwiftUI

/// The real board surface: a header showing the selected board's emoji + name, followed by a
/// horizontal scroll of `ListColumnView`s and a trailing `AddListButton`. Cards are fully
/// interactive (M5): create/rename/delete/select plus production drag-and-drop.
struct BoardView: View {
    let board: Board
    let store: BoardStore

    /// Fixed so DropMath (and the visual layout) have a deterministic column width to reason
    /// about the midline against — same rationale as the M2 spike's fixed `rowHeight`.
    static let columnWidth: CGFloat = 280

    @State private var targetedListID: UUID?
    /// Board-local single-card selection. M7 migrates this to `FocusedValues` (for the ⌘⌫ Edit-menu
    /// shortcut); keep it simple @State for now, per the brief.
    @State private var selectedCardID: UUID?
    /// The card currently showing its M6 detail sheet, if any — bound into every `CardView` so
    /// double-click-body / context-menu "Open Card" can set it from anywhere on the board.
    @State private var selectedDetailCard: Card?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            columnsScrollView
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding()
        .sheet(item: $selectedDetailCard) { card in
            CardDetailView(card: card, store: store, onDelete: {
                // Order matters — see CardDetailView.onDelete: close the sheet (nil the item)
                // BEFORE deleting, so no re-render evaluates the sheet against a deleted card.
                selectedDetailCard = nil
                store.deleteCard(card)
            })
        }
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
                        targetedListID: $targetedListID,
                        selectedCardID: $selectedCardID,
                        selectedDetailCard: $selectedDetailCard
                    )
                }
                AddListButton(board: board, store: store, columnWidth: Self.columnWidth)
            }
            .padding(.vertical, 4)
        }
    }
}
