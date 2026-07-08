# JSON Import (Backup/Restore, E-02) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Import a previously exported Tack JSON backup — "Add to Existing" (append, one undoable ⌘Z step, spike-gated) or "Replace All Boards" (non-undoable) — with hard-reject validation for structural failures, quiet sanitization for the gray zone, and full unit + e2e coverage via an `--import-from` launch hook.

**Architecture:** Zero new app-target source files. The pure half (decode → version gate → sanitize) extends `ExportDocument`; the impure half (`importBoards`/`replaceAllBoards` + private `materialize`) extends `BoardStore` — its first throwing methods, single-save atomic with rollback. UI is the E-01 pattern mirrored: a scene-level menu command flips `RootView` state, `RootView` hosts `.fileImporter` → mode `confirmationDialog` → first `.alert`. e2e content coverage uses `--import-from`/`--import-mode` (the open panel is not automatable and the runner cannot place files in the sandbox — the app exports its own input first via `--export-to`).

**Tech Stack:** Swift / SwiftUI / SwiftData (macOS 14+), Swift Testing (unit), XCUITest (e2e), XcodeGen.

**Spec:** `docs/superpowers/specs/2026-07-08-json-import-design.md` — the authority for every behavior below.

## Global Constraints

- `Tack.xcodeproj` is **generated**: after creating any new source/test file, run `make gen` before building.
- Every bare `xcodebuild` needs `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` (the Makefile exports it for `make` targets).
- Run `xcodebuild` in the **foreground**; before any run: `pkill -f xcodebuild; pkill -f Tack.app`. A unit run past ~6 minutes is a **hang** (NSUndoManager registration outside a group), not a slow run — kill it and read the log tail for a FAULT line.
- Unit tests with undo use `TestContainer(withUndo: true)`; never rely on `groupsByEvent` in headless tests.
- `BoardStore` is the only mutation surface; views never write to `ModelContext` (reading is fine).
- `CardLabel` rows are never inserted by import — always fetched (unique `colorName`, palette invariant = exactly 8 rows).
- Commit message style: imperative subject + `(E-02)` suffix, matching recent history (e.g. `Add BoardStore.moveBoards — undoable board reorder with gap self-healing (B-06)`).
- Single-suite run template (used throughout; substitute the `-only-testing` value):

```sh
pkill -f xcodebuild; pkill -f Tack.app
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project Tack.xcodeproj -scheme Tack \
  -destination "platform=macOS,arch=$(uname -m)" -derivedDataPath .build/DerivedData \
  -only-testing:TackTests/BoardStoreImportTests test
```

---

### Task 1: `ImportError` + `BoardStore.importBoards` (append mode) + `materialize`

**Files:**
- Modify: `Tack/Export/ExportDocument.swift` (append `ImportError` at the end of the file)
- Modify: `Tack/Store/BoardStore.swift` (new `// MARK: - Import (E-02)` section, after the `// MARK: - Labels on cards` section)
- Create: `TackTests/BoardStoreImportTests.swift`

**Interfaces:**
- Consumes: existing `ExportEnvelope`/`ExportBoard`/`ExportList`/`ExportCard` DTOs, `Board`/`BoardList`/`Card`/`CardLabel` initializers, `TestContainer`.
- Produces (later tasks rely on these exact signatures):
  - `enum ImportError: Error, Equatable, LocalizedError` with cases `.unreadable(detail: String)`, `.unsupportedVersion(Int)`, `.emptyReplace`, `.saveFailed(detail: String)`; properties `errorDescription: String?`, `recoverySuggestion: String?`, `caseName: String`.
  - `@discardableResult func importBoards(_ envelope: ExportEnvelope, importedAt: Date = .now) throws -> [Board]` on `BoardStore`.

- [ ] **Step 1: Add `ImportError` to `Tack/Export/ExportDocument.swift`**

Append at the end of the file:

```swift
// MARK: - Import errors (E-02)

/// Every failure the import surface can produce — file-read/decode failures, the version gate, the
/// empty-replace guard, and save failures wrapped at the store boundary — so RootView's alert and
/// the e2e marker only ever handle `ImportError` (no generic-`Error` path exists).
enum ImportError: Error, Equatable, LocalizedError {
    /// File-read failure (missing/unreadable file — wrapped by the read step in both the
    /// fileImporter completion and the launch hook), malformed JSON, a missing required field, or
    /// an undecodable date (Foundation's `.iso8601` rejects fractional seconds).
    case unreadable(detail: String)
    /// `formatVersion != ExportDocument.formatVersion`.
    case unsupportedVersion(Int)
    /// Replace-all requested with a zero-board envelope. The mode dialog omits the Replace button
    /// for empty backups; this is the store-level backstop (and what the test hook publishes if a
    /// test forces the combination).
    case emptyReplace
    /// `context.save()` threw during import; wrapped after rollback — nothing was persisted.
    case saveFailed(detail: String)

    var errorDescription: String? {
        switch self {
        case .unreadable:
            return "This file couldn't be read as a Tack export. It may be damaged or not a Tack export file."
        case .unsupportedVersion(let version):
            return "This file uses export format version \(version). This version of Tack can only import version 1."
        case .emptyReplace:
            return "This backup contains no boards, so it can't replace your existing boards."
        case .saveFailed(let detail):
            return "Tack couldn't save the imported boards. \(detail)"
        }
    }

    /// Second alert line. Truthful because import is single-save atomic (rollback on failure).
    var recoverySuggestion: String? {
        "Nothing was imported. Your existing boards are unchanged."
    }

    /// Stable machine token for the e2e marker ("error|<caseName>") — never localized copy.
    var caseName: String {
        switch self {
        case .unreadable: "unreadable"
        case .unsupportedVersion: "unsupportedVersion"
        case .emptyReplace: "emptyReplace"
        case .saveFailed: "saveFailed"
        }
    }
}
```

- [ ] **Step 2: Write the failing tests — create `TackTests/BoardStoreImportTests.swift`**

