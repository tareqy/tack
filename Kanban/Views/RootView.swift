import SwiftUI
import SwiftData

/// The real app shell: a boards sidebar plus a detail pane. Selection is persisted to
/// `@AppStorage` (keyed per `AppLaunchConfig.selectedBoardDefaultsKey` — see that type for the
/// UI-test isolation story) and restored via the pure `SelectionRestore.resolve`.
struct RootView: View {
    @Environment(BoardStore.self) private var store
    @Query(sort: \Board.position) private var boards: [Board]

    @AppStorage private var selectedBoardIDRaw: String?
    @State private var selectedBoardID: UUID?
    @State private var isPresentingCreateBoard = false

    init(config: AppLaunchConfig) {
        _selectedBoardIDRaw = AppStorage(config.selectedBoardDefaultsKey)
    }

    var body: some View {
        ZStack {
            // A detached marker (same trick as SpikeRootView's fallback), not an ancestor of
            // anything: empirically, `.accessibilityIdentifier` on `NavigationSplitView` itself
            // does NOT reach the underlying AX element (it keeps SwiftUI's auto-generated
            // type-name identifier instead — confirmed via an accessibility-hierarchy dump), so
            // root-view is hung off a sibling `Color.clear` instead. Being a sibling (not an
            // ancestor of the sidebar rows / board-detail) also sidesteps the M2 `.contain`
            // ancestor-inherits-id trap entirely. Verified empirically: smoke (`root-view`) and
            // board queries (`board-*`, `board-detail`) resolve correctly together (task-5 report).
            Color.clear
                .allowsHitTesting(false)
                .accessibilityIdentifier(AccessibilityID.rootView)

            NavigationSplitView {
                SidebarView(selection: $selectedBoardID)
            } detail: {
                detailContent
            }
            // Deliberately attached HERE (to the NavigationSplitView itself), not nested inside
            // SidebarView's content: empirically, a `.toolbar` contributed from the sidebar
            // column's own body reliably lands in the "more toolbar items" overflow popover and
            // never shows in the main bar, however much window width is available and regardless
            // of `ToolbarItem` id/placement/`defaultCustomization` — confirmed via `System Events`
            // UI inspection of a normally-launched build (empty toolbar space next to "Hide
            // Sidebar", item only reachable through the overflow menu). Moving the exact same
            // `ToolbarItem` up to the split view fixed it outright. See task-5 report.
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        isPresentingCreateBoard = true
                    } label: {
                        Label("New Board", systemImage: "plus")
                    }
                    .accessibilityIdentifier(AccessibilityID.newBoardButton)
                }
            }
        }
        .onAppear(perform: restoreSelectionIfNeeded)
        .onChange(of: selectedBoardID) { _, newValue in
            selectedBoardIDRaw = newValue?.uuidString
        }
        .sheet(isPresented: $isPresentingCreateBoard) {
            CreateBoardSheet(store: store) { created in
                selectedBoardID = created.id
            }
        }
    }

    @ViewBuilder
    private var detailContent: some View {
        if boards.isEmpty {
            EmptyStateView(onCreateBoard: { isPresentingCreateBoard = true })
        } else if let selectedBoardID, let board = boards.first(where: { $0.id == selectedBoardID }) {
            BoardView(board: board, store: store)
        } else {
            Text("Select a board")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// Restores the persisted selection on first appearance. Guarded so a later `.onAppear`
    /// (e.g. after a sheet dismiss) doesn't clobber a selection the user already made.
    private func restoreSelectionIfNeeded() {
        guard selectedBoardID == nil else { return }
        let savedID = selectedBoardIDRaw.flatMap(UUID.init(uuidString:))
        selectedBoardID = SelectionRestore.resolve(savedID: savedID, boards: boards)?.id
    }
}
