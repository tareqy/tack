import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// The real app shell: a boards sidebar plus a detail pane. Selection is persisted to
/// `@AppStorage` (keyed per `AppLaunchConfig.selectedBoardDefaultsKey` — see that type for the
/// UI-test isolation story) and restored via the pure `SelectionRestore.resolve`.
struct RootView: View {
    @Environment(BoardStore.self) private var store
    @Environment(\.modelContext) private var modelContext
    @Environment(\.undoManager) private var undoManager
    @Query(sort: \Board.position) private var boards: [Board]
    @Query(sort: \Area.position) private var areas: [Area]

    @AppStorage private var selectedBoardIDRaw: String?
    @State private var selectedBoardID: UUID?
    /// M-C: per-board view mode, the `selectedBoardIDRaw` triad pattern one more time —
    /// `@AppStorage` raw string (key from `AppLaunchConfig.viewModeDefaultsKey`), a live
    /// decoded map, seeded on appear and re-encoded on change.
    @AppStorage private var viewModesRaw: String?
    @State private var viewModes: [UUID: BoardViewMode] = [:]
    /// App-wide Settings preference plus a SNAPSHOT of the surface chosen for the current open.
    /// Keeping these separate is what makes a Settings change mid-edit apply only next time.
    @AppStorage private var cardDetailPresentationRaw: String
    @State private var presentedCardID: UUID?
    @State private var activeCardDetailPresentation: CardDetailPresentation?
    @State private var isCardDetailDirty = false
    @State private var pendingCardDetailTransition: PendingCardDetailTransition?
    @State private var isPresentingCreateBoard = false

    /// E-01 export (⇧⌘E): the document is built on demand when Export is invoked, then the
    /// `.fileExporter` below drives the sandbox-friendly save panel.
    @State private var isPresentingExporter = false
    @State private var exportDocument: ExportJSONDocument?

    /// E-01 export e2e (test-only): the filename passed via `--export-to`, and the published
    /// self-check result. Nil for every normal launch (see `runExportSelfCheckIfNeeded`).
    private let exportToFilename: String?
    @State private var exportSelfCheck: String?

    /// E-02 import (⇧⌘I): file picked → decoded+sanitized envelope parks here until the user
    /// chooses a mode in the confirmation dialog.
    struct PendingImport: Identifiable {
        let id = UUID()
        let envelope: ExportEnvelope
        let filename: String
    }

    @State private var isPresentingImporter = false
    @State private var pendingImport: PendingImport?
    @State private var importError: ImportError?

    /// E-02 import e2e (test-only): `--import-from` filename, `--import-mode` override, the
    /// published outcome marker, and a one-shot guard (marker-independent: ask-mode publishes
    /// nothing until a dialog button is clicked, so the marker can't be the guard).
    private let importFromFilename: String?
    private let importModeOverride: String?
    @State private var importSelfCheck: String?
    @State private var importHookHasRun = false

    private enum PendingCardDetailTransition {
        case openCard(UUID)
        case selectBoard(UUID?)
        case setViewMode(BoardViewMode)
        case presentImporter
    }

    init(config: AppLaunchConfig) {
        _selectedBoardIDRaw = AppStorage(config.selectedBoardDefaultsKey)
        _viewModesRaw = AppStorage(config.viewModeDefaultsKey)
        _cardDetailPresentationRaw = AppStorage(
            wrappedValue: CardDetailPresentation.sheet.rawValue,
            config.cardDetailPresentationDefaultsKey
        )
        // Test-only affordance — honored ONLY under --uitest (mirrors how --appearance is gated
        // in TackApp.init), so a normal launch can never be made to write an export file.
        exportToFilename = config.isUITest ? config.exportTo : nil
        importFromFilename = config.isUITest ? config.importFrom : nil
        importModeOverride = config.isUITest ? config.importMode : nil
    }