```swift
import Testing
import Foundation
import SwiftData
@testable import Tack

/// E-02 store-level import: materialization, positions, label attachment, undo shape, atomicity.
/// In-memory (`TestContainer`) — the on-disk undo behavior is covered by `ImportUndoOnDiskTests`.
@MainActor
@Suite("BoardStore import")
struct BoardStoreImportTests {

    /// A fixed envelope exercising nesting, labels, due dates, collapse state, and DELIBERATELY
    /// scrambled DTO positions (99/7/5/3/2/0) — the materializer must ignore them all.
    private func sampleEnvelope() -> ExportEnvelope {
        let created = Date(timeIntervalSince1970: 1_750_000_000)
        return ExportEnvelope(
            formatVersion: 1,
            exportedAt: Date(timeIntervalSince1970: 1_781_827_200),
            boards: [
                ExportBoard(
                    name: "Imported A", emoji: "📦", position: 99, themeName: "ocean",
                    customThemeHex: "FF8800", createdAt: created,
                    lists: [
                        ExportList(name: "Alpha", position: 7, isCollapsed: true, cards: [
                            ExportCard(title: "A1", details: "first", position: 5,
                                       dueDate: Date(timeIntervalSince1970: 1_781_740_800),
                                       includesTime: false, createdAt: created, updatedAt: created,
                                       labels: ["red", "blue"]),
                            ExportCard(title: "A2", details: nil, position: 2, dueDate: nil,
                                       includesTime: false, createdAt: created, updatedAt: created,
                                       labels: []),
                        ]),
                        ExportList(name: "Beta", position: 3, isCollapsed: false, cards: []),
                    ]
                ),
                ExportBoard(name: "Imported B", emoji: nil, position: 0, themeName: "default",
                            customThemeHex: nil, createdAt: created, lists: []),
            ]
        )
    }

    private func fetchBoards(_ context: ModelContext) -> [Board] {
        (try? context.fetch(FetchDescriptor<Board>(sortBy: [SortDescriptor(\.position)]))) ?? []
    }

    private func fetchLabels(_ context: ModelContext) -> [CardLabel] {
        (try? context.fetch(FetchDescriptor<CardLabel>())) ?? []
    }

    @Test("append into an empty store materializes the exact graph")
    func appendIntoEmptyMaterializesGraph() throws {
        let env = TestContainer()
        defer { withExtendedLifetime(env) {} }
        env.store.ensureLabelsSeeded()

        let imported = try env.store.importBoards(sampleEnvelope(), importedAt: Date(timeIntervalSince1970: 1_781_827_200))

        let boards = fetchBoards(env.context)
        #expect(boards.map(\.name) == ["Imported A", "Imported B"])
        #expect(boards.map(\.position) == [0, 1])
        #expect(imported.map(\.name) == ["Imported A", "Imported B"], "return value matches envelope order")

        let boardA = boards[0]
        #expect(boardA.emoji == "📦")
        #expect(boardA.themeName == "ocean")
        #expect(boardA.customThemeHex == "FF8800")
        #expect(boardA.createdAt == Date(timeIntervalSince1970: 1_750_000_000))

        let lists = boardA.sortedLists
        #expect(lists.map(\.name) == ["Alpha", "Beta"])
        #expect(lists.map(\.position) == [0, 1], "list positions come from array order, not DTO values")
        #expect(lists[0].isCollapsed == true)
        #expect(lists[0].createdAt == Date(timeIntervalSince1970: 1_781_827_200),
                "BoardList.createdAt is synthesized from importedAt (absent from the format)")

        let cards = lists[0].sortedCards
        #expect(cards.map(\.title) == ["A1", "A2"])
        #expect(cards.map(\.position) == [0, 1], "card positions come from array order, not DTO values")
        #expect(cards[0].details == "first")
        #expect(cards[0].dueDate == Date(timeIntervalSince1970: 1_781_740_800))
        #expect(cards[0].includesTime == false)
    }

    @Test("appended boards get positions after the existing max; existing boards untouched")
    func appendAfterExistingMax() throws {
        let env = TestContainer()
        defer { withExtendedLifetime(env) {} }
        env.store.ensureLabelsSeeded()
        let existing1 = env.store.createBoard(name: "Existing 0", emoji: nil)
        let existing2 = env.store.createBoard(name: "Existing 1", emoji: nil)
        existing2.position = 5   // simulate a position gap (deleteBoard doesn't renumber)
        try env.context.save()

        try env.store.importBoards(sampleEnvelope())

        let boards = fetchBoards(env.context)
        #expect(boards.map(\.name) == ["Existing 0", "Existing 1", "Imported A", "Imported B"])
        #expect(boards.map(\.position) == [0, 5, 6, 7], "imported = (max 5) + 1, +2; existing untouched")
        #expect(existing1.name == "Existing 0")
    }

    @Test("labels attach to the fetched palette rows by identity; palette stays exactly 8")
    func labelsAttachByIdentity() throws {
        let env = TestContainer()
        defer { withExtendedLifetime(env) {} }
        env.store.ensureLabelsSeeded()
        let paletteIDs = Set(fetchLabels(env.context).map(ObjectIdentifier.init))
        #expect(paletteIDs.count == 8)

        try env.store.importBoards(sampleEnvelope())

        #expect(fetchLabels(env.context).count == 8, "import must never insert CardLabel rows")
        let cardA1 = fetchBoards(env.context)[0].sortedLists[0].sortedCards[0]
        #expect(Set(cardA1.labels.map(\.colorName)) == ["red", "blue"])
        #expect(Set(cardA1.labels.map(ObjectIdentifier.init)).isSubset(of: paletteIDs),
                "attached labels are the SAME palette row objects, not copies")
    }

    @Test("append is exactly one undo step: undo removes the whole import, redo restores it")
    func appendIsOneUndoStep() throws {
        let env = TestContainer(withUndo: true)
        defer { withExtendedLifetime(env) {} }
        env.store.ensureLabelsSeeded()
        env.store.createBoard(name: "Existing", emoji: nil)

        try env.store.importBoards(sampleEnvelope())
        #expect(fetchBoards(env.context).count == 3)

        env.undoManager!.undo()
        #expect(fetchBoards(env.context).map(\.name) == ["Existing"], "one ⌘Z removes the entire import")
        #expect(fetchLabels(env.context).count == 8, "palette untouched by undo (fetched, not inserted)")

        env.undoManager!.redo()
        #expect(fetchBoards(env.context).count == 3, "one redo restores the entire import")
        #expect(fetchBoards(env.context)[1].sortedLists[0].sortedCards[0].labels.count == 2,
                "label joins restored by redo")
    }

    @Test("empty-envelope append is a no-op that registers no undo step")
    func emptyEnvelopeAppendIsNoOp() throws {
        let env = TestContainer(withUndo: true)
        defer { withExtendedLifetime(env) {} }

        let empty = ExportEnvelope(formatVersion: 1, exportedAt: .now, boards: [])
        let imported = try env.store.importBoards(empty)

        #expect(imported.isEmpty)
        #expect(fetchBoards(env.context).isEmpty)
        #expect(env.undoManager!.canUndo == false, "no empty 'Import Boards' group on the stack")
    }

    @Test("undo action name is 'Import Boards'")
    func undoActionName() throws {
        let env = TestContainer(withUndo: true)
        defer { withExtendedLifetime(env) {} }
        env.store.ensureLabelsSeeded()
        try env.store.importBoards(sampleEnvelope())
        #expect(env.undoManager!.undoActionName == "Import Boards")
    }
}
```

