import Testing
import Foundation
import SwiftData
@testable import Tack

/// M-E on-disk smoke — the reduced form of the plan's spike suite. THE SPIKE GATE RESOLVED (RED)
/// ON-DISK during Task 0: both `deleteCard` and `deleteList`, run 3/3 times against a real sqlite
/// store, crashed immediately inside their own `withUndoGroup` — before `undo()` was ever called —
/// with `SwiftData/ModelSnapshot.swift:46: Fatal error: Unexpected backing data for snapshot
/// creation: SwiftData._FullFutureBackingData<Tack.ChecklistItem>` (leg A) / `<...Tack.Card>` or
/// `<...Tack.ChecklistItem>` (leg B) — the same crash class and file/line as `BoardStore.deleteBoard`'s
/// documented on-disk fatal assert, reproduced one cascade level shallower now that a card carries
/// checklist items. deleteCard/deleteList therefore ship NON-undoable via the deleteBoard detach
/// pattern (see the M-E plan's ledger block, `docs/superpowers/plans/2026-07-09-checklists.md`).
///
/// What this suite still pins, on a REAL sqlite store: both deletes cascade completely (no
/// orphaned checklist rows), renumber survivors, complete the detach discipline (manager
/// reattached, stack clear, no assert/hang), and persist — the ImportUndoOnDiskTests posture.
@MainActor
@Suite("Checklist cascade-delete on-disk smoke", .serialized)
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

    @Test("on-disk deleteCard: full cascade, survivors renumbered, detach discipline clean")
    func onDiskDeleteCardSmoke() throws {
        let env = try OnDiskStore()
        defer { env.tearDown() }
        let (toDo, target) = try seed(env)
        _ = env.store.addCard(to: toDo, title: "Tail") // a pre-delete group that must be CLEARED
        // Hold a real undoable group on the stack to prove the delete clears it.
        #expect(env.undoManager.canUndo == true)

        env.store.deleteCard(target)

        #expect(try env.context.fetchCount(FetchDescriptor<Card>()) == 2)
        #expect(try env.context.fetchCount(FetchDescriptor<ChecklistItem>()) == 0,
                "cascade must not leave orphaned checklist rows")
        #expect(toDo.sortedCards.map(\.title) == ["Survivor", "Tail"])
        #expect(toDo.sortedCards.map(\.position) == [0, 1], "survivors renumbered")
        // Detach discipline completed: manager reattached, stack clear, no assert/hang.
        #expect(env.context.undoManager === env.undoManager)
        #expect(env.undoManager.canUndo == false)
        #expect(env.undoManager.canRedo == false)
        // Persisted: a second context on the same container sees the post-delete truth.
        let fresh = ModelContext(env.container)
        #expect(try fresh.fetchCount(FetchDescriptor<ChecklistItem>()) == 0)
        #expect(try fresh.fetchCount(FetchDescriptor<Card>()) == 2)
    }

    @Test("on-disk deleteList: cascade through cards to items, detach discipline clean")
    func onDiskDeleteListSmoke() throws {
        let env = try OnDiskStore()
        defer { env.tearDown() }
        let (toDo, _) = try seed(env)
        let board = try #require(toDo.board)

        env.store.deleteList(toDo)

        #expect(try env.context.fetchCount(FetchDescriptor<BoardList>()) == 2)
        #expect(try env.context.fetchCount(FetchDescriptor<Card>()) == 0)
        #expect(try env.context.fetchCount(FetchDescriptor<ChecklistItem>()) == 0)
        #expect(board.sortedLists.map(\.name) == ["In Progress", "Done"])
        #expect(board.sortedLists.map(\.position) == [0, 1])
        #expect(env.context.undoManager === env.undoManager)
        #expect(env.undoManager.canUndo == false)
        #expect(env.undoManager.canRedo == false)
        let fresh = ModelContext(env.container)
        #expect(try fresh.fetchCount(FetchDescriptor<BoardList>()) == 2)
    }
}
