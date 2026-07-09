import Testing
import Foundation
import SwiftData
@testable import Tack

/// M-E SPIKE (Task 0) — the evidence that decides whether deleteCard/deleteList STAY undoable now
/// that they cascade through a third graph level (ChecklistItem). Two prior findings frame the
/// risk: the on-disk Board delete fatally asserts inside SwiftData's undo snapshotting
/// (BoardStore.deleteBoard's evidence block), and the import spike's redo silently dropped every
/// third-level Card insert of a multi-board graph (see ImportUndoOnDiskTests). Leg B here probes
/// the exact same depth one relationship over: list → cards → checklist items.
///
/// ORACLES: exact fetchCounts + exact text/isDone/position arrays + persistentModelID row
/// identity. NEVER ObjectIdentifier (instances refault across saves — the import spike's
/// ObjectIdentifier verdicts varied run-to-run) and never bare "didn't crash" (the known failure
/// mode is SILENT row loss, not a crash).
///
/// VERDICT PROTOCOL (the plan's Task 0): run this suite 3×. GREEN = all assertions, 3/3 runs →
/// deleteCard/deleteList keep withUndoGroup (Task 1a; this file stays verbatim as the regression
/// sentinel). RED = any crash / hang (>6 min) / failed assertion in any run → both adopt
/// deleteBoard's detach-and-clear discipline (Task 1b; this file is rewritten into the reduced
/// on-disk smoke form, exactly how ImportUndoOnDiskTests ships).
@MainActor
@Suite("Checklist cascade-undo on-disk spike", .serialized)
struct ChecklistUndoOnDiskTests {

    /// On-disk equivalent of `TestContainer(withUndo: true)` — copied verbatim from
    /// ImportUndoOnDiskTests.OnDiskStore (private there; deliberately duplicated, not promoted —
    /// two spike files, promotion can wait for a third user): sqlite under a unique temp dir,
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
                .appendingPathComponent("TackChecklistSpike-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let schema = Schema(versionedSchema: TackSchemaV1.self)
            let configuration = ModelConfiguration(schema: schema, url: directory.appendingPathComponent("spike.sqlite"))
            container = try ModelContainer(for: schema, migrationPlan: TackMigrationPlan.self,
                                           configurations: [configuration])
            context = container.mainContext
            let manager = UndoManager()
            manager.groupsByEvent = false
            context.undoManager = manager
            undoManager = manager
            store = BoardStore(context: context)
        }

