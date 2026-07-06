import SwiftUI
import SwiftData

struct SidebarView: View {
    @Environment(BoardStore.self) private var store
    @Query(sort: \Board.position) private var boards: [Board]

    @Binding var selection: UUID?

    @State private var filterQuery = ""
    @State private var renamingBoard: Board?
    @State private var boardPendingDeletion: Board?

    private var filteredBoards: [Board] {
        BoardStore.filterBoards(boards, query: filterQuery)
    }

    var body: some View {
        VStack(spacing: 0) {
            TextField("Filter boards", text: $filterQuery)
                .textFieldStyle(.roundedBorder)
                .reportsTextInputFocus()
                .padding(8)
                .accessibilityIdentifier(AccessibilityID.sidebarFilterField)

            List(filteredBoards, selection: $selection) { board in
                BoardRowView(board: board)
                    .contextMenu {
                        Button("Rename") { renamingBoard = board }
                        Button("Delete", role: .destructive) { boardPendingDeletion = board }
                    }
            }
            .listStyle(.sidebar)
        }
        // The "New Board" toolbar button lives on `RootView`'s `NavigationSplitView`, not here —
        // see the comment there for why a toolbar contributed from this view doesn't work.
        .sheet(item: $renamingBoard) { board in
            RenameBoardSheet(board: board, store: store)
        }
        .confirmationDialog(
            deleteDialogTitle,
            isPresented: isPresentingDeleteDialog,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                performDelete()
            }
            .accessibilityIdentifier(AccessibilityID.deleteBoardConfirm)
            Button("Cancel", role: .cancel) {
                boardPendingDeletion = nil
            }
        }
    }

    private var deleteDialogTitle: String {
        guard let board = boardPendingDeletion else { return "" }
        return "Delete \"\(board.name)\"? Its lists and cards will be deleted."
    }

    private var isPresentingDeleteDialog: Binding<Bool> {
        Binding(
            get: { boardPendingDeletion != nil },
            set: { presented in if !presented { boardPendingDeletion = nil } }
        )
    }

    /// Deletes the pending board. If it was selected, moves selection to the next board by
    /// position via the pure `NextBoardSelection.resolve` (the survivor immediately after it, or —
    /// if it was last — the new last survivor), or nil if none remain.
    private func performDelete() {
        guard let board = boardPendingDeletion else { return }
        let wasSelected = selection == board.id
        let nextSelection = NextBoardSelection.resolve(
            afterDeleting: board.id,
            boards: boards.map { (id: $0.id, position: $0.position) }
        )

        store.deleteBoard(board)
        boardPendingDeletion = nil

        if wasSelected {
            selection = nextSelection
        }
    }
}
