import SwiftUI
import SwiftData

struct SidebarView: View {
    @Environment(BoardStore.self) private var store
    @Query(sort: \Board.position) private var boards: [Board]
    @Query(sort: \Area.position) private var areas: [Area]

    @Binding var selection: UUID?

    @State private var filterQuery = ""
    @State private var editingBoard: Board?
    @State private var boardPendingDeletion: Board?
    @State private var boardPendingNewArea: Board?
    @State private var renamingArea: Area?
    @State private var areaPendingDeletion: Area?

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

            List(selection: $selection) {
                if filterQuery.isEmpty {
                    sectionedRows
                } else {
                    // Filtering renders FLAT and headerless — the exact pre-M-F presentation.
                    // It searches ALL boards (collapsed areas included: search must find what
                    // collapse hides) and carries NO .onMove anywhere, which keeps B-06's
                    // "reorder enabled ⇔ showing all boards" invariant structural instead of
                    // gated (the old nil-handler trick).
                    ForEach(filteredBoards) { board in
                        boardRow(board)
                    }
                }
            }
            .listStyle(.sidebar)
            .confirmationDialog(
                deleteAreaDialogTitle,
                isPresented: isPresentingAreaDeleteDialog,
                titleVisibility: .visible
            ) {
                Button("Delete Area", role: .destructive) { performAreaDelete() }
                    .accessibilityIdentifier(AccessibilityID.deleteAreaConfirm)
                Button("Cancel", role: .cancel) { areaPendingDeletion = nil }
            } message: {
                Text(areaDeleteMessage)
            }
        }
        // The "New Board" toolbar button lives on `RootView`'s `NavigationSplitView`, not here —
        // see the comment there for why a toolbar contributed from this view doesn't work.
        .sheet(item: $editingBoard) { board in
            EditBoardSheet(board: board, store: store)
        }
        .sheet(item: $boardPendingNewArea) { board in
            AreaNameSheet(mode: .create(moving: board), store: store)
        }
        .sheet(item: $renamingArea) { area in
            AreaNameSheet(mode: .rename(area), store: store)
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
        } message: {
            // Board delete detaches the undo manager and clears the stack (see
            // `BoardStore.deleteBoard`) — the one thing this dialog must say.
            Text("This deletes all of its lists and cards. You can't undo this.")
        }
    }

    /// M-F: ungrouped boards FIRST, headerless — with zero areas this renders byte-identically
    /// to the pre-M-F flat sidebar — then one Section per area in area-position order. Rows stay
    /// in GLOBAL position order within their section (the @Query sort); each section's `.onMove`
    /// passes its section-local offsets STRAIGHT THROUGH to
    /// `moveBoards(fromOffsets:toOffset:in:)` — the B-06 contract, index math still in one
    /// place (`Reordering.movedWithinSubset`), nowhere in this view.
    @ViewBuilder
    private var sectionedRows: some View {
        ForEach(ungroupedBoards) { board in
            boardRow(board)
        }
        .onMove { source, destination in
            store.moveBoards(fromOffsets: source, toOffset: destination, in: nil)
        }
        ForEach(areas) { area in
            Section {
                // The header rides as the section's FIRST ROW, deliberately NOT `header:` —
                // Section-header hosting flattens its AX subtree under XCUITest (the observed
                // evidence: ONE StaticText survives, carrying only the chevron's own id
                // area-toggle-<name>; the container's area-<name> id is absent and the chevron
                // Button is demoted to non-interactive; see AreaHeaderView's HOSTING note).
                // `.selectionDisabled` keeps the untagged row out of the List's selection
                // machinery.
                AreaHeaderView(area: area, store: store,
                               onRename: { renamingArea = area },
                               onDelete: { areaPendingDeletion = area })
                    .selectionDisabled(true)
                // A collapsed area contributes NO rows to the tree (the oracle AreaUITests
                // leans on) — BoardSnapshot's collapsed-list precedent, one level up.
                if !area.isCollapsed {
                    ForEach(boards(in: area)) { board in
                        boardRow(board)
                    }
                    .onMove { source, destination in
                        store.moveBoards(fromOffsets: source, toOffset: destination, in: area)
                    }
                }
            }
        }
    }

    private var ungroupedBoards: [Board] {
        boards.filter { $0.area == nil }
    }

    private func boards(in area: Area) -> [Board] {
        boards.filter { $0.area?.id == area.id }
    }

    private func boardRow(_ board: Board) -> some View {
        BoardRowView(board: board)
            .contextMenu {
                Button("Edit Board…") { editingBoard = board }
                moveToAreaMenu(for: board)
                Button("Delete", role: .destructive) { boardPendingDeletion = board }
            }
    }

    /// M-F design (e): the committed cross-area move UX — the CardView "Move to List" submenu
    /// shape, proven driveable under XCUITest. Current membership is communicated by DISABLING
    /// the current destination (also prevents no-op churn; setArea's guard is the backstop).
    @ViewBuilder
    private func moveToAreaMenu(for board: Board) -> some View {
        Menu("Move to Area") {
            ForEach(areas) { area in
                Button(area.name) { store.setArea(board, to: area) }
                    .disabled(board.area?.id == area.id)
            }
            if !areas.isEmpty {
                Button("No Area") { store.setArea(board, to: nil) }
                    .disabled(board.area == nil)
                Divider()
            }
            Button("New Area…") { boardPendingNewArea = board }
        }
    }

    private var deleteAreaDialogTitle: String {
        guard let area = areaPendingDeletion else { return "" }
        return "Delete “\(area.name)”?"
    }

    private var isPresentingAreaDeleteDialog: Binding<Bool> {
        Binding(
            get: { areaPendingDeletion != nil },
            set: { presented in if !presented { areaPendingDeletion = nil } }
        )
    }

    /// Nullify copy: boards SURVIVE — this dialog must say so (contrast the board-delete
    /// dialog's data-loss warning). Undo sentence per the Task 0 verdict: leg A is RED
    /// (`deleteArea` adopted the detach-and-clear discipline, non-undoable — see
    /// `BoardStore.deleteArea`), so this appends the board-delete dialog's exact "can't undo"
    /// sentence rather than staying silent about undo.
    private var areaDeleteMessage: String {
        guard let area = areaPendingDeletion else { return "" }
        let count = area.boards.count
        if count == 0 { return "This area contains no boards. You can't undo this." }
        let noun = count == 1 ? "Its board" : "Its \(count) boards"
        return "\(noun) will be kept and moved out of the area. You can't undo this."
    }

    private func performAreaDelete() {
        guard let area = areaPendingDeletion else { return }
        // Selection needs no repair: nullify releases boards, it never deletes them —
        // NextBoardSelection stays a board-delete-only concern.
        store.deleteArea(area)
        areaPendingDeletion = nil
    }

    private var deleteDialogTitle: String {
        guard let board = boardPendingDeletion else { return "" }
        return "Delete “\(board.name)”?"
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
