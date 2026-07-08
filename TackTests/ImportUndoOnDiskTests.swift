import Testing
import Foundation
import SwiftData
@testable import Tack

/// E-02 on-disk smoke — the reduced form of the plan's spike suite. THE SPIKE GATE ALREADY
/// RESOLVED (FAIL) IN-MEMORY during Task 1: SwiftData's automatic undo registration
/// deterministically dropped every 3rd-level Card insert on redo of the import group, so append
/// import ships NON-undoable via the deleteBoard detach pattern (see the spec's "Spike outcome
/// (2026-07-08)" block in docs/superpowers/specs/2026-07-08-json-import-design.md).
///
/// What this suite still pins, on a REAL sqlite store (the environment in-memory tests provably
/// cannot represent — see BoardStore.deleteBoard's evidence): importBoards materializes the full
/// graph, persists it, and the detach discipline completes without the on-disk assert class
/// (EXC_BREAKPOINT) or the NSUndoManager hang, leaving the manager reattached and the stack clear.
@MainActor
@Suite("Import on-disk smoke", .serialized)
struct ImportUndoOnDiskTests {

    /// On-disk equivalent of `TestContainer(withUndo: true)`: sqlite under a unique temp dir,
    /// UndoManager with `groupsByEvent = false` (headless — no run loop to open event groups).
    @MainActor
    private struct OnDiskStore {
        let directory: URL
        let container: ModelContainer
        let context: ModelContext
        let store: BoardStore
        let undoManager: UndoManager

        init() throws {
            directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("TackImportSmoke-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let schema = Schema(versionedSchema: TackSchemaV1.self)
            let configuration = ModelConfiguration(schema: schema, url: directory.appendingPathComponent("smoke.sqlite"))
            container = try ModelContainer(for: schema, migrationPlan: TackMigrationPlan.self,
                                           configurations: [configuration])
            context = container.mainContext
            let manager = UndoManager()
            manager.groupsByEvent = false
            context.undoManager = manager
            undoManager = manager
            store = BoardStore(context: context)
        }

        /// Best-effort: SwiftData's ModelContainer has no public close API and `env` outlives this
        /// deferred call, so the sqlite file is unlinked while the store is still open — macOS
        /// logs a harmless "vnode unlinked while in use" to stderr. Accepted: assertions have all
        /// run by then, and the temp dir is gone either way.
        func tearDown() {
            try? FileManager.default.removeItem(at: directory)
        }
    }

    @Test("on-disk import materializes, persists, and completes the detach discipline cleanly")
    func onDiskImportSmoke() throws {
        let env = try OnDiskStore()
        defer { env.tearDown() }
        env.store.ensureLabelsSeeded()
        env.store.createBoard(name: "Seeded", emoji: nil)

        let created = Date(timeIntervalSince1970: 1_750_000_000)
        let envelope = ExportEnvelope(
            formatVersion: 1,
            exportedAt: Date(timeIntervalSince1970: 1_781_827_200),
            boards: [
                ExportBoard(name: "Import One", emoji: "1️⃣", position: 0, themeName: "default",
                            customThemeHex: nil, createdAt: created, lists: [
                    ExportList(name: "L1", position: 0, isCollapsed: false, cards: [
                        ExportCard(title: "C1", details: "d", position: 0,
                                   dueDate: Date(timeIntervalSince1970: 1_781_740_800),
                                   includesTime: false, createdAt: created, updatedAt: created,
                                   labels: ["red", "green"]),
                    ]),
                    ExportList(name: "L2", position: 1, isCollapsed: true, cards: []),
                ]),
                ExportBoard(name: "Import Two", emoji: nil, position: 1, themeName: "ocean",
                            customThemeHex: nil, createdAt: created, lists: [
                    ExportList(name: "L3", position: 0, isCollapsed: false, cards: [
                        ExportCard(title: "C2", details: nil, position: 0, dueDate: nil,
                                   includesTime: false, createdAt: created, updatedAt: created,
                                   labels: ["blue"]),
                    ]),
                ]),
            ]
        )

        try env.store.importBoards(envelope)

        // Full graph materialized on the live context.
        let boards = try env.context.fetch(FetchDescriptor<Board>(sortBy: [SortDescriptor(\.position)]))
        #expect(boards.map(\.name) == ["Seeded", "Import One", "Import Two"])
        #expect(boards[1].sortedLists.map(\.name) == ["L1", "L2"])
        #expect(boards[1].sortedLists[0].sortedCards[0].title == "C1")
        #expect(Set(boards[1].sortedLists[0].sortedCards[0].labels.map(\.colorName)) == ["red", "green"])
        #expect(try env.context.fetch(FetchDescriptor<CardLabel>()).count == 8)

        // Detach discipline completed: manager reattached, stack clear, no assert/hang.
        #expect(env.context.undoManager === env.undoManager)
        #expect(env.undoManager.canUndo == false)
        #expect(env.undoManager.canRedo == false)

        // Persisted: a second context on the same on-disk container sees the saved rows.
        let fresh = ModelContext(env.container)
        #expect(try fresh.fetch(FetchDescriptor<Board>()).count == 3)
    }
}
