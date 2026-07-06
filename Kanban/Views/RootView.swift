import SwiftUI
import SwiftData

/// The real app shell: a boards sidebar plus a detail pane. Selection is persisted to
/// `@AppStorage` (keyed per `AppLaunchConfig.selectedBoardDefaultsKey` — see that type for the
/// UI-test isolation story) and restored via the pure `SelectionRestore.resolve`.
struct RootView: View {
    @Environment(BoardStore.self) private var store
    @Environment(\.modelContext) private var modelContext
    @Environment(\.undoManager) private var undoManager
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
        .onAppear(perform: wireUndoManager)
        .onChange(of: undoManagerID) { _, _ in wireUndoManager() }
        .onChange(of: selectedBoardID) { _, newValue in
            selectedBoardIDRaw = newValue?.uuidString
        }
        .sheet(isPresented: $isPresentingCreateBoard) {
            CreateBoardSheet(store: store) { created in
                selectedBoardID = created.id
            }
        }
        // Always-present board-navigation command surface (New Board, ⌘1–⌘9) — see AppCommands.
        .focusedSceneValue(\.boardSelectionActions, boardSelectionActions)
    }

    // MARK: - Command surface

    private var sortedBoards: [Board] { boards.sorted { $0.position < $1.position } }

    private var boardSelectionActions: BoardSelectionActions {
        BoardSelectionActions(
            newBoard: { isPresentingCreateBoard = true },
            selectBoard: { position in
                let ordered = sortedBoards
                guard position >= 1, position <= ordered.count else { return }
                selectedBoardID = ordered[position - 1].id
            },
            boardNames: sortedBoards.map(\.name)
        )
    }

    // MARK: - Undo wiring

    /// Identity of the current scene undo manager, so `onChange` can re-wire when the scene hands
    /// us a different one (UndoManager isn't Equatable, but ObjectIdentifier is).
    private var undoManagerID: ObjectIdentifier? { undoManager.map(ObjectIdentifier.init) }

    /// Points the model context at the scene's (window's) undo manager, which the system
    /// Edit ▸ Undo/Redo items and ⌘Z drive. Assigned once per manager identity; never detached.
    ///
    /// DELIBERATELY does NOT set `groupsByEvent = false` here — asymmetric with the unit-test
    /// setup (`TestContainer`), per coordinator direction. The M1 "explicit grouping +
    /// groupsByEvent=false" rule was derived for HEADLESS unit hosts, where no run loop exists to
    /// open event groups. In the running app there IS a run loop, and an on-disk SwiftData
    /// container performs undo registrations OUTSIDE BoardStore's explicit groups (autosave,
    /// relationship maintenance, lazy materialization). With `groupsByEvent = false` those stray
    /// registrations land at grouping level 0 and throw NSInternalInconsistencyException ("must
    /// begin a group before registering undo") → a SwiftData assertion crash — reproduced on
    /// deleteBoard's cascade, and as silent createBoard failures (AppKit swallows the exception
    /// mid-button-action, leaving the sheet open). With the default `groupsByEvent = true`, the
    /// run-loop event group absorbs them, and BoardStore's explicit begin/end pairs nest legally
    /// inside the event group; each user gesture triggers exactly one store mutation, so one ⌘Z
    /// still reverses exactly one operation (verified end-to-end by KeyboardShortcutUITests'
    /// stepwise-undo assertions).
    private func wireUndoManager() {
        guard let undoManager, modelContext.undoManager !== undoManager else { return }
        modelContext.undoManager = undoManager
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