        /// Best-effort (the ImportUndoOnDiskTests caveat verbatim): no public close API, so the
        /// sqlite file is unlinked while open — a harmless stderr line, assertions already ran.
        func tearDown() {
            try? FileManager.default.removeItem(at: directory)
        }
    }

    private static let itemTexts = ["Renew library card", "Gather books from car", "Pay late fee"]

    /// Board → 3 default lists → "Target" card (+ "Survivor" sibling) → 3 checklist items, saved,
    /// then the undo stack is CLEARED so the only group under test is the delete itself. Items are
    /// inserted directly (the FixtureSeeder.seedSpike precedent) — the staged store path
    /// (`applyCardEdits`' checklist parameter) doesn't exist until Task 1, and setup writes must
    /// not sit on the stack anyway.
    private func seed(_ env: OnDiskStore) throws -> (toDo: BoardList, target: Card) {
        env.store.ensureLabelsSeeded()
        let board = env.store.createBoard(name: "Spike", emoji: nil)
        let toDo = board.sortedLists[0]
        let target = env.store.addCard(to: toDo, title: "Target")
        _ = env.store.addCard(to: toDo, title: "Survivor")
        for (index, text) in Self.itemTexts.enumerated() {
            env.context.insert(ChecklistItem(text: text, isDone: index == 0, position: index, card: target))
        }
        try env.context.save()
        env.undoManager.removeAllActions()
        return (toDo, target)
    }

    /// The integrity oracle shared by both legs' "restored" checkpoints.
    private func assertTargetFullyRestored(_ env: OnDiskStore, in list: BoardList,
                                           expectedPersistentID: PersistentIdentifier) throws {
        #expect(try env.context.fetchCount(FetchDescriptor<Card>()) == 2)
        #expect(try env.context.fetchCount(FetchDescriptor<ChecklistItem>()) == 3,
                "the known failure mode is SILENT third-level row loss — count is the primary oracle")
        let restored = try #require(list.sortedCards.first { $0.title == "Target" })
        #expect(restored.persistentModelID == expectedPersistentID,
                "undo must restore the row, not fabricate a lookalike")
        let items = restored.sortedChecklistItems
        #expect(items.map(\.text) == Self.itemTexts)
        #expect(items.map(\.isDone) == [true, false, false])
        #expect(items.map(\.position) == [0, 1, 2])
    }

    @Test("leg A: deleteCard of a checklist-bearing card — undo → redo → undo, full third-level integrity")
    func deleteCardUndoRedoIntegrity() throws {
        let env = try OnDiskStore()
        defer { env.tearDown() }
        let (toDo, target) = try seed(env)
        let targetPersistentID = target.persistentModelID

        env.store.deleteCard(target)
        #expect(try env.context.fetchCount(FetchDescriptor<Card>()) == 1)
        #expect(try env.context.fetchCount(FetchDescriptor<ChecklistItem>()) == 0,
                "cascade must not leave orphaned checklist rows")
        #expect(toDo.sortedCards.map(\.title) == ["Survivor"], "survivors renumbered")

        // Undo: the risky transition — re-INSERT of the card plus its third-level items.
        env.undoManager.undo()
        try assertTargetFullyRestored(env, in: toDo, expectedPersistentID: targetPersistentID)

        // Redo: re-delete. Must be clean AND complete (no orphans, no crash).
        env.undoManager.redo()
        #expect(try env.context.fetchCount(FetchDescriptor<Card>()) == 1)
        #expect(try env.context.fetchCount(FetchDescriptor<ChecklistItem>()) == 0)

        // Undo again: the cycle must keep restoring the SAME rows indefinitely.
        env.undoManager.undo()
        try assertTargetFullyRestored(env, in: toDo, expectedPersistentID: targetPersistentID)
    }

    @Test("leg B: deleteList cascading through cards to items — undo → redo → undo (the import-spike depth)")
    func deleteListUndoRedoIntegrity() throws {
        let env = try OnDiskStore()
        defer { env.tearDown() }
        let (toDo, target) = try seed(env)
        let targetPersistentID = target.persistentModelID
        let listPersistentID = toDo.persistentModelID
        let board = try #require(toDo.board)

        env.store.deleteList(toDo)
        #expect(try env.context.fetchCount(FetchDescriptor<BoardList>()) == 2)
        #expect(try env.context.fetchCount(FetchDescriptor<Card>()) == 0)
        #expect(try env.context.fetchCount(FetchDescriptor<ChecklistItem>()) == 0)
        #expect(board.sortedLists.map(\.name) == ["In Progress", "Done"], "survivors renumbered")

        // Undo: a THREE-level re-insert (list → 2 cards → 3 items) — exactly the depth at which
        // the import spike silently lost rows.
        env.undoManager.undo()
        #expect(try env.context.fetchCount(FetchDescriptor<BoardList>()) == 3)
        let restoredList = try #require(board.sortedLists.first { $0.name == "To Do" })
        #expect(restoredList.persistentModelID == listPersistentID)
        #expect(board.sortedLists.map(\.name) == ["To Do", "In Progress", "Done"],
                "original list positions restored")
        try assertTargetFullyRestored(env, in: restoredList, expectedPersistentID: targetPersistentID)

        env.undoManager.redo()
        #expect(try env.context.fetchCount(FetchDescriptor<BoardList>()) == 2)
        #expect(try env.context.fetchCount(FetchDescriptor<Card>()) == 0)
        #expect(try env.context.fetchCount(FetchDescriptor<ChecklistItem>()) == 0)

        env.undoManager.undo()
        #expect(try env.context.fetchCount(FetchDescriptor<BoardList>()) == 3)
        let restoredAgain = try #require(board.sortedLists.first { $0.name == "To Do" })
        try assertTargetFullyRestored(env, in: restoredAgain, expectedPersistentID: targetPersistentID)
    }
}