    var body: some View {
        Group {
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

            // E-01 export e2e marker (present only under --export-to): publishes the app's own
            // write→read→decode self-check of the exported JSON for the test to assert (the runner
            // is sandboxed and can't read the app's container file directly).
            if let exportSelfCheck {
                Color.clear
                    .allowsHitTesting(false)
                    .accessibilityRepresentation {
                        Text(exportSelfCheck)
                            .accessibilityIdentifier(AccessibilityID.exportSelfCheck)
                    }
            }

            // E-02 import e2e marker (present only under --import-from): see AccessibilityID.
            if let importSelfCheck {
                Color.clear
                    .allowsHitTesting(false)
                    .accessibilityRepresentation {
                        Text(importSelfCheck)
                            .accessibilityIdentifier(AccessibilityID.importSelfCheck)
                    }
            }

            // M-C: view-mode marker (the boardThemeValue pattern — a detached SIBLING, never an
            // ancestor of queried children). Exposes the SELECTED board's mode as "board"/"list";
            // absent with no board selected. This is the UI tests' oracle for mode switches.
            if selectedBoard != nil {
                Color.clear
                    .allowsHitTesting(false)
                    .accessibilityRepresentation {
                        Text(selectedBoardViewMode.rawValue)
                            .accessibilityIdentifier(AccessibilityID.viewModeValue)
                    }
            }

            NavigationSplitView {
                SidebarView(selection: selectedBoardBinding, onDeleteBoard: deleteBoard)
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
                // M-C: the Board/List view-mode switcher. Present-but-disabled with no board
                // selected — the same HIG stable-toolbar-geometry rationale as the Theme button
                // below. Identifier on the Picker; segments carry LABELS only (see
                // AccessibilityID.viewModePicker).
                ToolbarItem(placement: .automatic) {
                    Picker("View Mode", selection: viewModeBinding) {
                        Image(systemName: "square.grid.3x1.below.line.grid.1x2")
                            .accessibilityLabel("Board")
                            .tag(BoardViewMode.board)
                        Image(systemName: "list.bullet")
                            .accessibilityLabel("List")
                            .tag(BoardViewMode.list)
                        Image(systemName: "calendar")
                            .accessibilityLabel("Calendar")
                            .tag(BoardViewMode.calendar)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .help("Show the selected board as columns, a due-date list, or a month calendar")
                    .disabled(selectedBoard == nil)
                    .accessibilityIdentifier(AccessibilityID.viewModePicker)
                }
                // M8: the per-board Theme button (its popover lives inside `ThemeButton`).
                // Contributed HERE, not from BoardView's own body, for the exact same
                // empirically-established reason as the "New Board" item below — parameterized
                // with whichever board `detailContent` is currently showing. Always PRESENT and
                // merely disabled with no board (HIG: stable toolbar geometry — the old
                // conditional made the '+' button jump as selection changed).
                ToolbarItem(placement: .automatic) {
                    ThemeButton(board: selectedBoard, store: store)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        isPresentingCreateBoard = true
                    } label: {
                        Label("New Board", systemImage: "plus")
                    }
                    .help("New board")
                    .accessibilityIdentifier(AccessibilityID.newBoardButton)
                }
            }
        }
        .onAppear(perform: restoreSelectionIfNeeded)
        .onAppear(perform: restoreViewModesIfNeeded)
        .onAppear(perform: wireUndoManager)
        .onAppear(perform: runExportSelfCheckIfNeeded)
        // Re-run once boards are first available (the @Query may populate after the initial appear).
        .onChange(of: boards.count) { _, _ in runExportSelfCheckIfNeeded() }
        .onAppear(perform: runImportSelfCheckIfNeeded)
        .onChange(of: undoManagerID) { _, _ in wireUndoManager() }
        .onChange(of: allCardIDs) { _, newIDs in
            guard let presentedCardID, !newIDs.contains(presentedCardID) else { return }
            closeCardDetail()
        }
        .onChange(of: selectedBoardID) { _, newValue in
            selectedBoardIDRaw = newValue?.uuidString
            autoExpandAreaIfNeeded(for: newValue)
        }
        .onChange(of: viewModes) { _, newValue in
            viewModesRaw = BoardViewMode.encode(newValue)
        }
        .sheet(isPresented: $isPresentingCreateBoard) {
            CreateBoardSheet(store: store) { created in
                requestBoardSelection(created.id)
            }
        }
        .sheet(isPresented: cardDetailSheetBinding) {
            cardDetailEditor(presentation: .sheet)
        }
        .inspector(isPresented: cardDetailInspectorBinding) {
            cardDetailEditor(presentation: .sidePanel)
                .inspectorColumnWidth(min: 340, ideal: 380, max: 520)
        }
        // E-01: the JSON export save panel. Hosted here (not in AppCommands — a `Commands` value
        // can't present a `.fileExporter`); the ⇧⌘E command flips `isPresentingExporter` after
        // building the document. `defaultFilename` gets the .json extension from `contentType`.
        .fileExporter(
            isPresented: $isPresentingExporter,
            document: exportDocument,
            contentType: .json,
            defaultFilename: ExportDocument.suggestedFilename()
        ) { _ in
            exportDocument = nil
        }
        // E-02: the JSON import open panel (hosted here for the same Commands-can't-present
        // reason as the exporter above).
        .fileImporter(
            isPresented: $isPresentingImporter,
            allowedContentTypes: [.json]
        ) { result in
            handlePickedImportFile(result)
        }
        // E-02: the mode chooser. Replace is omitted for a zero-board envelope (the one
        // total-data-loss vector); the store's .emptyReplace guard is the backstop.
        .confirmationDialog(
            importDialogTitle,
            isPresented: Binding(
                get: { pendingImport != nil },
                set: { if !$0 { pendingImport = nil } }
            ),
            titleVisibility: .visible,
            presenting: pendingImport
        ) { pending in
            Button("Add to Existing") { completeImport(pending, replacing: false) }
            if !pending.envelope.boards.isEmpty {
                Button("Replace All Boards", role: .destructive) { completeImport(pending, replacing: true) }
            }
            Button("Cancel", role: .cancel) { cancelImport() }
            } message: { pending in
                Text(importDialogMessage(pending))
            }
        }
        // E-02: the app's first user-facing error alert. Every error reaching here is an
        // ImportError (the store wraps save failures), so the copy is always specific and always
        // ends in the atomicity guarantee.
        .alert(
            "Import Failed",
            isPresented: Binding(
                get: { importError != nil },
                set: { if !$0 { importError = nil } }
            ),
            presenting: importError
        ) { _ in
            Button("OK", role: .cancel) { importError = nil }
        } message: { error in
            Text([error.errorDescription, error.recoverySuggestion].compactMap { $0 }.joined(separator: "\n\n"))
        }
        .confirmationDialog(
            "Discard Changes?",
            isPresented: isPresentingCardDetailTransitionDialog,
            titleVisibility: .visible
        ) {
            Button("Discard Changes", role: .destructive, action: discardAndPerformPendingTransition)
            Button("Keep Editing", role: .cancel) { pendingCardDetailTransition = nil }
        } message: {
            Text("This card has unsaved changes. Discard them to continue, or keep editing the current card.")
        }
        .onExitCommand(perform: closeSidePanelFromExitCommand)
        // Always-present board-navigation command surface (New Board, ⌘1–⌘9, ⇧⌘E export) — see AppCommands.
        .focusedSceneValue(\.boardSelectionActions, boardSelectionActions)
    }

    // MARK: - Command surface

    private var sortedBoards: [Board] { boards.sorted { $0.position < $1.position } }

    /// The board currently shown in the detail pane (nil when none selected/matched) — shared by
    /// `detailContent` and the toolbar's Theme button so both agree on exactly which board is on
    /// screen.
    private var selectedBoard: Board? {
        guard let selectedBoardID else { return nil }
        return boards.first(where: { $0.id == selectedBoardID })
    }

    /// Every card currently reachable from the live board query. Root stores only a UUID so a
    /// deleted SwiftData object is never retained by presentation state.
    private var allCards: [Card] {
        boards.flatMap { $0.sortedLists }.flatMap { $0.sortedCards }
    }

    private var allCardIDs: Set<UUID> { Set(allCards.map(\.id)) }

    private var presentedCard: Card? {
        guard let presentedCardID else { return nil }
        return allCards.first(where: { $0.id == presentedCardID })
    }

    private var preferredCardDetailPresentation: CardDetailPresentation {
        CardDetailPresentation(storedValue: cardDetailPresentationRaw)
    }

    private var isCardDetailSheetPresented: Bool {
        activeCardDetailPresentation == .sheet && presentedCard != nil
    }

    private var selectedBoardBinding: Binding<UUID?> {
        Binding(get: { selectedBoardID }, set: requestBoardSelection)
    }

    private var cardDetailSheetBinding: Binding<Bool> {
        Binding(
            get: { isCardDetailSheetPresented },
            set: { if !$0 { closeCardDetail() } }
        )
    }

    private var cardDetailInspectorBinding: Binding<Bool> {
        Binding(
            get: { activeCardDetailPresentation == .sidePanel && presentedCard != nil },
            set: { if !$0 { closeCardDetail() } }
        )
    }

    /// The selected board's mode; `.board` when unset, so every existing board keeps its
    /// current look until the user opts in per board.
    private var selectedBoardViewMode: BoardViewMode {
        guard let selectedBoardID else { return .board }
        return viewModes[selectedBoardID] ?? .board
    }

    /// Shared write path for the toolbar switcher and the View-menu items. No-op with no
    /// selection (the menu gate allows enabled-with-no-selection edge states; this is the
    /// backstop).
    private func setViewMode(_ mode: BoardViewMode) {
        guard selectedBoardID != nil, mode != selectedBoardViewMode else { return }
        requestCardDetailTransition(.setViewMode(mode))
    }

    private func applyViewMode(_ mode: BoardViewMode) {
        guard let selectedBoardID else { return }
        viewModes[selectedBoardID] = mode
    }

    private var viewModeBinding: Binding<BoardViewMode> {
        Binding(get: { selectedBoardViewMode }, set: { setViewMode($0) })
    }

    /// Seeds the live map from the persisted string on first appearance (the
    /// `restoreSelectionIfNeeded` pattern). Guarded so a later `.onAppear` never clobbers modes
    /// set this session; re-decoding an empty map is a harmless no-op.
    private func restoreViewModesIfNeeded() {
        guard viewModes.isEmpty else { return }
        viewModes = BoardViewMode.decode(viewModesRaw)
    }

    private var boardSelectionActions: BoardSelectionActions {
        BoardSelectionActions(
            newBoard: { isPresentingCreateBoard = true },
            selectBoard: { position in
                let ordered = sortedBoards
                guard position >= 1, position <= ordered.count else { return }
                requestBoardSelection(ordered[position - 1].id)
            },
            boardNames: sortedBoards.map(\.name),
            exportAllBoards: presentExporter,
            importBoards: requestImporter,
            setViewMode: setViewMode
        )
    }

    // MARK: - Card detail presentation

    /// All entry points (board/list/calendar double-click, context menu, and ⌘O) converge here.
    /// Reopening the already-presented card is a no-op so it can never reset a staged draft.
    private func openCardDetail(_ card: Card) {
        guard presentedCardID != card.id else { return }
        requestCardDetailTransition(.openCard(card.id))
    }

    private func requestBoardSelection(_ boardID: UUID?) {
        guard boardID != selectedBoardID else { return }
        requestCardDetailTransition(.selectBoard(boardID))
    }

    /// Import can replace the complete board graph. A dirty inspector requires an explicit
    /// discard before the file workflow begins, so a later atomic-save failure can never be the
    /// event that silently loses its draft. A clean editor stays open until the chosen import
    /// mode actually changes its context.
    private func requestImporter() {
        if presentedCardID != nil, isCardDetailDirty {
            pendingCardDetailTransition = .presentImporter
        } else {
            isPresentingImporter = true
        }
    }

    /// Dirty drafts guard only genuine context changes. Explicit Cancel/Esc/Delete continue to
    /// close immediately because those controls already communicate their discard semantics.
    private func requestCardDetailTransition(_ transition: PendingCardDetailTransition) {
        if presentedCardID != nil, isCardDetailDirty {
            pendingCardDetailTransition = transition
        } else {
            performCardDetailTransition(transition)
        }
    }

    private var isPresentingCardDetailTransitionDialog: Binding<Bool> {
        Binding(
            get: { pendingCardDetailTransition != nil },
            set: { if !$0 { pendingCardDetailTransition = nil } }
        )
    }

    private func discardAndPerformPendingTransition() {
        guard let transition = pendingCardDetailTransition else { return }
        pendingCardDetailTransition = nil
        performCardDetailTransition(transition)
    }

    private func performCardDetailTransition(_ transition: PendingCardDetailTransition) {
        switch transition {
        case .openCard(let cardID):
            guard allCardIDs.contains(cardID) else { return }
            // Snapshot Settings NOW. Changing Settings during this presentation cannot move it;
            // explicitly opening another card is the next open and consults the latest choice.
            presentedCardID = cardID
            activeCardDetailPresentation = preferredCardDetailPresentation
            isCardDetailDirty = false
        case .selectBoard(let boardID):
            closeCardDetail()
            selectedBoardID = boardID
        case .setViewMode(let mode):
            closeCardDetail()
            applyViewMode(mode)
        case .presentImporter:
            closeCardDetail()
            isPresentingImporter = true
        }
    }

    private func closeCardDetail() {
        presentedCardID = nil
        activeCardDetailPresentation = nil
        isCardDetailDirty = false
        pendingCardDetailTransition = nil
    }

    /// Esc remains a presentation-level Cancel even after keyboard focus has returned to the
    /// nonmodal board/list/calendar surface. Modal sheets handle Esc inside their own key window.
    private func closeSidePanelFromExitCommand() {
        guard activeCardDetailPresentation == .sidePanel else { return }
        closeCardDetail()
    }

    /// Editor identity is pinned to the card UUID so swapping cards always seeds fresh staged
    /// state. Every close/delete callback clears Root's ID before any model destruction.
    @ViewBuilder
    private func cardDetailEditor(presentation: CardDetailPresentation) -> some View {
        if let card = presentedCard {
            CardDetailView(
                card: card,
                store: store,
                presentation: presentation,
                onDelete: { deleteCard(card) },
                onClose: closeCardDetail,
                onDirtyChange: { dirty in
                    guard presentedCardID == card.id else { return }
                    isCardDetailDirty = dirty
                }
            )
            .id(card.id)
        }
    }

    private func deleteCard(_ card: Card) {
        if presentedCardID == card.id {
            closeCardDetail()
        }
        store.deleteCard(card)
    }

    private func deleteList(_ list: BoardList) {
        if presentedCard?.list?.id == list.id {
            closeCardDetail()
        }
        store.deleteList(list)
    }

    private func deleteBoard(_ board: Board) {
        if board.sortedLists.flatMap({ $0.sortedCards }).contains(where: { $0.id == presentedCardID }) {
            closeCardDetail()
        }
        store.deleteBoard(board)
    }

    /// E-01 export e2e self-check (test-only, `--export-to <file>`): encodes every board through
    /// the production `ExportDocument` path, WRITES the JSON to the sandbox `UITest/` dir, READS it
    /// back, DECODES it, and publishes a `"<board names>|<To Do card titles>"` summary via a hidden
    /// AX marker. Proves the full encode→disk→decode round trip end-to-end in the running app; the
    /// e2e asserts the published summary against the fixture (the runner can't read the app's
    /// sandbox file directly). Runs once, only when the flag is set and boards exist.
    private func runExportSelfCheckIfNeeded() {
        guard let filename = exportToFilename, exportSelfCheck == nil else { return }
        let boards = sortedBoards
        guard !boards.isEmpty,
              let data = try? ExportDocument.encode(ExportDocument.makeEnvelope(boards: boards, areas: Array(areas))),
              let directory = try? ModelContainerFactory.uiTestDirectory() else { return }
        let url = directory.appendingPathComponent(filename)
        try? data.write(to: url)
        guard let readBack = try? Data(contentsOf: url),
              let decoded = try? ExportDocument.decode(readBack) else { return }
        let names = decoded.boards.map(\.name).joined(separator: ",")
        let firstListCards = decoded.boards.first?.lists.first?.cards.map(\.title).joined(separator: ",") ?? ""
        exportSelfCheck = "\(names)|\(firstListCards)"
    }

    /// Builds the export document from every board (position order) and presents the save panel.
    /// No-op with no boards — the command is disabled in that case, but guard anyway.
    private func presentExporter() {
        let ordered = sortedBoards
        guard !ordered.isEmpty,
              let data = try? ExportDocument.encode(ExportDocument.makeEnvelope(boards: ordered, areas: Array(areas))) else { return }
        exportDocument = ExportJSONDocument(data: data)
        isPresentingExporter = true
    }

    // MARK: - Import (E-02)

    /// Reads and decodes the picked file. Security-scoped access: call `start` unconditionally
    /// and gate ONLY the paired `stop` on its Bool — it returns false for URLs already covered by
    /// the user-selected entitlement grant, so gating the READ on it would break legitimate
    /// imports. The decoded envelope is parked in `pendingImport` on the NEXT main-queue tick:
    /// flipping a confirmationDialog on in the same tick the fileImporter dismisses can silently
    /// fail to present (with the hop, the dialog presented promptly in the 2026-07-08 manual gate —
    /// see the spec's Manual-gate outcome; the error alert below hops for the same reason).
    private func handlePickedImportFile(_ result: Result<URL, Error>) {
        // A genuine panel `.failure` (rare — e.g. a permissions error surfaced by the panel
        // itself) is deliberately silent here alongside a plain cancel; if that's ever revisited,
        // it would need its own alert, since today only the read/decode/save paths below present one.
        guard case .success(let url) = result else { return }
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        do {
            let data: Data
            do {
                data = try Data(contentsOf: url)
            } catch {
                throw ImportError.unreadable(detail: error.localizedDescription)
            }
            let envelope = try ExportDocument.decodeForImport(data)
            let filename = url.lastPathComponent
            DispatchQueue.main.async {
                pendingImport = PendingImport(envelope: envelope, filename: filename)
            }
        } catch let error as ImportError {
            // Same presentation-timing hazard class as the dialog above: flipping the alert's
            // isPresented same-tick with the fileImporter's dismissal can silently fail to
            // present, so the error is parked on the next main-queue tick too.
            DispatchQueue.main.async {
                importError = error
            }
        } catch {
            DispatchQueue.main.async {
                importError = .unreadable(detail: error.localizedDescription)
            }
        }
    }

    private var importDialogTitle: String {
        let count = pendingImport?.envelope.boards.count ?? 0
        return "Import \(count) \(count == 1 ? "Board" : "Boards")"
    }

    private func importDialogMessage(_ pending: PendingImport) -> String {
        let importedBoards = pending.envelope.boards
        guard !importedBoards.isEmpty else {
            return "“\(pending.filename)” contains no boards, so adding it changes nothing — and it can't replace your existing boards."
        }
        let listCount = importedBoards.reduce(0) { $0 + $1.lists.count }
        let cardCount = importedBoards.reduce(0) { $0 + $1.lists.reduce(0) { $0 + $1.cards.count } }
        return "“\(pending.filename)” contains \(counted(importedBoards.count, "board")) (\(counted(listCount, "list")), \(counted(cardCount, "card"))). "
            + "“Add to Existing” keeps your current \(counted(boards.count, "board")) and adds the imported ones after them. "
            + "“Replace All Boards” deletes your current boards first — replacing cannot be undone."
    }

    /// "1 board" / "3 boards" — Apple style avoids the "(s)" shorthand, and this message sits
    /// directly under a title that already pluralizes properly.
    private func counted(_ count: Int, _ noun: String) -> String {
        "\(count) \(noun)\(count == 1 ? "" : "s")"
    }

    /// Shared completion for the dialog buttons AND the --import-from test hook, so both paths
    /// get identical store routing, post-import selection, and (test-only) marker publication.
    private func completeImport(_ pending: PendingImport, replacing: Bool) {
        pendingImport = nil
        do {
            // Replace destroys the complete board graph. Clear any presented card ID first so
            // SwiftUI can never re-evaluate an editor against a deleted SwiftData object.
            if replacing {
                closeCardDetail()
            }
            let imported = replacing
                ? try store.replaceAllBoards(with: pending.envelope)
                : try store.importBoards(pending.envelope)
            if let first = imported.first {
                requestBoardSelection(first.id)
            }
            publishImportMarker(importSuccessSummary())
        } catch let error as ImportError {
            importError = error
            publishImportMarker("error|\(error.caseName)")
        } catch {
            let wrapped = ImportError.saveFailed(detail: error.localizedDescription)
            importError = wrapped
            publishImportMarker("error|\(wrapped.caseName)")
        }
    }

    private func cancelImport() {
        pendingImport = nil
        publishImportMarker("cancelled")
    }

    /// E-02 import e2e self-check (test-only, `--import-from <file>` + `--import-mode
    /// add|replace|ask`). Reads the JSON from the sandbox UITest/ dir, decodes through the
    /// production path, then routes through the SAME completion the dialog buttons use
    /// (`completeImport` — identical store routing and post-import selection): `add`/`replace`
    /// import directly; `ask` parks the envelope in `pendingImport` so the REAL mode dialog
    /// presents and the test drives its buttons. Deliberately `.onAppear`-only — export's extra
    /// `.onChange(of: boards.count)` re-trigger exists because export reads the `@Query`; import
    /// reads the file and store directly.
    private func runImportSelfCheckIfNeeded() {
        guard let filename = importFromFilename, !importHookHasRun else { return }
        importHookHasRun = true
        do {
            let directory = try ModelContainerFactory.uiTestDirectory()
            let url = directory.appendingPathComponent(filename)
            let data: Data
            do {
                data = try Data(contentsOf: url)
            } catch {
                throw ImportError.unreadable(detail: error.localizedDescription)
            }
            let envelope = try ExportDocument.decodeForImport(data)
            let pending = PendingImport(envelope: envelope, filename: filename)
            switch importModeOverride {
            case "ask":
                DispatchQueue.main.async { pendingImport = pending }
            case "replace":
                completeImport(pending, replacing: true)
            default:   // nil or "add"
                completeImport(pending, replacing: false)
            }
        } catch let error as ImportError {
            importError = error
            publishImportMarker("error|\(error.caseName)")
        } catch {
            let wrapped = ImportError.unreadable(detail: error.localizedDescription)
            importError = wrapped
            publishImportMarker("error|\(wrapped.caseName)")
        }
    }

    /// No-op for every normal launch (nil hook filename) — production imports never publish.
    private func publishImportMarker(_ value: String) {
        guard importFromFilename != nil else { return }
        importSelfCheck = value
    }

    /// "ok|<names>|<titles>" computed from LIVE post-import store state via a direct fetch (the
    /// @Query can lag a tick behind the store call; reading the context is fine — the
    /// views-never-WRITE invariant is untouched).
    private func importSuccessSummary() -> String {
        let descriptor = FetchDescriptor<Board>(sortBy: [SortDescriptor(\.position)])
        let all = (try? modelContext.fetch(descriptor)) ?? []
        let names = all.map(\.name).joined(separator: ",")
        let titles = all.first?.sortedLists.first?.sortedCards.map(\.title).joined(separator: ",") ?? ""
        return "ok|\(names)|\(titles)"
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
            EmptyStateView(onCreateBoard: { isPresentingCreateBoard = true },
                           onImportBoards: { isPresentingImporter = true })
                .navigationTitle("Tack")
        } else if let selectedBoard {
            // M-C/M-D: the view-mode seam. The views are different TYPES in this switch, so
            // switching modes tears down the old view's @State (board-local selection, filter
            // bar, month anchor) — accepted and honest: a mode switch is a context switch.
            switch selectedBoardViewMode {
            case .list:
                ListBoardView(
                    board: selectedBoard,
                    store: store,
                    isCardDetailSheetPresented: isCardDetailSheetPresented,
                    onOpenCard: openCardDetail,
                    onDeleteCard: deleteCard
                )
            case .calendar:
                CalendarBoardView(
                    board: selectedBoard,
                    store: store,
                    isCardDetailSheetPresented: isCardDetailSheetPresented,
                    onOpenCard: openCardDetail,
                    onDeleteCard: deleteCard
                )
            case .board:
                BoardView(
                    board: selectedBoard,
                    store: store,
                    isCardDetailSheetPresented: isCardDetailSheetPresented,
                    onOpenCard: openCardDetail,
                    onDeleteCard: deleteCard,
                    onDeleteList: deleteList,
                    onExitCardDetail: closeSidePanelFromExitCommand
                )
            }
        } else {
            // Same native empty-state dressing as the zero-boards state next door — a bare
            // secondary string beside a fully-dressed sibling read as unfinished.
            ContentUnavailableView(
                "No Board Selected",
                systemImage: "square.grid.2x2",
                description: Text("Choose a board in the sidebar.")
            )
            .navigationTitle("Tack")
        }
    }

    /// Restores the persisted selection on first appearance. Guarded so a later `.onAppear`
    /// (e.g. after a sheet dismiss) doesn't clobber a selection the user already made.
    private func restoreSelectionIfNeeded() {
        guard selectedBoardID == nil else { return }
        let savedID = selectedBoardIDRaw.flatMap(UUID.init(uuidString:))
        selectedBoardID = SelectionRestore.resolve(savedID: savedID, boards: boards)?.id
    }

    /// M-F design (c): selecting or restoring a board whose area is collapsed auto-expands that
    /// area, so the sidebar highlight is never hidden. ONE site covers every selection path —
    /// restore-at-launch, ⌘1–⌘9, NextBoardSelection after a delete, post-import selection, and
    /// create. Routed through the store (an honest "Expand Area" undo step when it fires;
    /// setAreaCollapsed's no-op guard makes every other selection change free).
    private func autoExpandAreaIfNeeded(for boardID: UUID?) {
        guard let boardID,
              let area = boards.first(where: { $0.id == boardID })?.area,
              area.isCollapsed else { return }
        store.setAreaCollapsed(area, false)
    }
}