- [ ] **Step 3: Run the suite to verify it fails to compile (`importBoards` doesn't exist)**

Run `make gen` first (new test file), then the single-suite command from Global Constraints with `-only-testing:TackTests/BoardStoreImportTests`.
Expected: **build FAILURE** — `value of type 'BoardStore' has no member 'importBoards'`.

- [ ] **Step 4: Implement `importBoards` + `materialize` in `Tack/Store/BoardStore.swift`**

Insert after the `// MARK: - Labels on cards` section (before `// MARK: - Position bookkeeping`):

```swift
    // MARK: - Import (E-02)

    /// Append-mode import: materializes every board in `envelope` AFTER the existing boards, as
    /// ONE undoable ⌘Z step ("Import Boards"). Single-save atomic: all inserts, then exactly one
    /// save; on save failure the context is rolled back and the error is wrapped as
    /// `ImportError.saveFailed` — nothing was persisted, existing boards are unchanged.
    ///
    /// Uses an inline, defer-closed undo bracket instead of `withUndoGroup` (whose body is
    /// non-throwing). The defer guarantees the group can never be left open on any exit path.
    /// Failure ordering (spec §2): detach → rollback → close group → reattach → clear stack →
    /// throw. The manager is detached BEFORE rollback so rollback's reverts can't register; the
    /// stack is cleared because the just-registered group references discarded objects (same
    /// rationale as `deleteBoard`'s clear).
    ///
    /// An empty envelope returns early — before opening the bracket, before any save — mirroring
    /// `moveBoards`' identity no-op, so an empty Add never eats a ⌘Z step.
    ///
    /// `envelope` is expected to be sanitized (`ExportDocument.decodeForImport`); `materialize`
    /// still guards unknown label names by skipping them. `importedAt` is injectable for
    /// deterministic tests; production passes `.now`.
    @discardableResult
    func importBoards(_ envelope: ExportEnvelope, importedAt: Date = .now) throws -> [Board] {
        guard !envelope.boards.isEmpty else { return [] }

        let held = context.undoManager
        var failed = false
        held?.beginUndoGrouping()
        held?.setActionName("Import Boards")
        defer {
            held?.endUndoGrouping()
            if context.undoManager !== held { context.undoManager = held }
            if failed { held?.removeAllActions() }
        }

        let basePosition = (fetchBoards().map(\.position).max() ?? -1) + 1
        let imported = materialize(envelope, basePosition: basePosition, importedAt: importedAt)
        do {
            try context.save()
        } catch {
            failed = true
            context.undoManager = nil   // detach BEFORE rollback so its reverts can't register
            context.rollback()
            throw ImportError.saveFailed(detail: error.localizedDescription)
        }
        return imported
    }

    /// Direct memberwise materialization of an import envelope. Fresh UUIDs (the format carries
    /// none); board positions `basePosition + arrayIndex`; list/card positions from array
    /// enumeration — DTO position fields are dead by construction (never read, so hand-edited
    /// duplicates/gaps can't corrupt ordering). `BoardList.createdAt` is synthesized from
    /// `importedAt` (absent from the format). Labels attach by FETCHING the existing unique
    /// palette rows into a dictionary and appending those rows — never inserting `CardLabel`
    /// (unique `colorName`; palette invariant = exactly 8 rows); a missing row is skipped, never
    /// created, mirroring `toggleLabel`'s guard. Deliberately NOT `createBoard` (which injects
    /// three default lists). Performs NO save — callers own the single-save transaction.
    private func materialize(_ envelope: ExportEnvelope, basePosition: Int, importedAt: Date) -> [Board] {
        let labelsByColorName = Dictionary(uniqueKeysWithValues: fetchLabels().map { ($0.colorName, $0) })
        return envelope.boards.enumerated().map { boardIndex, exportBoard in
            let board = Board(
                name: exportBoard.name,
                emoji: exportBoard.emoji,
                position: basePosition + boardIndex,
                themeName: exportBoard.themeName,
                customThemeHex: exportBoard.customThemeHex,
                createdAt: exportBoard.createdAt
            )
            context.insert(board)
            for (listIndex, exportList) in exportBoard.lists.enumerated() {
                let list = BoardList(
                    name: exportList.name,
                    position: listIndex,
                    isCollapsed: exportList.isCollapsed,
                    createdAt: importedAt,
                    board: board
                )
                context.insert(list)
                for (cardIndex, exportCard) in exportList.cards.enumerated() {
                    let card = Card(
                        title: exportCard.title,
                        details: exportCard.details,
                        position: cardIndex,
                        dueDate: exportCard.dueDate,
                        includesTime: exportCard.includesTime,
                        createdAt: exportCard.createdAt,
                        updatedAt: exportCard.updatedAt,
                        list: list,
                        labels: exportCard.labels.compactMap { labelsByColorName[$0] }
                    )
                    context.insert(card)
                }
            }
            return board
        }
    }
```

- [ ] **Step 5: Run the suite to verify it passes**

Same command as Step 3. Expected: **all 6 tests PASS**.

- [ ] **Step 6: Run the full unit suite to catch regressions**

Run: `make unit`
Expected: PASS (no existing test touches the new code, but the store file changed).

- [ ] **Step 7: Commit**

```bash
git add Tack/Export/ExportDocument.swift Tack/Store/BoardStore.swift TackTests/BoardStoreImportTests.swift
git commit -m "Add BoardStore.importBoards — append-mode JSON import as one undo step (E-02)"
```

---

### Task 2: The on-disk undo spike (`ImportUndoOnDiskTests`) — decision gate

**Files:**
- Create: `TackTests/ImportUndoOnDiskTests.swift`
- Possibly modify (only if the spike FAILS): `Tack/Store/BoardStore.swift`, `docs/superpowers/specs/2026-07-08-json-import-design.md`

**Interfaces:**
- Consumes: `BoardStore.importBoards(_:importedAt:)` from Task 1; `TackSchemaV1`/`TackMigrationPlan` (see `ModelContainerFactory`).
- Produces: the go/no-go decision on the append-undo contract. **Every later task assumes PASS**; on FAIL, apply the fallback in Step 5 and adjust as documented there.

- [ ] **Step 1: Create `TackTests/ImportUndoOnDiskTests.swift`**

```swift
import Testing
import Foundation
import SwiftData
@testable import Tack

/// THE E-02 SPIKE (spec: "Testing — Spike first"), kept afterwards as the permanent on-disk undo
/// regression. In-memory stores provably cannot reproduce the on-disk Board-delete assert (see
/// `BoardStore.deleteBoard`'s evidence), so these tests run against a REAL sqlite store in a temp
/// directory. Undoing an import deletes freshly inserted Boards on disk via the undo machinery —
/// adjacent to (but a different code path from) the known deleteBoard EXC_BREAKPOINT.
///
/// FAILURE SIGNATURES (run this suite ISOLATED, in the foreground):
///   - a run past ~6 minutes = the documented NSUndoManager hang;
///   - EXC_BREAKPOINT = the SwiftData fatal assert;
///   - wrong state after redo = SILENT CORRUPTION — counts as spike failure too (the moveCard
///     broken-redo precedent proves crash-free redo can still corrupt).
/// TRIAGE BEFORE ENACTING THE FALLBACK: a FAULT from a registration OUTSIDE the import group
/// (e.g. during the explicit-bracket save in the second test) is a headless-config artifact —
/// rework the test, not the feature. A fault inside importBoards' own group / undo / redo is
/// genuine → enact the spec's fallback (non-undoable append, detach pattern).
@MainActor
@Suite("Import undo on disk", .serialized)
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
                .appendingPathComponent("TackImportSpike-\(UUID().uuidString)", isDirectory: true)
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

        func tearDown() {
            try? FileManager.default.removeItem(at: directory)
        }
    }

    private func envelope() -> ExportEnvelope {
        let created = Date(timeIntervalSince1970: 1_750_000_000)
        return ExportEnvelope(
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
    }

    private func boards(_ context: ModelContext) -> [Board] {
        (try? context.fetch(FetchDescriptor<Board>(sortBy: [SortDescriptor(\.position)]))) ?? []
    }

    private func labels(_ context: ModelContext) -> [CardLabel] {
        (try? context.fetch(FetchDescriptor<CardLabel>())) ?? []
    }

    @Test("undo/redo fidelity: undo returns to the seeded state, redo restores the full graph")
    func undoRedoFidelityOnDisk() throws {
        let env = try OnDiskStore()
        defer { env.tearDown() }
        env.store.ensureLabelsSeeded()
        env.store.createBoard(name: "Seeded", emoji: nil)   // pre-existing data — a seeded store
        let paletteIDs = Set(labels(env.context).map(ObjectIdentifier.init))

        try env.store.importBoards(envelope())
        #expect(boards(env.context).map(\.name) == ["Seeded", "Import One", "Import Two"])

        env.undoManager.undo()
        #expect(boards(env.context).map(\.name) == ["Seeded"], "undo removes exactly the import")
        #expect(labels(env.context).count == 8, "palette survives undo")

        env.undoManager.redo()
        let after = boards(env.context)
        #expect(after.map(\.name) == ["Seeded", "Import One", "Import Two"],
                "SILENT WRONG STATE HERE = SPIKE FAILURE (moveCard broken-redo precedent)")
        let c1 = after[1].sortedLists[0].sortedCards[0]
        #expect(Set(c1.labels.map(\.colorName)) == ["red", "green"],
                "Card↔label many-to-many re-attached by redo")
        #expect(Set(c1.labels.map(ObjectIdentifier.init)).isSubset(of: paletteIDs),
                "redo re-attaches the SAME palette rows")
        #expect(labels(env.context).count == 8)

        env.undoManager.undo()
        #expect(boards(env.context).map(\.name) == ["Seeded"], "second undo cycle still clean")
    }

    @Test("committing the undone state to disk: save after undo persists only the seeded boards")
    func undoneImportCommitsOnDisk() throws {
        let env = try OnDiskStore()
        defer { env.tearDown() }
        env.store.ensureLabelsSeeded()
        env.store.createBoard(name: "Seeded", emoji: nil)

        try env.store.importBoards(envelope())
        env.undoManager.undo()

        // THE assert-adjacent moment: committing the undo-driven cascade delete of on-disk Boards.
        // The save is wrapped in an explicit undo group so any SwiftData save-time registration
        // lands inside a group instead of throwing at grouping level 0 (the documented headless
        // hang — a failure HERE is a harness artifact per the triage note above, not the feature).
        env.undoManager.beginUndoGrouping()
        try env.context.save()
        env.undoManager.endUndoGrouping()

        #expect(boards(env.context).map(\.name) == ["Seeded"], "only seeded boards persist")
        #expect(labels(env.context).count == 8)
        // No redo assertion: a post-undo save may legitimately invalidate redo (standard
        // NSUndoManager behavior, not corruption).
    }
}
```

- [ ] **Step 2: `make gen`, then run the spike ISOLATED in the foreground**

```sh
make gen
pkill -f xcodebuild; pkill -f Tack.app
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project Tack.xcodeproj -scheme Tack \
  -destination "platform=macOS,arch=$(uname -m)" -derivedDataPath .build/DerivedData \
  -only-testing:TackTests/ImportUndoOnDiskTests test
```

Expected: **PASS in well under 6 minutes.** Watch for the failure signatures in the suite doc comment.

- [ ] **Step 3 (PASS path): Record the spike outcome in the spec**

Edit `docs/superpowers/specs/2026-07-08-json-import-design.md` — append to the end of the "Spike first" paragraph block in **Testing**:

```markdown
**Spike outcome (2026-07-XX):** PASS — both tests green on-disk in <N>s; multi-board-graph undo,
redo (including Card↔label re-attachment by identity), and the post-undo save all behaved. The
append-mode import ships as one undoable ⌘Z step; `ImportUndoOnDiskTests` stays as the permanent
on-disk regression. Real-app ⌘Z verification (the M7 headless/app divergence guard) happens in the
manual ship-gate step.
```

(Fill in the real date/duration. **Skip Step 5.**)

- [ ] **Step 4: Commit**

```bash
git add TackTests/ImportUndoOnDiskTests.swift docs/superpowers/specs/2026-07-08-json-import-design.md
git commit -m "Add ImportUndoOnDiskTests — on-disk multi-board import undo spike passes (E-02)"
```

- [ ] **Step 5 (FAIL path only): Enact the spec's fallback**

Only if Step 2 genuinely failed (per the triage note — a fault *inside* the import group/undo/redo, not the bracket-save artifact):

1. Replace `importBoards`' undo bracket with the `deleteBoard` detach pattern — the body becomes:

```swift
    @discardableResult
    func importBoards(_ envelope: ExportEnvelope, importedAt: Date = .now) throws -> [Board] {
        guard !envelope.boards.isEmpty else { return [] }
        // SPIKE FAILED (see ImportUndoOnDiskTests + spec Testing outcome): multi-board-graph undo
        // is unsafe on-disk. Import is NOT undoable — deleteBoard's detach discipline.
        let held = context.undoManager
        context.undoManager = nil
        defer {
            context.undoManager = held
            held?.removeAllActions()
        }
        let basePosition = (fetchBoards().map(\.position).max() ?? -1) + 1
        let imported = materialize(envelope, basePosition: basePosition, importedAt: importedAt)
        do {
            try context.save()
        } catch {
            context.rollback()
            throw ImportError.saveFailed(detail: error.localizedDescription)
        }
        return imported
    }
```

2. In `BoardStoreImportTests`: replace `appendIsOneUndoStep` and `undoActionName` with a single test asserting `canUndo == false` after import; keep `emptyEnvelopeAppendIsNoOp` as-is.
3. Reduce `ImportUndoOnDiskTests` to one on-disk materialize smoke (import → assert graph → save → assert).
4. Record the FAIL outcome in the spec's "Spike outcome" block (crash signature, triage evidence) and note that PRD/CLAUDE.md updates land in Task 9 (non-undoable append + new pitfall entry).
5. Re-run both suites, then commit with message `Spike outcome: append import falls back to non-undoable — on-disk undo assert (E-02)`.

---

### Task 3: `ExportDocument.decodeForImport` — decode, version gate, sanitize

**Files:**
- Modify: `Tack/Export/ExportDocument.swift` (extend the `ExportDocument` enum; also update the `ExportJSONDocument.init(configuration:)` stub comment)
- Create: `TackTests/ImportDecodeTests.swift`

**Interfaces:**
- Consumes: `ExportDocument.decode`, `ImportError` (Task 1), `HexColor.parse`/`HexColor.format` (in `Tack/Models/BoardTheme.swift`), `LabelColor`.
- Produces: `static func decodeForImport(_ data: Data, calendar: Calendar = .current) throws -> ExportEnvelope` on `ExportDocument`.

- [ ] **Step 1: Write the failing tests — create `TackTests/ImportDecodeTests.swift`**

```swift
import Testing
import Foundation
@testable import Tack

/// E-02 pure codec leg: decode + formatVersion gate + gray-zone sanitization. No ModelContainer.
@Suite("ExportDocument.decodeForImport")
struct ImportDecodeTests {

    /// A UTC-pinned calendar so start-of-day assertions are deterministic regardless of the
    /// machine's time zone (the production default `Calendar.current` is injectable by design).
    private var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func json(_ boards: String, formatVersion: Int = 1) -> Data {
        Data("""
        {"boards":[\(boards)],"exportedAt":"2026-07-08T00:00:00Z","formatVersion":\(formatVersion)}
        """.utf8)
    }

    private func cardJSON(labels: String = "[]", dueDate: String? = nil, includesTime: Bool = false) -> String {
        let due = dueDate.map { "\"dueDate\":\"\($0)\"," } ?? ""
        return """
        {"createdAt":"2026-01-01T00:00:00Z","details":null,\(due)"includesTime":\(includesTime),
         "labels":\(labels),"position":0,"title":"C","updatedAt":"2026-01-01T00:00:00Z"}
        """
    }

    private func boardJSON(cards: String, customThemeHex: String = "null") -> String {
        """
        {"createdAt":"2026-01-01T00:00:00Z","customThemeHex":\(customThemeHex),"lists":[
          {"cards":[\(cards)],"isCollapsed":false,"name":"L","position":0}
        ],"name":"B","position":0,"themeName":"default"}
        """
    }

    // MARK: - Hard rejects

    @Test("malformed JSON throws .unreadable")
    func malformedJSONUnreadable() {
        #expect(throws: ImportError.self) {
            try ExportDocument.decodeForImport(Data("not json {".utf8))
        }
        do { _ = try ExportDocument.decodeForImport(Data("not json {".utf8)) }
        catch let error as ImportError { #expect(error.caseName == "unreadable") }
        catch { Issue.record("expected ImportError, got \(error)") }
    }

    @Test("a missing required field (board without name) throws .unreadable")
    func missingRequiredFieldUnreadable() {
        let noName = json("""
        {"createdAt":"2026-01-01T00:00:00Z","lists":[],"position":0,"themeName":"default"}
        """)
        do { _ = try ExportDocument.decodeForImport(noName) }
        catch let error as ImportError { #expect(error.caseName == "unreadable") }
        catch { Issue.record("expected ImportError, got \(error)") }
    }

    @Test("missing formatVersion key throws .unreadable")
    func missingVersionKeyUnreadable() {
        let data = Data(#"{"boards":[],"exportedAt":"2026-07-08T00:00:00Z"}"#.utf8)
        do { _ = try ExportDocument.decodeForImport(data) }
        catch let error as ImportError { #expect(error.caseName == "unreadable") }
        catch { Issue.record("expected ImportError, got \(error)") }
    }

    @Test("formatVersion 2 and 0 throw .unsupportedVersion carrying the file's version")
    func versionGate() {
        for version in [2, 0] {
            do { _ = try ExportDocument.decodeForImport(json("", formatVersion: version)) }
            catch let error as ImportError { #expect(error == .unsupportedVersion(version)) }
            catch { Issue.record("expected ImportError, got \(error)") }
        }
    }

    @Test("fractional-second ISO dates throw .unreadable (Foundation .iso8601 rejects them)")
    func fractionalSecondsUnreadable() {
        let data = json(boardJSON(cards: cardJSON(dueDate: "2026-07-08T10:00:00.123Z")))
        do { _ = try ExportDocument.decodeForImport(data) }
        catch let error as ImportError { #expect(error.caseName == "unreadable") }
        catch { Issue.record("expected ImportError, got \(error)") }
    }

    // MARK: - Valid decodes

    @Test("a zero-board envelope decodes successfully")
    func emptyEnvelopeDecodes() throws {
        let envelope = try ExportDocument.decodeForImport(json(""))
        #expect(envelope.boards.isEmpty)
        #expect(envelope.formatVersion == 1)
    }

    // MARK: - Gray-zone sanitization

    @Test("unknown label names are dropped; known ones kept")
    func unknownLabelsDropped() throws {
        let envelope = try ExportDocument.decodeForImport(
            json(boardJSON(cards: cardJSON(labels: #"["green","neon"]"#))))
        #expect(envelope.boards[0].lists[0].cards[0].labels == ["green"])
    }

    @Test("duplicate labels are deduped and reordered to palette order")
    func labelsDedupedAndPaletteOrdered() throws {
        let envelope = try ExportDocument.decodeForImport(
            json(boardJSON(cards: cardJSON(labels: #"["blue","red","blue"]"#))))
        #expect(envelope.boards[0].lists[0].cards[0].labels == ["red", "blue"],
                "LabelColor.allCases order: red before blue, duplicates collapsed")
    }

    @Test("dueDate is normalized to the calendar's start of day when includesTime is false")
    func dueDateNormalizedWhenDateOnly() throws {
        let envelope = try ExportDocument.decodeForImport(
            json(boardJSON(cards: cardJSON(dueDate: "2026-07-08T15:30:00Z"))), calendar: utcCalendar)
        let expected = ISO8601DateFormatter().date(from: "2026-07-08T00:00:00Z")!
        #expect(envelope.boards[0].lists[0].cards[0].dueDate == expected)
    }

    @Test("dueDate is untouched when includesTime is true")
    func dueDateUntouchedWhenIncludesTime() throws {
        let envelope = try ExportDocument.decodeForImport(
            json(boardJSON(cards: cardJSON(dueDate: "2026-07-08T15:30:00Z", includesTime: true))),
            calendar: utcCalendar)
        let expected = ISO8601DateFormatter().date(from: "2026-07-08T15:30:00Z")!
        #expect(envelope.boards[0].lists[0].cards[0].dueDate == expected)
    }

    @Test("customThemeHex is canonicalized ('#ff0000' → 'FF0000'); garbage becomes nil")
    func hexCanonicalized() throws {
        let canonical = try ExportDocument.decodeForImport(
            json(boardJSON(cards: cardJSON(), customThemeHex: "\"#ff0000\"")))
        #expect(canonical.boards[0].customThemeHex == "FF0000")

        let garbage = try ExportDocument.decodeForImport(
            json(boardJSON(cards: cardJSON(), customThemeHex: "\"nothex\"")))
        #expect(garbage.boards[0].customThemeHex == nil)
    }

    @Test("themeName and position fields pass through unrewritten")
    func themeAndPositionsUntouched() throws {
        let data = json("""
        {"createdAt":"2026-01-01T00:00:00Z","lists":[],"name":"B","position":42,
         "themeName":"definitely-not-a-preset"}
        """)
        let envelope = try ExportDocument.decodeForImport(data)
        #expect(envelope.boards[0].themeName == "definitely-not-a-preset",
                "unknown themes resolve at render (ThemeResolution.resolve → .default); not sanitize's job")
        #expect(envelope.boards[0].position == 42,
                "DTO positions are never read by the materializer — rewriting them would be dead code")
    }

    @Test("sanitization is idempotent: decode(encode(decoded)) == decoded")
    func sanitizeIdempotent() throws {
        let data = json(boardJSON(cards: cardJSON(labels: #"["blue","red","neon"]"#,
                                                  dueDate: "2026-07-08T15:30:00Z"),
                                  customThemeHex: "\"#ff0000\""))
        let once = try ExportDocument.decodeForImport(data, calendar: utcCalendar)
        let twice = try ExportDocument.decodeForImport(try ExportDocument.encode(once), calendar: utcCalendar)
        #expect(once == twice)
    }
}
```

- [ ] **Step 2: `make gen`, run the suite, verify it fails to compile**

Single-suite command with `-only-testing:TackTests/ImportDecodeTests`.
Expected: **build FAILURE** — `type 'ExportDocument' has no member 'decodeForImport'`.

- [ ] **Step 3: Implement `decodeForImport` in `Tack/Export/ExportDocument.swift`**

Add inside the `ExportDocument` enum, directly after `decode(_:)`:

```swift
    /// E-02 import: decode → explicit `formatVersion` gate (plain `decode` ignores it) → pure
    /// gray-zone sanitization (spec: hard-reject only structural failure; sanitize the rest).
    /// `calendar` is injectable so the start-of-day rule is table-testable under a pinned time
    /// zone; production uses `.current`. Idempotent: re-running on its own output is the identity
    /// (pinned by ImportDecodeTests).
    static func decodeForImport(_ data: Data, calendar: Calendar = .current) throws -> ExportEnvelope {
        let envelope: ExportEnvelope
        do {
            envelope = try decode(data)
        } catch {
            throw ImportError.unreadable(detail: String(describing: error))
        }
        guard envelope.formatVersion == formatVersion else {
            throw ImportError.unsupportedVersion(envelope.formatVersion)
        }
        return sanitized(envelope, calendar: calendar)
    }

    /// Gray-zone sanitization (all pure, all idempotent):
    ///   - card labels filtered to known `LabelColor` rawValues, deduped, reordered to palette order;
    ///   - `dueDate` → `calendar.startOfDay` when `includesTime == false` (the Card invariant);
    ///   - `customThemeHex` canonicalized via HexColor parse→format, or nil when unparsable (the
    ///     store's "never persists unparsable hex" invariant).
    /// Deliberately NOT rewritten: `themeName` (unknowns resolve to `.default` at render — that IS
    /// the fallback) and every `position` field (the materializer never reads them).
    private static func sanitized(_ envelope: ExportEnvelope, calendar: Calendar) -> ExportEnvelope {
        var result = envelope
        result.boards = envelope.boards.map { board in
            var board = board
            board.customThemeHex = board.customThemeHex
                .flatMap(HexColor.parse)
                .map { HexColor.format(r: $0.r, g: $0.g, b: $0.b) }
            board.lists = board.lists.map { list in
                var list = list
                list.cards = list.cards.map { card in
                    var card = card
                    let owned = Set(card.labels.compactMap(LabelColor.init(rawValue:)))
                    card.labels = LabelColor.allCases.filter { owned.contains($0) }.map(\.rawValue)
                    if let dueDate = card.dueDate, !card.includesTime {
                        card.dueDate = calendar.startOfDay(for: dueDate)
                    }
                    return card
                }
                return list
            }
            return board
        }
        return result
    }
```

Also replace the stale comment inside `ExportJSONDocument.init(configuration:)` with:

```swift
        // E-02 shipped via URL-based `.fileImporter` (see RootView.handlePickedImportFile), so this
        // ReadConfiguration path remains unused by design; it exists only so the type is a complete
        // FileDocument. Export never round-trips through this initializer.
```

Note: `HexColor.parse` returns an optional tuple `(r:g:b:)` and `HexColor.format(r:g:b:)` returns the canonical `"RRGGBB"` — both already exist in `Tack/Models/BoardTheme.swift` (used by `BoardStore.setTheme`).

- [ ] **Step 4: Run the suite to verify it passes**

Same command as Step 2. Expected: **all 13 tests PASS**.

- [ ] **Step 5: Commit**

```bash
git add Tack/Export/ExportDocument.swift TackTests/ImportDecodeTests.swift
git commit -m "Add ExportDocument.decodeForImport — version gate + gray-zone sanitize (E-02)"
```

---

### Task 4: `BoardStore.replaceAllBoards` + byte-equality round trip

**Files:**
- Modify: `Tack/Store/BoardStore.swift` (add `replaceAllBoards` directly after `importBoards`)
- Modify: `TackTests/BoardStoreImportTests.swift` (append tests)

**Interfaces:**
- Consumes: `materialize` + `ImportError` (Task 1), `decodeForImport` (Task 3).
- Produces: `@discardableResult func replaceAllBoards(with envelope: ExportEnvelope, importedAt: Date = .now) throws -> [Board]` on `BoardStore`.

- [ ] **Step 1: Append the failing tests to `TackTests/BoardStoreImportTests.swift`**

```swift
    // MARK: - Replace mode (Task 4)

    @Test("replace deletes existing boards; only envelope boards remain; palette stays 8")
    func replaceDeletesExisting() throws {
        let env = TestContainer()
        defer { withExtendedLifetime(env) {} }
        env.store.ensureLabelsSeeded()
        env.store.createBoard(name: "Old 1", emoji: nil)
        env.store.createBoard(name: "Old 2", emoji: nil)

        let imported = try env.store.replaceAllBoards(with: sampleEnvelope())

        #expect(fetchBoards(env.context).map(\.name) == ["Imported A", "Imported B"])
        #expect(fetchBoards(env.context).map(\.position) == [0, 1], "replace re-bases at position 0")
        #expect(fetchLabels(env.context).count == 8)
        #expect(imported.map(\.name) == ["Imported A", "Imported B"])
    }

    @Test("replace clears the undo stack (never undoable)")
    func replaceClearsUndoStack() throws {
        let env = TestContainer(withUndo: true)
        defer { withExtendedLifetime(env) {} }
        env.store.ensureLabelsSeeded()
        env.store.createBoard(name: "Old", emoji: nil)
        #expect(env.undoManager!.canUndo == true, "precondition: something undoable exists")

        try env.store.replaceAllBoards(with: sampleEnvelope())

        #expect(env.undoManager!.canUndo == false)
        #expect(env.undoManager!.canRedo == false)
    }

    @Test("replace with an empty envelope throws .emptyReplace and mutates nothing")
    func replaceEmptyThrowsAndMutatesNothing() throws {
        let env = TestContainer()
        defer { withExtendedLifetime(env) {} }
        env.store.ensureLabelsSeeded()
        env.store.createBoard(name: "Survivor", emoji: nil)

        let empty = ExportEnvelope(formatVersion: 1, exportedAt: .now, boards: [])
        #expect(throws: ImportError.emptyReplace) {
            try env.store.replaceAllBoards(with: empty)
        }
        #expect(fetchBoards(env.context).map(\.name) == ["Survivor"])
    }

    // MARK: - Byte-equality round trip (Task 4; the strongest cheap oracle)

    @Test("export → import into a fresh store → re-export reproduces the original bytes")
    func byteEqualityRoundTrip() throws {
        // Container A: seed via store ops, exercising EVERY format field — emoji, theme + custom
        // hex, a collapsed list, details, multiple labels, a due date (includesTime false).
        let a = TestContainer()
        defer { withExtendedLifetime(a) {} }
        a.store.ensureLabelsSeeded()
        let alpha = a.store.createBoard(name: "Alpha", emoji: "🅰️")
        a.store.setTheme(alpha, themeName: "ocean", customHex: "#ff8800")
        let alphaLists = alpha.sortedLists
        a.store.setCollapsed(alphaLists[1], true)
        let cardOne = a.store.addCard(to: alphaLists[0], title: "Card One")
        a.store.applyCardEdits(cardOne, title: "Card One", details: "line1\nline2",
                               labels: [.red, .blue], dueDate: Date(timeIntervalSince1970: 1_781_800_000))
        a.store.addCard(to: alphaLists[0], title: "Card Two")
        a.store.createBoard(name: "Beta", emoji: nil)

        let fixedExportedAt = Date(timeIntervalSince1970: 1_781_827_200)
        let aBoards = fetchBoards(a.context)
        let original = try ExportDocument.encode(ExportDocument.makeEnvelope(boards: aBoards, exportedAt: fixedExportedAt))

        // Container B: fresh, PALETTE SEEDED FIRST (TestContainer does not seed it; an unseeded B
        // would silently drop every label), import through the full production decode path.
        let b = TestContainer()
        defer { withExtendedLifetime(b) {} }
        b.store.ensureLabelsSeeded()
        try b.store.importBoards(try ExportDocument.decodeForImport(original))

        let bBoards = fetchBoards(b.context)
        let reExported = try ExportDocument.encode(ExportDocument.makeEnvelope(boards: bBoards, exportedAt: fixedExportedAt))
        #expect(reExported == original,
                "byte-stable round trip: positions, label order, dates, theme, collapse state all survive")
    }
```

- [ ] **Step 2: Run the suite, verify the new tests fail to compile (`replaceAllBoards` missing)**

Single-suite command with `-only-testing:TackTests/BoardStoreImportTests`.
Expected: **build FAILURE** — `no member 'replaceAllBoards'`.

- [ ] **Step 3: Implement `replaceAllBoards` in `Tack/Store/BoardStore.swift`**

Directly after `importBoards`:

```swift
    /// Replace-mode import: deletes EVERY existing board, then materializes the envelope from
    /// position 0. ALWAYS non-undoable — `deleteBoard`'s detach discipline verbatim (see that
    /// method's evidence for why an on-disk Board delete with an attached manager fatally
    /// asserts): manager detached for the whole delete + materialize + save span, reattached +
    /// stack cleared in a defer (prior undo groups reference the deleted boards). Delete and
    /// insert share the ONE save, so a failed replace can never leave deleted-but-not-replaced
    /// data (rollback revives the unsaved deletes).
    ///
    /// Guards `.emptyReplace` as the store-level backstop behind the dialog's omitted Replace
    /// button: a zero-board envelope must never be able to wipe the store.
    @discardableResult
    func replaceAllBoards(with envelope: ExportEnvelope, importedAt: Date = .now) throws -> [Board] {
        guard !envelope.boards.isEmpty else { throw ImportError.emptyReplace }

        let held = context.undoManager
        context.undoManager = nil
        defer {
            context.undoManager = held
            held?.removeAllActions()
        }

        for board in fetchBoards() {
            context.delete(board)
        }
        let imported = materialize(envelope, basePosition: 0, importedAt: importedAt)
        do {
            try context.save()
        } catch {
            context.rollback()
            throw ImportError.saveFailed(detail: error.localizedDescription)
        }
        return imported
    }
```

- [ ] **Step 4: Run the suite, then the full unit suite**

Run the single-suite command (expected: **all 10 tests PASS**), then `make unit` (expected: PASS).

- [ ] **Step 5: Commit**

```bash
git add Tack/Store/BoardStore.swift TackTests/BoardStoreImportTests.swift
git commit -m "Add BoardStore.replaceAllBoards — non-undoable replace import + byte-equality round trip (E-02)"
```

---

### Task 5: UI wiring — menu command, fileImporter, mode dialog, error alert, empty state

**Files:**
- Modify: `Tack/Commands/FocusedValues.swift` (add `importBoards` to `BoardSelectionActions`)
- Modify: `Tack/Commands/AppCommands.swift` (add the menu item)
- Modify: `Tack/Views/RootView.swift` (importer state + modifiers + completion)
- Modify: `Tack/Views/EmptyStateView.swift` (secondary button)
- Modify: `Tack/Support/AccessibilityID.swift` (empty-state button id)
- Create: `TackUITests/ImportUITests.swift` (menu + empty-state tests only; content e2es land in Task 7)
- Modify: `TackUITests/TackUITestCase.swift` + `TackUITests/ExportUITests.swift` (promote the private menu helpers to the base class)

**Interfaces:**
- Consumes: `ImportError`, `decodeForImport`, `importBoards`, `replaceAllBoards` (Tasks 1–4).
- Produces: `BoardSelectionActions.importBoards: () -> Void`; `EmptyStateView(onCreateBoard:onImportBoards:)`; `AccessibilityID.emptyStateImportButton == "empty-import-boards"`; `RootView.completeImport(_:replacing:)` and `RootView.PendingImport` (Task 6's hook routes through these); base-class `openMenu(_:)`/`menuItem(_:)`/`closeMenu()` on `TackUITestCase`.

- [ ] **Step 1: Add the closure to `BoardSelectionActions` in `Tack/Commands/FocusedValues.swift`**

Append to the struct, after `exportAllBoards`:

```swift
    /// E-02 / ⇧⌘I — File ▸ "Import Boards…": presents the JSON open panel (RootView hosts the
    /// `.fileImporter` — a `Commands` value can't present one, same constraint as the exporter).
    /// Always enabled, including at zero boards: restore-into-an-empty-app is the headline case.
    let importBoards: () -> Void
```

- [ ] **Step 2: Add the menu item in `Tack/Commands/AppCommands.swift`**

Directly after the `Button("Export All Boards…")` block (before its trailing `Divider()`):

```swift
            // E-02 (⇧⌘I): import a JSON backup via the open panel (hosted by RootView, same
            // constraint as the exporter). Enabled whenever RootView publishes the surface —
            // including with zero boards (restore-into-empty is the headline case).
            Button("Import Boards…") { guardedMutation { boardSelection?.importBoards() } }
                .keyboardShortcut("i", modifiers: [.command, .shift])
                .disabled(boardSelection == nil)
```

- [ ] **Step 3: Wire `RootView` (`Tack/Views/RootView.swift`)**

3a. Add state + a nested type after the existing export properties (after `@State private var exportSelfCheck`):

```swift
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
```

3b. Add the modifiers, directly after the existing `.fileExporter(...)` block:

```swift
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
```

3c. Add `importBoards: { isPresentingImporter = true }` to the `BoardSelectionActions(...)` initializer call in `boardSelectionActions` (after `exportAllBoards: presentExporter`).

3d. Add the import methods, after `presentExporter()`:

```swift
    // MARK: - Import (E-02)

    /// Reads and decodes the picked file. Security-scoped access: call `start` unconditionally
    /// and gate ONLY the paired `stop` on its Bool — it returns false for URLs already covered by
    /// the user-selected entitlement grant, so gating the READ on it would break legitimate
    /// imports. The decoded envelope is parked in `pendingImport` on the NEXT main-queue tick:
    /// flipping a confirmationDialog on in the same tick the fileImporter dismisses can silently
    /// fail to present (verify the hop is needed by hand during implementation; record the result
    /// in the spec).
    private func handlePickedImportFile(_ result: Result<URL, Error>) {
        guard case .success(let url) = result else { return }   // panel cancel/error: no-op
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
            importError = error
        } catch {
            importError = .unreadable(detail: error.localizedDescription)
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
        return "“\(pending.filename)” contains \(importedBoards.count) board(s) (\(listCount) list(s), \(cardCount) card(s)). "
            + "“Add to Existing” keeps your current \(boards.count) board(s) and adds the imported ones after them. "
            + "“Replace All Boards” deletes your current board(s) first — replacing cannot be undone."
    }

    /// Shared completion for the dialog buttons AND the --import-from test hook (Task 6), so both
    /// paths get identical store routing and post-import selection.
    private func completeImport(_ pending: PendingImport, replacing: Bool) {
        pendingImport = nil
        do {
            let imported = replacing
                ? try store.replaceAllBoards(with: pending.envelope)
                : try store.importBoards(pending.envelope)
            if let first = imported.first {
                selectedBoardID = first.id
            }
        } catch let error as ImportError {
            importError = error
        } catch {
            importError = .saveFailed(detail: error.localizedDescription)
        }
    }

    private func cancelImport() {
        pendingImport = nil
    }
```

- [ ] **Step 4: Add the empty-state button**

`Tack/Support/AccessibilityID.swift` — after `emptyStateCreateBoardButton`:

```swift
    static let emptyStateImportButton = "empty-import-boards"
```

`Tack/Views/EmptyStateView.swift` — full new body:

```swift
/// Shown in the detail pane when there are zero boards. `onCreateBoard` opens the SAME creation
/// sheet as the sidebar's "New Board" toolbar button; `onImportBoards` presents the SAME import
/// open panel as File ▸ Import Boards… (E-02) — restore-onto-a-fresh-machine lands exactly here.
/// The state for both lives in `RootView`.
struct EmptyStateView: View {
    let onCreateBoard: () -> Void
    let onImportBoards: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "square.grid.2x2")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("No boards yet")
                .font(.title2)
                .bold()
            Text("Create a board to start organizing your work.")
                .foregroundStyle(.secondary)
            Button("Create your first board", action: onCreateBoard)
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier(AccessibilityID.emptyStateCreateBoardButton)
            Button("Import from Backup…", action: onImportBoards)
                .accessibilityIdentifier(AccessibilityID.emptyStateImportButton)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}
```

And in `RootView.detailContent`, update the call site:

```swift
        if boards.isEmpty {
            EmptyStateView(onCreateBoard: { isPresentingCreateBoard = true },
                           onImportBoards: { isPresentingImporter = true })
        }
```

- [ ] **Step 5: Promote the menu helpers to `TackUITestCase`**

Add to `TackUITests/TackUITestCase.swift` (new `// MARK: - Menus` section after the context-menus section) — moved verbatim from `ExportUITests` so `ImportUITests` can share them:

```swift
    // MARK: - Menus

    func openMenu(_ title: String, timeout: TimeInterval = 15) {
        let bar = app.menuBars.menuBarItems[title]
        XCTAssertTrue(bar.waitForExistence(timeout: timeout), "\(title) menu should exist in the menu bar")
        bar.click()
    }

    func closeMenu() {
        app.typeKey(.escape, modifierFlags: [])
    }

    func menuItem(_ title: String) -> XCUIElement {
        app.menuBars.menuItems[title]
    }
```

Delete the three now-duplicate `private func openMenu/closeMenu/menuItem` helpers from `TackUITests/ExportUITests.swift` (the base-class versions are call-compatible).

- [ ] **Step 6: Create `TackUITests/ImportUITests.swift` with the two panel-free tests**

```swift
import XCTest

/// E-02 JSON import. The production open panel is a sandboxed, remote-hosted NSOpenPanel that
/// XCUITest cannot drive (same class as E-01's save panel), and the sandboxed runner cannot place
/// files inside the app container — so content e2es (Task 7) use the --import-from launch hook,
/// with the app exporting its own input first via --export-to. This file starts with the two
/// panel-free legs: menu discoverability/enablement and the empty-state affordance.
final class ImportUITests: TackUITestCase {

    private let timeout: TimeInterval = 15

    private var rootView: XCUIElement { app.descendants(matching: .any)[AccessibilityID.rootView] }
    private var boardDetail: XCUIElement { app.descendants(matching: .any)[AccessibilityID.boardDetail] }

    func testImportMenuItemExistsAndEnabledOnBothFixtures() {
        // Unlike Export (disabled at zero boards), Import is enabled EVERYWHERE — restore into an
        // empty app is its headline case.
        launch(fixture: "empty")
        XCTAssertTrue(rootView.waitForExistence(timeout: timeout))
        openMenu("File")
        let importItem = menuItem("Import Boards…")
        XCTAssertTrue(importItem.waitForExistence(timeout: timeout), "File ▸ Import Boards… should exist")
        XCTAssertTrue(importItem.isEnabled, "Import should be enabled with zero boards")
        closeMenu()

        app.terminate()
        launch(fixture: "standard")
        XCTAssertTrue(boardDetail.waitForExistence(timeout: timeout))
        openMenu("File")
        XCTAssertTrue(menuItem("Import Boards…").waitForExistence(timeout: timeout))
        XCTAssertTrue(menuItem("Import Boards…").isEnabled, "Import should be enabled with boards present")
        closeMenu()
    }

    func testEmptyStateShowsImportButton() {
        launch(fixture: "empty")
        let importButton = app.buttons[AccessibilityID.emptyStateImportButton]
        XCTAssertTrue(importButton.waitForExistence(timeout: timeout),
                      "the zero-board empty state should offer Import from Backup…")
        // Presence-only: clicking would open the un-drivable NSOpenPanel.
    }
}
```

- [ ] **Step 7: `make gen`, build, run the new UI tests + the export suite (helper move)**

```sh
make gen && make build
pkill -f xcodebuild; pkill -f Tack.app
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project Tack.xcodeproj -scheme Tack \
  -destination "platform=macOS,arch=$(uname -m)" -derivedDataPath .build/DerivedData \
  -only-testing:TackUITests/ImportUITests -only-testing:TackUITests/ExportUITests test
```

Expected: **all 4 tests PASS** (2 new + 2 export regressions exercising the moved helpers).

- [ ] **Step 8: Commit**

```bash
git add Tack/Commands/FocusedValues.swift Tack/Commands/AppCommands.swift Tack/Views/RootView.swift \
        Tack/Views/EmptyStateView.swift Tack/Support/AccessibilityID.swift \
        TackUITests/ImportUITests.swift TackUITests/TackUITestCase.swift TackUITests/ExportUITests.swift
git commit -m "Wire Import Boards… UI — ⇧⌘I, fileImporter, mode dialog, first error alert, empty-state button (E-02)"
```

---

### Task 6: Launch hooks — `--import-from` / `--import-mode` + self-check marker

**Files:**
- Modify: `Tack/Support/AppLaunchConfig.swift`
- Modify: `Tack/Support/AccessibilityID.swift`
- Modify: `Tack/Views/RootView.swift`
- Modify: `TackUITests/TackUITestCase.swift`
- Modify: `TackTests/AppLaunchConfigTests.swift`

**Interfaces:**
- Consumes: `RootView.completeImport(_:replacing:)`/`PendingImport`/`cancelImport()` (Task 5), `ModelContainerFactory.uiTestDirectory()`.
- Produces: `AppLaunchConfig.importFrom: String?`, `AppLaunchConfig.importMode: String?`; `AccessibilityID.importSelfCheck == "import-self-check"`; `TackUITestCase.launch(fixture:reset:storeName:appearance:exportTo:importFrom:importMode:)`. Marker grammar (Task 7 asserts these exact shapes): `ok|<board names in position order>|<first board's first-list card titles>`, `error|<ImportError.caseName>`, `cancelled`.

- [ ] **Step 1: Write the failing parse tests — append to `TackTests/AppLaunchConfigTests.swift`**

```swift
    // MARK: - E-02: --import-from / --import-mode

    @Test("importFrom reads the value following --import-from; nil when absent or trailing")
    func importFromParsing() {
        #expect(AppLaunchConfig(arguments: ["--uitest", "--import-from", "backup.json"]).importFrom == "backup.json")
        #expect(AppLaunchConfig(arguments: ["--uitest"]).importFrom == nil)
        #expect(AppLaunchConfig(arguments: ["--uitest", "--import-from"]).importFrom == nil)
    }

    @Test("importMode reads the value following --import-mode; nil when absent or trailing")
    func importModeParsing() {
        #expect(AppLaunchConfig(arguments: ["--uitest", "--import-mode", "replace"]).importMode == "replace")
        #expect(AppLaunchConfig(arguments: ["--uitest"]).importMode == nil)
        #expect(AppLaunchConfig(arguments: ["--uitest", "--import-mode"]).importMode == nil)
    }
```

- [ ] **Step 2: Run to verify failure, then implement `AppLaunchConfig`**

Run with `-only-testing:TackTests/AppLaunchConfigTests` → **build FAILURE** (`no member 'importFrom'`). Then add to the struct, after `exportTo`:

```swift
    /// E-02 import e2e hook, test-only (mirrors `exportTo`): `--import-from <filename>` makes a
    /// `--uitest` launch read `UITest/<filename>` from the sandbox container and run it through
    /// the production decode + store path, publishing the outcome via the `import-self-check`
    /// marker. Exists because the production import runs through a sandboxed, remote-hosted
    /// NSOpenPanel that XCUITest cannot drive, and the sandboxed runner cannot place files in the
    /// app container (the canonical e2e has the app export its own input first via `--export-to`).
    let importFrom: String?
    /// E-02, test-only: `--import-mode add|replace|ask` (default add). `add`/`replace` import
    /// directly (deterministic content tests); `ask` presents the REAL mode dialog so a test can
    /// drive its buttons — the only automatable path onto the dialog.
    let importMode: String?
```

And in `init(arguments:)`, after the `exportTo` line:

```swift
        importFrom = AppLaunchConfig.value(after: "--import-from", in: arguments)
        importMode = AppLaunchConfig.value(after: "--import-mode", in: arguments)
```

(No static passthroughs — `exportTo` has none either.) Re-run: **PASS**.

- [ ] **Step 3: Add the marker id to `Tack/Support/AccessibilityID.swift`**

After `exportSelfCheck`:

```swift
    /// E-02 import e2e marker (test-only, present only under `--import-from`). Same detached
    /// `.accessibilityRepresentation` pattern as `exportSelfCheck`. Value grammar (STABLE tokens,
    /// never localized copy): "ok|<all post-import board names in position order>|<first board's
    /// first-list card titles>" — computed from LIVE post-import store state, the only oracle that
    /// distinguishes add from replace when names duplicate; "error|<ImportError.caseName>" on any
    /// failure; "cancelled" when the ask-mode dialog is dismissed.
    static let importSelfCheck = "import-self-check"
```

- [ ] **Step 4: Wire the hook in `Tack/Views/RootView.swift`**

4a. Properties — after `exportSelfCheck`:

```swift
    /// E-02 import e2e (test-only): `--import-from` filename, `--import-mode` override, the
    /// published outcome marker, and a one-shot guard (marker-independent: ask-mode publishes
    /// nothing until a dialog button is clicked, so the marker can't be the guard).
    private let importFromFilename: String?
    private let importModeOverride: String?
    @State private var importSelfCheck: String?
    @State private var importHookHasRun = false
```

In `init(config:)`, after the `exportToFilename` line:

```swift
        importFromFilename = config.isUITest ? config.importFrom : nil
        importModeOverride = config.isUITest ? config.importMode : nil
```

4b. Marker view — inside the `ZStack`, after the `exportSelfCheck` block:

```swift
            // E-02 import e2e marker (present only under --import-from): see AccessibilityID.
            if let importSelfCheck {
                Color.clear
                    .allowsHitTesting(false)
                    .accessibilityRepresentation {
                        Text(importSelfCheck)
                            .accessibilityIdentifier(AccessibilityID.importSelfCheck)
                    }
            }
```

4c. Trigger — after `.onAppear(perform: runExportSelfCheckIfNeeded)`:

```swift
        .onAppear(perform: runImportSelfCheckIfNeeded)
```

4d. The hook + marker plumbing — after `cancelImport()`:

```swift
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
            importError = .unreadable(detail: error.localizedDescription)
            publishImportMarker("error|unreadable")
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
```

4e. Hook the marker into the shared completion paths — `completeImport` gains one line in each branch, and `cancelImport` publishes the cancel token. Replace both methods with:

```swift
    /// Shared completion for the dialog buttons AND the --import-from test hook, so both paths
    /// get identical store routing, post-import selection, and (test-only) marker publication.
    private func completeImport(_ pending: PendingImport, replacing: Bool) {
        pendingImport = nil
        do {
            let imported = replacing
                ? try store.replaceAllBoards(with: pending.envelope)
                : try store.importBoards(pending.envelope)
            if let first = imported.first {
                selectedBoardID = first.id
            }
            publishImportMarker(importSuccessSummary())
        } catch let error as ImportError {
            importError = error
            publishImportMarker("error|\(error.caseName)")
        } catch {
            importError = .saveFailed(detail: error.localizedDescription)
            publishImportMarker("error|saveFailed")
        }
    }

    private func cancelImport() {
        pendingImport = nil
        publishImportMarker("cancelled")
    }
```

- [ ] **Step 5: Extend `TackUITestCase.launch`**

Replace the `launch` signature and arg-building in `TackUITests/TackUITestCase.swift`:

```swift
    @discardableResult
    func launch(fixture: String = "standard", reset: Bool = true, storeName: String? = nil,
                appearance: String? = nil, exportTo: String? = nil,
                importFrom: String? = nil, importMode: String? = nil) -> XCUIApplication {
```

and after the `exportTo` block:

```swift
        // E-02 import e2e: `--import-from <file>` (+ optional `--import-mode add|replace|ask`)
        // makes the app read that JSON from the sandbox UITest/ dir and import it on launch.
        // relaunchPreservingStore deliberately re-passes NEITHER flag: a preserved-store relaunch
        // must never double-import (and FixtureSeeder skips non-empty stores) — this
        // non-forwarding is what makes the persistence leg of the round-trip test valid. Do not
        // "fix" it to forward all args.
        if let importFrom {
            args.append(contentsOf: ["--import-from", importFrom])
        }
        if let importMode {
            args.append(contentsOf: ["--import-mode", importMode])
        }
```

- [ ] **Step 6: Build + run unit suite**

Run: `make gen` (no new files, but harmless) then `make build && make unit`
Expected: build succeeds; `AppLaunchConfigTests` (now 6+2 tests) and all other unit suites PASS.

- [ ] **Step 7: Commit**

```bash
git add Tack/Support/AppLaunchConfig.swift Tack/Support/AccessibilityID.swift Tack/Views/RootView.swift \
        TackUITests/TackUITestCase.swift TackTests/AppLaunchConfigTests.swift
git commit -m "Add --import-from/--import-mode launch hooks + import self-check marker (E-02)"
```

---

### Task 7: Content e2es — round trip, replace, error, dialog-cancel

**Files:**
- Modify: `TackUITests/ImportUITests.swift` (append four tests)

**Interfaces:**
- Consumes: everything from Tasks 5–6. Marker grammar and `launch(importFrom:importMode:)` exactly as defined in Task 6. The standard fixture's known content: boards `Groceries`, `Work`; Groceries' To Do cards `Buy milk`, `Call plumber`, `Return library books` (see `ExportUITests.testExportWritesDecodableJSON`).

- [ ] **Step 1: Append the four content tests to `TackUITests/ImportUITests.swift`**

```swift
    // MARK: - Content e2es (via --export-to → --import-from; the panel itself is un-drivable)

    private var importMarker: XCUIElement {
        app.descendants(matching: .any)[AccessibilityID.importSelfCheck]
    }
    private var exportMarker: XCUIElement {
        app.descendants(matching: .any)[AccessibilityID.exportSelfCheck]
    }

    private func markerValue(_ marker: XCUIElement) -> String? { marker.value as? String }

    /// Launches the standard fixture with --export-to and waits until the export JSON is written
    /// (the export marker publishing IS the write-complete signal), then terminates.
    private func exportStandardFixture(to filename: String) {
        launch(fixture: "standard", exportTo: filename)
        XCTAssertTrue(poll(timeout: timeout) { exportMarker.exists && markerValue(exportMarker)?.isEmpty == false },
                      "export self-check should publish before we relaunch to import")
        app.terminate()
    }

    func testImportRoundTripRestoresBackup() {
        exportStandardFixture(to: "import-roundtrip.json")

        // Same auto-derived store name; --reset wipes only the sqlite files — the JSON survives.
        launch(fixture: "empty", importFrom: "import-roundtrip.json")

        XCTAssertTrue(poll(timeout: timeout) { importMarker.exists }, "import marker should publish")
        XCTAssertEqual(markerValue(importMarker), "ok|Groceries,Work|Buy milk,Call plumber,Return library books",
                       "live post-import store state should match the exported fixture")
        XCTAssertTrue(app.descendants(matching: .any)[AccessibilityID.board("Groceries")].waitForExistence(timeout: timeout))
        XCTAssertTrue(app.descendants(matching: .any)[AccessibilityID.board("Work")].exists)
        // Post-import selection: the first imported board is shown in the detail pane.
        let detail = app.descendants(matching: .any)[AccessibilityID.boardDetail]
        XCTAssertTrue(poll(timeout: timeout) { detail.exists && combinedText(detail).contains("Groceries") },
                      "the first imported board should be selected after import")

        // Persistence leg: relaunchPreservingStore re-passes neither import flag (by design), and
        // FixtureSeeder skips non-empty stores — so the boards must come from the persisted store.
        relaunchPreservingStore()
        XCTAssertTrue(app.descendants(matching: .any)[AccessibilityID.board("Groceries")].waitForExistence(timeout: timeout),
                      "imported boards should survive a relaunch")
    }

    func testReplaceModeReplacesExistingBoards() {
        exportStandardFixture(to: "import-replace.json")

        // Import the standard fixture's own export INTO the standard fixture, replace mode.
        launch(fixture: "standard", importFrom: "import-replace.json", importMode: "replace")

        XCTAssertTrue(poll(timeout: timeout) { importMarker.exists })
        XCTAssertEqual(markerValue(importMarker), "ok|Groceries,Work|Buy milk,Call plumber,Return library books",
                       "exactly the two imported boards — replace, not append (append would list four)")
        // Duplicate-count oracle: after replace exactly ONE row per name (append would show two).
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: AccessibilityID.board("Groceries")).count, 1)
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: AccessibilityID.board("Work")).count, 1)
        // Replace is never undoable and clears the stack.
        openMenu("Edit")
        let undoItem = app.menuBars.menuItems.matching(NSPredicate(format: "title BEGINSWITH 'Undo'")).firstMatch
        XCTAssertTrue(undoItem.waitForExistence(timeout: timeout))
        XCTAssertFalse(undoItem.isEnabled, "Edit ▸ Undo should be disabled after a replace import")
        closeMenu()
    }

    func testImportMissingFilePublishesErrorAndChangesNothing() {
        launch(fixture: "standard", importFrom: "does-not-exist.json")

        XCTAssertTrue(poll(timeout: timeout) { importMarker.exists })
        XCTAssertEqual(markerValue(importMarker), "error|unreadable",
                       "stable token, never localized alert copy")
        // The production error alert also presented — dismiss it, then confirm nothing changed.
        let ok = hittableButton("OK")
        if ok.waitForExistence(timeout: 5) { ok.click() }
        XCTAssertTrue(app.descendants(matching: .any)[AccessibilityID.board("Groceries")].waitForExistence(timeout: timeout))
        XCTAssertTrue(app.descendants(matching: .any)[AccessibilityID.board("Work")].exists)
    }

    func testImportDialogCancelDoesNothing() {
        exportStandardFixture(to: "import-cancel.json")

        // ask-mode presents the REAL mode dialog; drive its Cancel with the harness helper built
        // for confirmationDialog buttons.
        launch(fixture: "standard", importFrom: "import-cancel.json", importMode: "ask")

        let cancel = hittableButton("Cancel")
        XCTAssertTrue(cancel.waitForExistence(timeout: timeout), "the mode dialog should present under ask")
        cancel.click()

        XCTAssertTrue(poll(timeout: timeout) { markerValue(importMarker) == "cancelled" })
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: AccessibilityID.board("Groceries")).count, 1,
                       "cancel imports nothing — no duplicate rows")
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: AccessibilityID.board("Work")).count, 1)
    }
```

- [ ] **Step 2: Run the import UI suite**

```sh
pkill -f xcodebuild; pkill -f Tack.app
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project Tack.xcodeproj -scheme Tack \
  -destination "platform=macOS,arch=$(uname -m)" -derivedDataPath .build/DerivedData \
  -only-testing:TackUITests/ImportUITests test
```

Expected: **all 6 tests PASS** (2 from Task 5 + 4 new). If the ask-mode dialog never presents, that is the fileImporter→dialog presentation-race class — the hook already hops via `DispatchQueue.main.async`; record findings in the spec (the spec asks for the hop verification result).

- [ ] **Step 3: Run the FULL test suite**

Run: `make test`
Expected: unit + UI all PASS.

- [ ] **Step 4: Commit**

```bash
git add TackUITests/ImportUITests.swift
git commit -m "Add import content e2es — round trip, replace, error token, dialog cancel (E-02)"
```

---

### Task 8: Manual ship-gate verification (real panel + real-app ⌘Z)

**Files:**
- Modify: `docs/superpowers/specs/2026-07-08-json-import-design.md` (record outcomes)

**Interfaces:** none — this is the human verification the spec mandates (the M7 headless-pass/app-crash divergence guard). **This task blocks on the user.**

- [ ] **Step 1: Build and hand the user the procedure**

Run `make build`, then present exactly this procedure (≈60s) and STOP until the user reports back:

```
1. open .build/DerivedData/Build/Products/Debug/Tack.app --args --uitest --fixture standard --store-name humancheck --reset
2. File ▸ Export All Boards… (⇧⌘E) → save "roundtrip.json" somewhere reachable (e.g. Desktop).
3. File ▸ Import Boards… (⇧⌘I) → pick roundtrip.json → the dialog should read "Import 2 Boards"
   with list/card counts → click "Add to Existing".
   ✓ Sidebar shows Groceries, Work, Groceries, Work; the third row (imported Groceries) is selected.
4. Press ⌘Z once. ✓ Both imported boards disappear in one step; NO crash. Press ⇧⌘Z. ✓ Both return.
5. File ▸ Import Boards… → pick roundtrip.json → click "Replace All Boards".
   ✓ Destructive-styled button; after: exactly Groceries + Work; Edit ▸ Undo is DISABLED.
6. Optional (security-scope edge): repeat step 3 once with the file on an external/iCloud volume.
7. Afterwards: delete the humancheck.sqlite* files under the app sandbox's Application Support/UITest/.
```

- [ ] **Step 2: Record the outcome in the spec**

Append to the spec's **Testing → Manual** paragraph: date, what was verified (steps 3–5 incl. the ⌘Z/⇧⌘Z no-crash result and whether the dialog presented without the async hop being insufficient), and any deviations. If step 4 crashed: STOP — reopen the Task 2 fallback (Step 5 there) and flag for re-planning.

- [ ] **Step 3: Commit**

```bash
git add docs/superpowers/specs/2026-07-08-json-import-design.md
git commit -m "Record E-02 manual ship-gate verification outcome (E-02)"
```

---

### Task 9: Doc sync — PRD, README, CLAUDE.md

**Files:**
- Modify: `PRD-Kanban-Board-Mac.md`
- Modify: `README.md`
- Modify: `CLAUDE.md`

**Interfaces:** none — text only. Use the spec's §5 ("Model, PRD, docs") as the checklist; every item below is one of its obligations.

- [ ] **Step 1: PRD amendments** (locate by grep, not line number — the file shifts)

1. **§4.6 E-02 row** — replace the deferred row with shipped behavior: two modes ("Add to Existing" appends after existing boards; "Replace All Boards" deletes existing first, is **not undoable**, clears the undo stack, and is unavailable for zero-board backups), ⇧⌘I, hard-reject on malformed JSON/missing fields/`formatVersion != 1` (whole-file, nothing imported), gray-zone sanitization, append undo per the recorded spike outcome.
2. **§4.6 MVP-scope line** — E-01 stays; add a note that E-02 shipped post-MVP.
3. **§7 out-of-scope** — remove the single "Backup/restore — import a previously exported JSON file" row.
4. **Appendix Feature Priority Matrix** — move "E-02 Backup/restore — import exported JSON" out of the deferred P1 list (mark shipped).
5. **§4.3 shortcuts table** — add: ⇧⌘I · Import Boards… · File menu.
6. **§9 acceptance criteria** — add an E-02 block: (a) importing an exported file restores boards/lists/cards/labels/due dates/themes in order; (b) Add to Existing is one ⌘Z step (or documented non-undoable, per spike outcome); (c) Replace All deletes existing boards first, clears the undo stack, and is unavailable for empty backups; (d) an invalid file (malformed/missing fields/unsupported version) imports nothing and shows an error stating existing boards are unchanged. Plus the automation note mirroring E-01's save-panel paragraph: the NSOpenPanel leg is manually verified (Task 8); content correctness is automated via `--import-from`.

- [ ] **Step 2: README** — in the features summary, add JSON import next to JSON export (two modes, ⇧⌘I; imports live in the File menu and the zero-board empty state). The roadmap's **Trello import** entry STAYS (different feature, still deferred).

- [ ] **Step 3: CLAUDE.md** — in the "Launch paths" `--uitest` bullet, add `--export-to` (E-01 export self-check), `--import-from`/`--import-mode` (E-02 import self-check; `add|replace|ask`) to the listed flags. Add a Pitfalls entry ONLY if Task 2's spike failed or Task 8 diverged from the headless result — describe the evidence in the established style.

- [ ] **Step 4: Final full run + commit**

Run: `make test` — expected: everything PASSES.

```bash
git add PRD-Kanban-Board-Mac.md README.md CLAUDE.md
git commit -m "Sync PRD/README/CLAUDE.md for shipped JSON import (E-02)"
```
