# Checklists / Action Items (M-E) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Cards gain checklists, shipped under the user-facing name **"Action Items"** (the locked feature-review naming). A new third-level SwiftData entity (`ChecklistItem`: text, isDone, position) hangs off `Card` with a cascade delete rule; the card-detail sheet grows an "Action Items" section directly below Brief — fully **STAGED** like every other sheet field (local `@State` drafts, one `applyCardEdits` call on Save, one ⌘Z per sheet, Esc/Cancel discards); the card face's meta line gains a quiet "done/total" fraction chip (only when items exist — it takes the M-0 one-extra-slot budget, since no timer exists); and the export format bumps to **v4** with an `ExportCard.checklist` array (per-feature-bump policy). No reorder UI in v1: insertion order IS the order (position = draft index), which deliberately dodges the native-`List`-`.onMove`-untestability pitfall — reorder is a documented follow-up. But before ANY of that: this milestone opens with a **SPIKE**, because a third level of cascade graph is exactly the depth at which SwiftData's undo machinery has already failed this codebase twice (the on-disk Board-delete fatal assert; the import spike's silent third-level Card drops on redo), and `deleteCard`/`deleteList` — both currently undoable via `withUndoGroup` — will now cascade through checklist rows. The spike's evidence, not anyone's optimism, decides whether they stay undoable (maintainer's explicit instruction: "decide after the spike").

**Architecture:** Task 0 adds the entity (`Tack/Models/ChecklistItem.swift`, joining `TackSchemaV1.models` — the additive-change precedent: new table, lightweight migration, no schema version bump) and a new on-disk spike suite `TackTests/ChecklistUndoOnDiskTests.swift` mirroring `ImportUndoOnDiskTests`' structure (same private `OnDiskStore` helper shape — that struct is `private` there, so it is copied, not promoted; promotion can wait for a third user). The spike runs BOTH legs on a real sqlite store: (a) `deleteCard` of a 3-item card → undo → redo → undo, (b) `deleteList` of a list whose card carries 3 items (the exact board→list→card→item depth the import spike died at, one relationship over) → undo → redo → undo. Integrity oracles are exact COUNTS + exact text/isDone/position arrays + `persistentModelID` row identity — **never `ObjectIdentifier`** (instances refault across saves; the import spike proved ObjectIdentifier verdicts vary run-to-run) and never bare "no crash" (the known failure mode is SILENT third-level row loss). **Decision rule (written here so nobody relitigates it mid-implementation): GREEN = every assertion passes in 3/3 consecutive runs → Task 1a (deleteCard/deleteList keep their `withUndoGroup` form, zero store change, spike file stays verbatim as a regression sentinel). RED = any crash, hang (>6 min IS a hang), or assertion failure in any run → Task 1b (deleteCard AND deleteList adopt `deleteBoard`'s detach-and-clear discipline — non-undoable, stack cleared — with the PRD §4.7/U-01/C-05/L-02 rows amended and the spike file rewritten into a reduced on-disk smoke, exactly how `ImportUndoOnDiskTests` ships).** Both conditional tasks are fully coded below; exactly one runs. The store's editing surface is deliberately narrow: NO per-item live mutations exist — the sheet's Save/Cancel contract means `applyCardEdits` gains one non-defaulted `checklist: [ChecklistDraft]` parameter (a value struct: `id: UUID?` — nil = new row; the non-defaulting mirrors `includesTime`'s rationale: a defaulted `[]` would silently DELETE every item on any unrelated call site) and diffs drafts against `sortedChecklistItems` inside the same "Edit Card" undo group: match by id → text/isDone updates; ids missing from the drafts → deletes; nil-id drafts → inserts; final positions renumbered 0..<n in draft order through the existing `renumber` helper (ChecklistItem conforms to the private `PositionedEntity` protocol via an extension in `BoardStore.swift`, beside Board/BoardList/Card — the protocol stays private, so the conformance must live in that file). Whitespace-only drafts are dropped at save (the labels-filter posture: drop invalid, pass kept text through verbatim). **Fixture choice (evidence-based): the seeded checklist goes on "Return library books"** — it is the only dated Groceries card whose detail sheet NO UI test ever opens (Call plumber anchors five CardDetailUITests flows plus the calendar double-click e2e; Buy milk is renamed and dragged; Write report is the load-bearing timed card, opened by the quick-pick-reset and delete-from-detail tests; Book flights anchors the due-date and timed-toggle flows), and its face-level uses (CollapseUITests/CardCRUDUITests order scans, LabelFilter hide-assertions, BadgeUITests `|tomorrow` suffix, KeyboardShortcut moves, the ListView delete) are all id- or badge-value-based, which a fraction chip on the same meta line cannot disturb — the order scans match `BEGINSWITH "card-"` and the new id is `checklist-<title>`. One sheet-layout resolution, stated up front: the Brief editor is the sheet's ONE flexible element (maxHeight `.infinity` + `layoutPriority(1)`, floor 120pt), so an UNbounded checklist would arithmetically push Labels/Due Date off the fixed-ideal-height sheet (~190pt of rows at 5 items > the ~0pt of slack once the editor hits its floor) — therefore the section is built lean: ONE header line carrying the title, the done/total count, AND the inline "Add Item" button (so an empty checklist costs ~20pt, inside any plausible slack), with the rows in a **fixed-height, content-sized rows-only scroller capped at 4 visible rows** (plain non-lazy `ForEach` in a plain `ScrollView` — NOT a native `List`, NOT a whole-sheet scroll; with ≤4 rows nothing ever scrolls, so clicks/typing are untouched, and non-lazy means below-the-fold rows still EXIST for AX queries). The budget reasoning: with an empty Brief the editor sits well above its 120pt floor, so a ≤132pt section compresses the editor, not the pinned controls; the one uncovered combination — long Brief AND long checklist at default size — is accepted v1 (the sheet is user-resizable since M-0, that's the relief valve; human-checklist item 5 eyeballs it). `testLongChecklistKeepsDueDateHittable` extends the M-0 `dueQuickToday`-hittable oracle to pin all of this.

**Tech Stack:** SwiftUI (macOS 14), SwiftData (versioned schema), XCUITest, Swift Testing, xcodegen.

## Global Constraints

- Every bare `xcodebuild` needs `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`; `pkill -f xcodebuild; pkill -f Tack.app` before every run; FOREGROUND runs; judge only by the log tail; every `TackUITests` invocation carries `-parallel-testing-enabled NO`.
- A unit-test run past ~6 minutes is a **hang, not a slow run** (classically an NSUndoManager registration outside explicit grouping) — kill it and read the log tail for a FAULT line. **In Task 0 specifically, a hang or crash is not a broken test — it is the spike's RED verdict. Record it, don't debug it.**
- **File accounting (`Tack.xcodeproj` is generated — `make gen` REQUIRED after every file-set change):** Task 0 adds `Tack/Models/ChecklistItem.swift` and `TackTests/ChecklistUndoOnDiskTests.swift` — the ONLY two new files in the whole milestone, so `make gen` runs in Task 0 and nowhere else. `ChecklistDraft` lives in `Tack/Store/BoardStore.swift` (a store-boundary value type beside its consumer), Task 1b rewrites the spike file IN PLACE, and new `AccessibilityID` constants need no project change (that file is compiled into both the app and TackUITests targets per `project.yml`). Any other file creation means you've drifted — stop and re-read the task.
- **Signature discipline (type-consistent across all tasks):** `ChecklistDraft` is exactly `{ id: UUID?, text: String, isDone: Bool }`, `Equatable`, deliberately NOT `Identifiable` (two sheet-added rows both carry nil ids; SwiftUI row identity comes from the ForEach INDEX, stable because v1 has no reorder UI). `applyCardEdits`' new `checklist:` parameter is NOT defaulted — every call site states its checklist intent explicitly (the `includesTime` rationale: a defaulted `[]` would let a title rename silently wipe a card's items, because `[]` under diff semantics means "delete all"). AX id grammar: `checkitem-toggle-<index>` / `checkitem-text-<index>` / `checkitem-delete-<index>` / `checkitem-add` (the app's only INDEX-keyed ids — sheet rows are anonymous until saved); the card-face chip is `checklist-<title>` with wire value `"<done>/<total>"` — never `card-`-prefixed (`cardIdentifiersByPosition` counts `BEGINSWITH "card-"`).
- **Text-input pitfall surface (the milestone's biggest):** the checklist row TextFields are the first NEW text inputs since M-A. Every one of them MUST call `.reportsTextInputFocus()` (or menu shortcuts — ⌘⌫ included — fire while the user types an item), and NO `.focused()` bindings anywhere (the launch-focus pitfall: FocusState bindings bridge AppKit focus into SwiftUI and killed the whole keyboard command surface once already). "Add Item" therefore does NOT auto-focus the new row — the user clicks into it (accepted v1, documented in code).
- **No native `List` inside the sheet** (nested-scroll + `.onMove` pitfalls): the rows are a plain `ForEach`, wrapped only in the fixed-height rows scroller described in Architecture. No whole-sheet `ScrollView` either — `testLongBriefScrollsInsideEditorNotSheet` pins that from M-0.
- **The fixture roster is load-bearing and this milestone touches exactly ONE card of it:** "Return library books" gains 3 checklist items (2 done). Card TITLES, list membership, dates, and labels are all UNCHANGED, so every title-keyed assertion across the 74 UI tests holds; the only new face element is the fraction chip on an EXISTING meta line (the card already has a badge), so row heights and drag geometry are undisturbed. Do not seed items on any other card.
- The spike file uses the on-disk container shape of `ImportUndoOnDiskTests` EXACTLY (sqlite under a unique temp dir, `UndoManager` with `groupsByEvent = false`, best-effort tearDown) — copied, since that helper is `private` to its file.
- The environmental keyboard/menu UI-test failure mode can be active on this host. Keyboard/menu-gated suites (`KeyboardShortcutUITests`, `LabelFilterUITests`) are NOT gates for this plan; the gates are the unit suite + the mouse-driven suites (CardDetailUITests, BadgeUITests, ListViewUITests, CalendarViewUITests, DragAndDropUITests). Before debugging any red keyboard-driven test, control-run it against committed (known-green) code — if the control fails, it's the environment.
- Commit style: short imperative summary, body optional, `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>` trailer.

---

### Task 0: SPIKE — `ChecklistItem` entity + on-disk cascade-undo evidence (decides Task 1a vs 1b)

**Files:**
- Create: `Tack/Models/ChecklistItem.swift`
- Modify: `Tack/Models/Card.swift` (cascade relationship + `sortedChecklistItems`)
- Modify: `Tack/Models/TackSchema.swift` (entity joins `TackSchemaV1.models`)
- Create: `TackTests/ChecklistUndoOnDiskTests.swift`
- `make gen` (the milestone's only file-set change).

One deliberate sequencing note: the coordinator's task sketch placed the model in Task 1, but the spike physically cannot insert third-level rows of an entity that doesn't exist, and a test-local `@Model` would not exercise the real schema/cascade — so the model lands HERE, minimal, and Task 1 adds its store surface. (The import spike likewise ran against the real, already-shipped DTO types.)

**Interfaces:**
- Consumes: `TackSchemaV1` (versioned schema), `BoardStore.deleteCard`/`.deleteList` in their CURRENT `withUndoGroup` form (that form is what's on trial), `ModelContainer`/`ModelContext` on-disk.
- Produces: `ChecklistItem` (`id`/`text`/`isDone`/`position`/`card`), `Card.checklistItems` + `Card.sortedChecklistItems`, and the spike verdict that selects Task 1a or 1b. Adding the entity is compile-safe everywhere: `Card.init`'s new parameter is defaulted, so `FixtureSeeder`, `materialize`, and every test construction site compile unchanged.

- [ ] **Step 1: The model**

Create `Tack/Models/ChecklistItem.swift`:

```swift
import Foundation
import SwiftData

/// M-E: one checklist row (user-facing name: "Action Item") of a card — the model graph's third
/// cascade level (Board → BoardList → Card → ChecklistItem). `position` is the row's order within
/// its card, contiguous 0..<n, maintained by `BoardStore.applyCardEdits`' checklist diff (v1 has
/// no reorder UI: insertion order IS the order). Additive entity in TackSchemaV1 — a new table is
/// a lightweight migration, the same no-version-bump posture as the additive optional fields
/// (`durationMinutes`/`about`); an M-E store opened by an older build simply ignores the table.
@Model
final class ChecklistItem {
    @Attribute(.unique) var id: UUID
    var text: String
    var isDone: Bool
    var position: Int
    var card: Card?

    init(
        id: UUID = UUID(),
        text: String,
        isDone: Bool = false,
        position: Int,
        card: Card? = nil
    ) {
        self.id = id
        self.text = text
        self.isDone = isDone
        self.position = position
        self.card = card
    }
}
```

`Tack/Models/Card.swift` — after the `labels` relationship, add:

```swift
    /// M-E: checklist ("Action Items") rows. Cascade like Board.lists/BoardList.cards; the
    /// inverse is declared here only (ChecklistItem.card is a plain optional, the Card.list shape).
    @Relationship(deleteRule: .cascade, inverse: \ChecklistItem.card)
    var checklistItems: [ChecklistItem]
```

Extend `Card.init` with a trailing defaulted parameter `checklistItems: [ChecklistItem] = []` (assign `self.checklistItems = checklistItems`), and add below the class's stored properties, mirroring `Board.sortedLists`/`BoardList.sortedCards`:

```swift
    var sortedChecklistItems: [ChecklistItem] { checklistItems.sorted { $0.position < $1.position } }
```

`Tack/Models/TackSchema.swift` — the models array becomes:

```swift
        [Board.self, BoardList.self, Card.self, CardLabel.self, ChecklistItem.self]
```

- [ ] **Step 2: The spike suite**

Create `TackTests/ChecklistUndoOnDiskTests.swift`:

```swift
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
```

- [ ] **Step 3: Run the spike — three times**

```bash
pkill -f xcodebuild; pkill -f Tack.app
make gen
for i in 1 2 3; do
  pkill -f xcodebuild; pkill -f Tack.app
  DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project Tack.xcodeproj -scheme Tack \
    -destination "platform=macOS,arch=$(uname -m)" -derivedDataPath .build/DerivedData \
    -only-testing:TackTests/ChecklistUndoOnDiskTests test 2>&1 | tee .build/me-task0-spike-$i.log
done
```

Read every log to completion. A run stuck past ~6 minutes: kill both processes, read the tail for a FAULT/EXC_BREAKPOINT line — **that is a RED verdict, recorded, not a problem to fix.** Do NOT weaken assertions, add detach calls, or "stabilize" anything to get green: the spike measures the machinery as it stands.

- [ ] **Step 4: Record the verdict (this block is the ledger — the M-E analog of the import spec's "Spike outcome" block)**

Fill in, in THIS file:

> **Spike outcome (2026-07-09): RED** — runs: 0 / 3 passing.
> Evidence: `.build/me-task0-spike-{1,2,3}.log` — both legs crashed in all 3 runs with `SwiftData/ModelSnapshot.swift:46: Fatal error: Unexpected backing data for snapshot creation: SwiftData._FullFutureBackingData<Tack.ChecklistItem>` (leg A, all 3 runs) / `<...Tack.Card>` or `<...Tack.ChecklistItem>` (leg B, varies by run) — the crash fires immediately inside `deleteCard`/`deleteList`'s own `withUndoGroup` (undo-snapshot creation of the cascade-deleted rows), before `undoManager.undo()` is ever called.
> Consequence: Task 1b runs; Task 1a is checked off as `(skipped — spike verdict)`.

- [ ] **Step 5: Full unit suite** — `pkill -f xcodebuild; pkill -f Tack.app; make unit 2>&1 | tee .build/me-task0-unit.log` → `** TEST SUCCEEDED **` (the schema addition must not disturb any existing suite; `Card.init`'s defaulted parameter keeps every construction site compiling). If the spike itself is RED, run the rest of the suite with `-skip-testing:TackTests/ChecklistUndoOnDiskTests` for THIS gate only — Task 1b rewrites the file before the next full-suite gate.

- [ ] **Step 6: Commit**

```bash
git add Tack/Models/ChecklistItem.swift Tack/Models/Card.swift Tack/Models/TackSchema.swift TackTests/ChecklistUndoOnDiskTests.swift docs/superpowers/plans/2026-07-09-checklists.md
git commit -m "ChecklistItem entity + on-disk cascade-undo spike (M-E Task 0)

Third-level cascade entity (Card -> ChecklistItem, additive in
TackSchemaV1). Spike probes whether deleteCard/deleteList survive
undo/redo now that they cascade through checklist rows — exact-count +
persistentModelID oracles, never ObjectIdentifier (the import-spike
lesson). Verdict recorded in the M-E plan's ledger block; it selects
Task 1a (stay undoable) or 1b (deleteBoard detach discipline).

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 1: `ChecklistDraft` + `applyCardEdits` checklist diffing (unit TDD — runs regardless of verdict)

**Files:**
- Modify: `Tack/Store/BoardStore.swift` (`ChecklistDraft`, `PositionedEntity` conformance, `applyCardEdits` diff)
- Modify: `Tack/Views/CardDetail/CardDetailView.swift` (ONE line: the compile bridge — see Interfaces)
- Test (modify): `TackTests/BoardStoreCardTests.swift` (new checklist tests + mechanical `checklist:` on existing calls)
- Test (modify): `TackTests/BoardStoreImportTests.swift` (ONE mechanical `checklist:` addition, line ~239)
- Test (modify): `TackTests/CascadeDeleteTests.swift` (two in-memory cascade tests)

No new files → no `make gen`.

**Interfaces:**
- Consumes: `ChecklistItem`/`Card.sortedChecklistItems` (Task 0), `withUndoGroup`, `renumber` (via the new `PositionedEntity` conformance), the `editBoard`/`applyCardEdits` no-change-no-group discipline.
- Produces: `ChecklistDraft` + `ChecklistDraft.drafts(of:)` (consumed by Task 2's seeder and Task 3's staged `@State`); `applyCardEdits(..., checklist:)`. Because the parameter is non-defaulted, `CardDetailView.save()` must compile NOW: it passes `checklist: ChecklistDraft.drafts(of: card)` — an identity diff, honest (the sheet can't edit items until Task 3, which swaps this for the staged drafts).

- [ ] **Step 1: Write the failing tests**

Mechanical sweep first: `grep -rn "applyCardEdits" TackTests Tack` — every existing call gains a `checklist:` argument. Test calls on cards with no items pass `checklist: []` (an empty diff against an empty checklist = no change); `BoardStoreImportTests`' one call (~line 239) likewise. This keeps every pre-existing test's meaning byte-identical.

Append to `TackTests/BoardStoreCardTests.swift` (below the applyCardEdits section):

```swift
    // MARK: - applyCardEdits checklist (M-E)

    private func drafts(_ card: Card) -> [ChecklistDraft] { ChecklistDraft.drafts(of: card) }

    @Test("nil-id drafts insert in draft order with positions 0..<n")
    func checklistInsertsInDraftOrder() {
        let env = TestContainer()
        let board = env.store.createBoard(name: "B", emoji: nil)
        let card = env.store.addCard(to: board.sortedLists[0], title: "Card")

        env.store.applyCardEdits(card, title: card.title, details: card.details, labels: [],
                                 dueDate: nil, includesTime: false, durationMinutes: nil,
                                 checklist: [
                                     ChecklistDraft(id: nil, text: "One", isDone: false),
                                     ChecklistDraft(id: nil, text: "Two", isDone: true),
                                 ])

        let items = card.sortedChecklistItems
        #expect(items.map(\.text) == ["One", "Two"])
        #expect(items.map(\.isDone) == [false, true])
        #expect(items.map(\.position) == [0, 1])
    }

    @Test("id-matched drafts update text/isDone IN PLACE — same row, not delete+recreate")
    func checklistUpdatesMatchByID() {
        let env = TestContainer()
        let board = env.store.createBoard(name: "B", emoji: nil)
        let card = env.store.addCard(to: board.sortedLists[0], title: "Card")
        env.store.applyCardEdits(card, title: card.title, details: card.details, labels: [],
                                 dueDate: nil, includesTime: false, durationMinutes: nil,
                                 checklist: [ChecklistDraft(id: nil, text: "One", isDone: false)])
        let originalPersistentID = card.sortedChecklistItems[0].persistentModelID

        var edited = drafts(card)
        edited[0].text = "One, renamed"
        edited[0].isDone = true
        env.store.applyCardEdits(card, title: card.title, details: card.details, labels: [],
                                 dueDate: nil, includesTime: false, durationMinutes: nil,
                                 checklist: edited)

        let item = card.sortedChecklistItems[0]
        #expect(item.text == "One, renamed")
        #expect(item.isDone == true)
        // persistentModelID, never ObjectIdentifier — the spike/import identity-oracle rule.
        #expect(item.persistentModelID == originalPersistentID,
                "an id-matched draft must update the row, not replace it")
    }

    @Test("ids missing from the drafts delete their rows; survivors renumber to 0..<n")
    func checklistMissingIDsDelete() {
        let env = TestContainer()
        let board = env.store.createBoard(name: "B", emoji: nil)
        let card = env.store.addCard(to: board.sortedLists[0], title: "Card")
        env.store.applyCardEdits(card, title: card.title, details: card.details, labels: [],
                                 dueDate: nil, includesTime: false, durationMinutes: nil,
                                 checklist: ["One", "Two", "Three"].map { ChecklistDraft(id: nil, text: $0, isDone: false) })

        var remaining = drafts(card)
        remaining.remove(at: 0) // drop "One"
        env.store.applyCardEdits(card, title: card.title, details: card.details, labels: [],
                                 dueDate: nil, includesTime: false, durationMinutes: nil,
                                 checklist: remaining)

        #expect(card.sortedChecklistItems.map(\.text) == ["Two", "Three"])
        #expect(card.sortedChecklistItems.map(\.position) == [0, 1], "survivors renumbered")
        let allItems = (try? env.context.fetch(FetchDescriptor<ChecklistItem>())) ?? []
        #expect(allItems.count == 2, "the deleted row is gone from the store, not just the card")
    }

    @Test("whitespace-only drafts are dropped at save; kept text passes through verbatim")
    func checklistWhitespaceOnlyDraftsDropped() {
        let env = TestContainer()
        let board = env.store.createBoard(name: "B", emoji: nil)
        let card = env.store.addCard(to: board.sortedLists[0], title: "Card")

        env.store.applyCardEdits(card, title: card.title, details: card.details, labels: [],
                                 dueDate: nil, includesTime: false, durationMinutes: nil,
                                 checklist: [
                                     ChecklistDraft(id: nil, text: "  Keep me  ", isDone: false),
                                     ChecklistDraft(id: nil, text: "   ", isDone: false),
                                     ChecklistDraft(id: nil, text: "", isDone: true),
                                 ])

        #expect(card.sortedChecklistItems.map(\.text) == ["  Keep me  "],
                "drop whitespace-only, pass kept text through untrimmed (the labels-filter posture)")
        #expect(card.sortedChecklistItems.map(\.position) == [0])
    }

    @Test("round-tripped drafts + unchanged fields register no undo step and keep updatedAt")
    func checklistIdentityIsNoOp() {
        let env = TestContainer(withUndo: true)
        let board = env.store.createBoard(name: "B", emoji: nil)
        let card = env.store.addCard(to: board.sortedLists[0], title: "Card")
        env.store.applyCardEdits(card, title: card.title, details: card.details, labels: [],
                                 dueDate: nil, includesTime: false, durationMinutes: nil,
                                 checklist: [ChecklistDraft(id: nil, text: "One", isDone: true)])
        env.undoManager?.removeAllActions()
        let stamp = card.updatedAt

        env.store.applyCardEdits(card, title: card.title, details: card.details, labels: [],
                                 dueDate: nil, includesTime: false, durationMinutes: nil,
                                 checklist: drafts(card))

        #expect(env.undoManager?.canUndo == false, "an identity checklist must not be 'a change'")
        #expect(card.updatedAt == stamp)
    }

    @Test("a checklist edit (insert+update+delete) is ONE undo step; undo restores exactly, redo reapplies")
    func checklistEditIsOneUndoStep() {
        let env = TestContainer(withUndo: true)
        let board = env.store.createBoard(name: "B", emoji: nil)
        let card = env.store.addCard(to: board.sortedLists[0], title: "Card")
        env.store.applyCardEdits(card, title: card.title, details: card.details, labels: [],
                                 dueDate: nil, includesTime: false, durationMinutes: nil,
                                 checklist: [
                                     ChecklistDraft(id: nil, text: "One", isDone: false),
                                     ChecklistDraft(id: nil, text: "Two", isDone: false),
                                 ])
        env.undoManager?.removeAllActions()

        var edited = drafts(card)
        edited[0].isDone = true                                        // update
        edited.remove(at: 1)                                           // delete "Two"
        edited.append(ChecklistDraft(id: nil, text: "Three", isDone: false)) // insert
        env.store.applyCardEdits(card, title: card.title, details: card.details, labels: [],
                                 dueDate: nil, includesTime: false, durationMinutes: nil,
                                 checklist: edited)
        #expect(card.sortedChecklistItems.map(\.text) == ["One", "Three"])

        env.undoManager?.undo()
        #expect(card.sortedChecklistItems.map(\.text) == ["One", "Two"],
                "one ⌘Z reverses the whole staged checklist edit")
        #expect(card.sortedChecklistItems.map(\.isDone) == [false, false])
        #expect(env.undoManager?.canUndo == false, "exactly one step")

        // Redo of item-level inserts under one EXISTING card is a single-parent-level re-insert —
        // the shape createBoard's redo (board + lists) already proves safe. This is NOT the
        // spike's multi-level-cascade question. If this line ever crashes or loses rows, that is
        // spike-class evidence: STOP and re-open the Task 0 verdict — do not weaken the test.
        env.undoManager?.redo()
        #expect(card.sortedChecklistItems.map(\.text) == ["One", "Three"])
        #expect(card.sortedChecklistItems.map(\.isDone) == [true, false])
    }
```

Append to `TackTests/CascadeDeleteTests.swift` (same suite, same style as its neighbors):

```swift
    @Test("deleteCard cascades to its checklist items (M-E)")
    func deleteCardCascadesToChecklistItems() {
        let env = TestContainer()
        let board = env.store.createBoard(name: "B", emoji: nil)
        let card = env.store.addCard(to: board.sortedLists[0], title: "Card")
        env.store.applyCardEdits(card, title: card.title, details: card.details, labels: [],
                                 dueDate: nil, includesTime: false, durationMinutes: nil,
                                 checklist: [ChecklistDraft(id: nil, text: "One", isDone: false),
                                             ChecklistDraft(id: nil, text: "Two", isDone: true)])

        env.store.deleteCard(card)

        let items = (try? env.context.fetch(FetchDescriptor<ChecklistItem>())) ?? []
        #expect(items.isEmpty, "no orphaned checklist rows after a card delete")
    }

    @Test("deleteList cascades through cards to checklist items (M-E)")
    func deleteListCascadesThroughCardsToChecklistItems() {
        let env = TestContainer()
        let board = env.store.createBoard(name: "B", emoji: nil)
        let list = board.sortedLists[0]
        let card = env.store.addCard(to: list, title: "Card")
        env.store.applyCardEdits(card, title: card.title, details: card.details, labels: [],
                                 dueDate: nil, includesTime: false, durationMinutes: nil,
                                 checklist: [ChecklistDraft(id: nil, text: "One", isDone: false)])

        env.store.deleteList(list)

        let items = (try? env.context.fetch(FetchDescriptor<ChecklistItem>())) ?? []
        #expect(items.isEmpty, "no orphaned checklist rows after a list delete")
    }
```

- [ ] **Step 2: Run to verify failure**

```bash
pkill -f xcodebuild; pkill -f Tack.app
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild -project Tack.xcodeproj -scheme Tack \
  -destination "platform=macOS,arch=$(uname -m)" -derivedDataPath .build/DerivedData \
  -only-testing:TackTests/BoardStoreCardTests -only-testing:TackTests/CascadeDeleteTests \
  test 2>&1 | tee .build/me-task1-red.log
```
Expected: compile FAILURE (`ChecklistDraft` and the `checklist:` parameter don't exist) — the red state.

- [ ] **Step 3: Implement**

`Tack/Store/BoardStore.swift`. First, beside the existing conformances at the top of the file:

```swift
extension ChecklistItem: PositionedEntity {}
```

(The protocol stays `private` — that is WHY this conformance lives here, next to Board/BoardList/Card's, and not in the model file.)

Below the `PositionedEntity` conformances (above the `BoardStore` class), the draft type:

```swift
/// M-E: one staged checklist row of the card-detail sheet — a plain value the view stages and
/// `applyCardEdits` diffs against the persisted rows. `id` is the persisted `ChecklistItem.id`
/// when the draft mirrors an existing row; nil marks a row added in the sheet this session
/// (=> insert). Deliberately NOT Identifiable: two new rows both carry nil, so SwiftUI row
/// identity comes from the ForEach INDEX at the view site — stable, because v1 has no reorder UI.
struct ChecklistDraft: Equatable {
    var id: UUID?
    var text: String
    var isDone: Bool
}

extension ChecklistDraft {
    /// The card's persisted checklist as drafts, in position order — the seed for
    /// `CardDetailView`'s staged @State and the identity payload for call sites that don't edit
    /// the checklist (an identity array diffs to "no change").
    @MainActor
    static func drafts(of card: Card) -> [ChecklistDraft] {
        card.sortedChecklistItems.map { ChecklistDraft(id: $0.id, text: $0.text, isDone: $0.isDone) }
    }
}
```

Then `applyCardEdits` — signature + diff (the doc comment gains two sentences; the existing normalization/label logic is UNTOUCHED):

```swift
    /// [existing doc comment, unchanged, then:]
    /// M-E: `checklist` is the sheet's staged Action Items, diffed against the persisted rows
    /// inside the SAME "Edit Card" group (id-matched → in-place update; missing ids → deletes;
    /// nil ids → inserts; positions renumbered 0..<n in draft order — insertion order IS the
    /// order, v1 has no reorder UI). Whitespace-only drafts are dropped here, the save-time
    /// backstop (the labels-filter posture: drop invalid, pass kept text through verbatim).
    /// Deliberately NOT defaulted, same reason as `includesTime`: a defaulted `[]` means
    /// "delete every item" under diff semantics, so any unrelated call site would silently
    /// wipe the card's checklist.
    func applyCardEdits(_ card: Card, title: String, details: String?, labels: Set<LabelColor>,
                        dueDate: Date?, includesTime: Bool, durationMinutes: Int?,
                        checklist: [ChecklistDraft]) {
```

Inside, after the `labelsChanged` computation, add:

```swift
        let keptDrafts = checklist.filter {
            !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        let checklistChanged = keptDrafts != ChecklistDraft.drafts(of: card)
```

The whole-call guard becomes:

```swift
        guard titleChanged || detailsChanged || dueDateChanged || timeChanged || labelsChanged
                || checklistChanged else { return }
```

And inside the `withUndoGroup("Edit Card")` body, after the `labelsChanged` block (before the `updatedAt` bump):

```swift
            if checklistChanged {
                let existingByID = Dictionary(uniqueKeysWithValues: card.sortedChecklistItems.map { ($0.id, $0) })
                let keptIDs = Set(keptDrafts.compactMap(\.id))
                // Deletes are computed from the PRE-delete array (the deleteCard survivors
                // precedent: relationship arrays don't drop deleted objects until save).
                for item in card.sortedChecklistItems where !keptIDs.contains(item.id) {
                    context.delete(item)
                }
                var finalItems: [ChecklistItem] = []
                for draft in keptDrafts {
                    if let id = draft.id, let item = existingByID[id] {
                        if item.text != draft.text { item.text = draft.text }
                        if item.isDone != draft.isDone { item.isDone = draft.isDone }
                        finalItems.append(item)
                    } else {
                        // nil id (a sheet-added row) — or an id that no longer resolves (can't
                        // happen single-user, but total behavior beats a trap): insert fresh.
                        let item = ChecklistItem(text: draft.text, isDone: draft.isDone,
                                                 position: finalItems.count, card: card)
                        context.insert(item)
                        finalItems.append(item)
                    }
                }
                renumber(finalItems) // contiguous 0..<n in draft order — the shared invariant
            }
```

`Tack/Views/CardDetail/CardDetailView.swift` — `save()`'s call gains the Task-1 compile bridge:

```swift
            durationMinutes: durationMinutes,
            // M-E Task 1 bridge: identity payload (no sheet UI for items yet — Task 3 swaps this
            // for the staged checklistDrafts). An identity array diffs to "no checklist change".
            checklist: ChecklistDraft.drafts(of: card)
```

- [ ] **Step 4: Run to verify pass** — same command as Step 2, log `.build/me-task1-green.log`. Expected: `** TEST SUCCEEDED **` — 6 new checklist tests + 2 cascade tests + every pre-existing applyCardEdits test still green under the mechanical `checklist: []`.

- [ ] **Step 5: Full unit suite + build** — `make unit` then `make build`, logs `.build/me-task1-unit.log` / `.build/me-task1-build.log`, both green (the build gate proves `CardDetailView`'s bridge compiles).

- [ ] **Step 6: Commit**

```bash
git add Tack/Store/BoardStore.swift Tack/Views/CardDetail/CardDetailView.swift TackTests/BoardStoreCardTests.swift TackTests/BoardStoreImportTests.swift TackTests/CascadeDeleteTests.swift
git commit -m "applyCardEdits gains staged checklist diffing (M-E)

ChecklistDraft (id/text/isDone; nil id = new row) diffs against
sortedChecklistItems inside the one Edit Card undo group: id-matched
in-place updates, missing-id deletes, nil-id inserts, positions
renumbered 0..<n in draft order (no reorder UI in v1). Whitespace-only
drafts dropped at save. Parameter deliberately non-defaulted — [] means
'delete all' under diff semantics. CardDetailView passes an identity
payload until Task 3 stages real drafts.

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 1a — RUN ONLY IF THE SPIKE IS GREEN: deletes stay undoable; spike becomes the standing sentinel

**Files:**
- Modify: `Tack/Store/BoardStore.swift` (doc comments ONLY — zero behavior change)
- Modify: `TackTests/ChecklistUndoOnDiskTests.swift` (doc comment: spike → sentinel)

- [ ] **Step 1:** `BoardStore.deleteCard` and `deleteList` keep their `withUndoGroup` bodies UNTOUCHED. Append one sentence to each doc comment:

```swift
    /// M-E spike (ChecklistUndoOnDiskTests, 3/3 on-disk runs green): undo/redo of this delete
    /// remains integrity-safe with the third-level ChecklistItem cascade underneath — the suite
    /// stays in the repo as the regression sentinel for exactly this claim.
```

Also update `deleteBoard`'s evidence block's sentence "`deleteList` and `deleteCard` are empirically green with the manager attached" to append "(re-verified at three cascade levels by the M-E spike, `ChecklistUndoOnDiskTests`)".

- [ ] **Step 2:** In `ChecklistUndoOnDiskTests`' type doc, replace the "VERDICT PROTOCOL" paragraph with:

```swift
/// VERDICT (2026-07-__, recorded in the M-E plan's ledger): GREEN, 3/3 runs — deleteCard and
/// deleteList KEEP their withUndoGroup form. This suite now stands as the permanent regression
/// sentinel: if SwiftData's cascade-undo behavior regresses (an OS update is the likely vector),
/// these two tests are designed to catch the silent-row-loss mode before any user does.
```

- [ ] **Step 3:** Gates: `make unit` (log `.build/me-task1a-unit.log`) → green, spike suite included this time. Commit:

```bash
git add Tack/Store/BoardStore.swift TackTests/ChecklistUndoOnDiskTests.swift
git commit -m "Spike verdict GREEN: card/list deletes stay undoable over checklist cascades (M-E)

Zero store change — doc comments record the on-disk 3/3 evidence and
ChecklistUndoOnDiskTests is promoted from spike to standing regression
sentinel for the three-level cascade undo/redo integrity claim.

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 1b — RUN ONLY IF THE SPIKE IS RED: deletes adopt the detach-and-clear discipline

**Files:**
- Modify: `Tack/Store/BoardStore.swift` (`deleteCard` + `deleteList` rewritten)
- Modify: `TackTests/ChecklistUndoOnDiskTests.swift` (rewritten to the reduced on-disk smoke — the `ImportUndoOnDiskTests` final form)
- Modify: `TackUITests/KeyboardShortcutUITests.swift` (`testCmdDeleteThenUndoRedo` rewritten)
- Modify: `Tack/Commands/FocusedValues.swift`, `Tack/Views/Board/CardView.swift`, `Tack/Views/CardDetail/CardDetailView.swift` (comment sweeps: "(undoable)" claims)
- Modify: `PRD-Kanban-Board-Mac.md` (C-05, L-02, U-01, §4.7, §6, §9, Appendix)
- Modify: `CLAUDE.md` (extend the board-delete pitfall bullet)

- [ ] **Step 1: Store — both deletes get `deleteBoard`'s discipline verbatim**

```swift
    /// Renumbers survivors to 0..<n. NOT undoable since M-E — the checklist spike
    /// (ChecklistUndoOnDiskTests, Task 0 ledger in the M-E plan) showed SwiftData's undo of this
    /// delete's now-three-level cascade (card → checklist items) violating integrity on-disk
    /// [cite the recorded failure: crash frame or silent-row-loss assertion]. Mitigation is
    /// deleteBoard's shape-independent detach-and-clear, verbatim: manager detached for the span
    /// (the crashing/lossy registration is never created), stack cleared in the defer (earlier
    /// groups reference the deleted rows — undoing them post-delete would mutate dead objects).
    /// PRD C-05/U-01 amended accordingly. Don't "fix" this by restoring withUndoGroup.
    func deleteCard(_ card: Card) {
        let held = context.undoManager
        context.undoManager = nil
        defer {
            context.undoManager = held
            held?.removeAllActions()
        }
        // Compute survivors BEFORE deleting: `list.cards` does not drop the deleted object
        // until the context is saved (unchanged from the undoable-era comment).
        let survivors = card.list?.sortedCards.filter { $0.id != card.id } ?? []
        context.delete(card)
        renumber(survivors)
        save()
    }
```

`deleteList` — identical transformation (same doc comment adapted; survivors line reads `list.board?.sortedLists...` as today; `renumber(survivors)` and `save()` inside the detached span).

- [ ] **Step 2: Rewrite the spike file into the reduced sentinel** (whole-file replacement — keep `OnDiskStore` and `seed` verbatim, replace the two tests):

```swift
/// M-E on-disk smoke — the reduced form of the plan's spike suite. THE SPIKE GATE RESOLVED (RED)
/// ON-DISK during Task 0: [one sentence: the recorded failure]. deleteCard/deleteList therefore
/// ship NON-undoable via the deleteBoard detach pattern (see the M-E plan's ledger block).
///
/// What this suite still pins, on a REAL sqlite store: both deletes cascade completely (no
/// orphaned checklist rows), renumber survivors, complete the detach discipline (manager
/// reattached, stack clear, no assert/hang), and persist — the ImportUndoOnDiskTests posture.

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
```

- [ ] **Step 3: `KeyboardShortcutUITests`** — `testCmdDeleteThenUndoRedo` becomes `testCmdDeleteIsImmediateAndNotUndoable`: keep the selection + ⌘⌫ + no-dialog assertions verbatim, then REPLACE the undo half:

```swift
        // M-E: card delete is NOT undoable (spike-forced, the deleteBoard discipline — see
        // BoardStore.deleteCard). The delete must clear the undo stack outright.
        openMenu("Edit")
        let undo = menuItem("Undo")
        XCTAssertTrue(undo.waitForExistence(timeout: timeout), "Edit ▸ Undo should exist")
        XCTAssertFalse(undo.isEnabled, "Undo must be DISABLED after a card delete (stack cleared)")
        closeMenu()

        app.typeKey("z", modifierFlags: .command)
        XCTAssertFalse(anyCard("Book flights").waitForExistence(timeout: 3),
                       "⌘Z after a card delete must do nothing — the card stays deleted")
```

(This suite is in the environmentally-red keyboard class — it is NOT a gate; it must compile now and pass in the next fresh login session.)

- [ ] **Step 4: Comment sweep** — update the three "(undoable)" claims to "(NOT undoable since M-E — see BoardStore.deleteCard)": `FocusedValues.swift`'s `deleteSelectedCard` doc, `CardView.swift`'s context-menu delete comment ("PRD v1.1 C-05: undoable via the store, Finder ⌘⌫ pattern" → cite the amended C-05), `CardDetailView.swift`'s footer delete comment. Verify with `grep -rn "undoable" Tack/` that no stale claim survives.

- [ ] **Step 5: PRD amendments** (grep `undoable` across the file afterwards to catch stragglers). Exact replacements:

- §4.3 C-05 row → `| C-05 | Delete card (no confirmation; NOT undoable since M-E) | P0 | \`⌘⌫\` deletes the focused/selected card immediately with **no confirmation dialog** (Finder \`⌘⌫\` pattern). **Not undoable since M-E** — the checklist cascade spike showed SwiftData's undo of a card delete violating integrity once cards carry checklist items (see §4.7, U-01), so card delete now uses the board-delete detach discipline. Follow-up: a confirmation dialog or soft-delete should replace the lost safety net (see §7 soft-delete row) |`
- §4.2 L-02 row → `| L-02 | Rename / delete lists | P0 | Delete requires confirmation (cards may exist); **not undoable since M-E** (same spike-forced detach discipline as board delete — see §4.7, U-01); rename remains undoable |`
- §4.7 intro paragraph + U-01 row: change "The sole exception is **board deletion**" to name all three deletes (board/list/card), citing the M-E spike beside the existing board-delete evidence, and note the undo stack CLEARS on any delete.
- §6 (~line 326) sentence and §9's L-02/C-05/U-01 acceptance bullets (~lines 388/397/422): rewrite the delete-undo claims to match (C-05's acceptance becomes "…the card is removed immediately; ⌘Z does NOT restore it — deletion is permanent and the undo history is cleared").
- Appendix P0 bullets (~452/458): `L-02 Rename/delete list (confirm; not undoable — see §4.7)`, `C-05 Delete card (no confirmation; not undoable — see §4.7)`.

- [ ] **Step 6: CLAUDE.md** — extend the "Board delete is not undoable" pitfall bullet: "M-E extended this to **card and list deletes** (checklist-cascade spike, `ChecklistUndoOnDiskTests`): all three deletes use the detach-and-clear discipline. Don't 're-enable' undo on any of them."

- [ ] **Step 7: Gates + commit** — `make unit` (spike smoke included) + `make build`, logs `.build/me-task1b-*.log`, green. Commit:

```bash
git add Tack/Store/BoardStore.swift TackTests/ChecklistUndoOnDiskTests.swift TackUITests/KeyboardShortcutUITests.swift Tack/Commands/FocusedValues.swift Tack/Views/Board/CardView.swift Tack/Views/CardDetail/CardDetailView.swift PRD-Kanban-Board-Mac.md CLAUDE.md
git commit -m "Spike verdict RED: card/list deletes adopt the detach-and-clear discipline (M-E)

ChecklistUndoOnDiskTests showed SwiftData undo violating integrity on
the three-level delete cascade (see the M-E plan ledger). deleteCard and
deleteList now mirror deleteBoard: manager detached for the span, stack
cleared in a defer. Spike file reduced to the on-disk smoke sentinel
(the ImportUndoOnDiskTests posture); PRD C-05/L-02/U-01/§4.7 amended;
keyboard e2e now asserts the delete is NOT undoable.

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 2: Fixture checklist + export formatVersion 4 (unit TDD)

**Files:**
- Modify: `Tack/Store/FixtureSeeder.swift` (3 items on Return library books)
- Modify: `Tack/Export/ExportDocument.swift` (v4: `ExportChecklistItem`, `ExportCard.checklist`, sanitizer, version doc)
- Modify: `Tack/Store/BoardStore.swift` (`materialize` creates items)
- Test (modify): `TackTests/FixtureSeederTests.swift`, `TackTests/ExportDocumentTests.swift`, `TackTests/ImportDecodeTests.swift`, `TackTests/BoardStoreImportTests.swift`

No new files → no `make gen`.

**Interfaces:**
- Consumes: `ChecklistItem`/`ChecklistDraft`/`applyCardEdits(checklist:)` (Tasks 0–1).
- Produces: the seeded fixture card (consumed by Task 3's face assertion + FixtureSeederTests), `ExportDocument.formatVersion == 4`, `ExportChecklistItem`, the import gate `1...4`. One decoding-shape decision, resolved here because the coordinator's sketch ("defaulted `[]`") would be a latent bug: **synthesized Codable throws `keyNotFound` for a missing key on a NON-optional array — property defaults don't apply to decoding.** The only shape that makes v1–v3 files decode is the `about`/`durationMinutes` OPTIONAL precedent: `var checklist: [ExportChecklistItem]? = nil`. The exporter always writes the key (empty array for checklist-less cards, keeping encoding deterministic and the byte-equality property intact); old files decode `nil`; `materialize` reads `?? []`; the sanitizer maps arrays and leaves `nil` alone (idempotent). `ImportUndoOnDiskTests`/`BoardStoreImportTests`' existing `ExportCard(...)` constructions compile unchanged via the nil default.

- [ ] **Step 1: Write the failing tests**

`TackTests/FixtureSeederTests.swift` — append:

```swift
    @Test("M-E: Return library books carries the fixture checklist — 3 items, 2 done, positions 0..<3; no other card has items")
    func checklistOnReturnLibraryBooks() {
        let env = TestContainer()
        FixtureSeeder.seed("standard", context: env.context)

        let groceries = fetchBoards(env.context)[0]
        let returnBooks = card("Return library books", in: groceries.sortedLists[0])
        let items = returnBooks?.sortedChecklistItems ?? []
        #expect(items.map(\.text) == ["Renew library card", "Gather books from car", "Pay late fee"])
        #expect(items.map(\.isDone) == [true, true, false], "face fraction reads 2/3")
        #expect(items.map(\.position) == [0, 1, 2])

        let allCards = groceries.sortedLists.flatMap(\.sortedCards)
        for c in allCards where c.title != "Return library books" {
            #expect(c.checklistItems.isEmpty, "\(c.title) must stay checklist-free — the roster is load-bearing")
        }
    }
```

`TackTests/ExportDocumentTests.swift`:
- `formatVersionIsThree` → rename `formatVersionIsFour`, title `"formatVersion is 4 and present in the encoded JSON"`, both `#expect`s to `4`; `emptyStoreExportsZeroBoards`' trailing expect to `4`.
- Append inside `roundTripPreservesStructureAndValues`, after the M-B block:

```swift
            // M-E: the fixture's checklist card round-trips items in order with their flags;
            // checklist-less cards export an EMPTY array (never a missing key) so encoding
            // stays deterministic — the byte-equality re-encode below covers both shapes.
            #expect(toDo.cards[2].checklist == [
                ExportChecklistItem(text: "Renew library card", isDone: true),
                ExportChecklistItem(text: "Gather books from car", isDone: true),
                ExportChecklistItem(text: "Pay late fee", isDone: false),
            ])
            #expect(toDo.cards[1].checklist == [], "Call plumber: empty array, not nil, in a fresh export")
```

(The existing `#expect(try ExportDocument.encode(decoded) == data)` line IS the "byteEqualityRoundTrip carries items" requirement — it now runs over a graph containing items.)

`TackTests/ImportDecodeTests.swift`:
- `cardJSON` helper gains a checklist parameter (the "cardJSON helper extension"):

```swift
    private func cardJSON(labels: String = "[]", dueDate: String? = nil, includesTime: Bool = false,
                          durationMinutes: Int? = nil, checklist: String? = nil) -> String {
        let due = dueDate.map { "\"dueDate\":\"\($0)\"," } ?? ""
        let duration = durationMinutes.map { "\"durationMinutes\":\($0)," } ?? ""
        let checklistFragment = checklist.map { "\"checklist\":\($0)," } ?? ""
        return """
        {\(checklistFragment)"createdAt":"2026-01-01T00:00:00Z","details":null,\(due)\(duration)"includesTime":\(includesTime),
         "labels":\(labels),"position":0,"title":"C","updatedAt":"2026-01-01T00:00:00Z"}
        """
    }
```

(JSON key order is irrelevant to decoding, so the new fragment leads the object — the smallest diff to the existing helper.)

- `versionGate`: title → `"formatVersion 5 and 0 throw .unsupportedVersion carrying the file's version"`, loop → `for version in [5, 0]`.
- Append:

```swift
    @Test("a version-3 file (no checklist key) still imports; checklist decodes nil")
    func v3FileStillImports() throws {
        let data = json(boardJSON(cards: cardJSON()), formatVersion: 3)
        let envelope = try ExportDocument.decodeForImport(data)
        #expect(envelope.formatVersion == 3)
        #expect(envelope.boards[0].lists[0].cards[0].checklist == nil,
                "missing key decodes nil — the optional-not-defaulted-array shape is load-bearing")
    }

    @Test("whitespace-only checklist items are dropped; kept items pass through in order, text verbatim")
    func checklistWhitespaceItemsDropped() throws {
        let payload = #"[{"text":"  Keep  ","isDone":true},{"text":"   ","isDone":false},{"text":"Also keep","isDone":false}]"#
        let envelope = try ExportDocument.decodeForImport(
            json(boardJSON(cards: cardJSON(checklist: payload)), formatVersion: 4))
        #expect(envelope.boards[0].lists[0].cards[0].checklist == [
            ExportChecklistItem(text: "  Keep  ", isDone: true),
            ExportChecklistItem(text: "Also keep", isDone: false),
        ], "drop whitespace-only, never rewrite kept text — the labels-filter posture")
    }
```

- Extend `sanitizeIdempotent`'s payload: give its first card `checklist: #"[{"text":"A","isDone":true},{"text":" ","isDone":false}]"#` — the existing `once == twice` assertion then proves checklist sanitization is idempotent too.

`TackTests/BoardStoreImportTests.swift` — append beside the materialization tests:

```swift
    @Test("M-E: import materializes checklist items in array order with positions 0..<n")
    func importMaterializesChecklistItems() throws {
        let env = TestContainer()
        env.store.ensureLabelsSeeded()
        var card = ExportCard(title: "C", details: nil, position: 0, dueDate: nil,
                              includesTime: false, createdAt: .now, updatedAt: .now, labels: [])
        card.checklist = [ExportChecklistItem(text: "One", isDone: true),
                          ExportChecklistItem(text: "Two", isDone: false)]
        let envelope = ExportEnvelope(formatVersion: 4, exportedAt: .now, boards: [
            ExportBoard(name: "B", emoji: nil, position: 0, themeName: "default",
                        customThemeHex: nil, createdAt: .now,
                        lists: [ExportList(name: "L", position: 0, isCollapsed: false, cards: [card])]),
        ])

        let imported = try env.store.importBoards(envelope)

        let items = imported[0].sortedLists[0].sortedCards[0].sortedChecklistItems
        #expect(items.map(\.text) == ["One", "Two"])
        #expect(items.map(\.isDone) == [true, false])
        #expect(items.map(\.position) == [0, 1])
    }
```

- [ ] **Step 2: Run to verify failure**

```bash
pkill -f xcodebuild; pkill -f Tack.app
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild -project Tack.xcodeproj -scheme Tack \
  -destination "platform=macOS,arch=$(uname -m)" -derivedDataPath .build/DerivedData \
  -only-testing:TackTests/FixtureSeederTests -only-testing:TackTests/ExportDocumentTests \
  -only-testing:TackTests/ImportDecodeTests -only-testing:TackTests/BoardStoreImportTests \
  test 2>&1 | tee .build/me-task2-red.log
```
Expected: compile FAILURE (`ExportChecklistItem`/`checklist` don't exist) plus, once those exist, runtime reds on version 3→4 and the fixture card.

- [ ] **Step 3: Implement**

`Tack/Store/FixtureSeeder.swift` — in `seedGroceries`, directly after `returnBooks`' `setDueDate` line:

```swift
        // M-E: the fixture's ONE checklist-bearing card — 3 items, 2 done, face fraction "2/3".
        // Deliberately Return library books: the least-detail-coupled dated card (no UI test ever
        // opens its detail sheet; its face-level uses are id/badge-value-based, which the fraction
        // chip on the EXISTING meta line can't disturb). Seeded through applyCardEdits so drafts →
        // rows exercise the exact production diff path. Do not move these items to another card —
        // Call plumber / Write report / Book flights all anchor CardDetailUITests flows.
        store.applyCardEdits(returnBooks, title: returnBooks.title, details: returnBooks.details,
                             labels: [], dueDate: returnBooks.dueDate, includesTime: false,
                             durationMinutes: nil,
                             checklist: [
                                 ChecklistDraft(id: nil, text: "Renew library card", isDone: true),
                                 ChecklistDraft(id: nil, text: "Gather books from car", isDone: true),
                                 ChecklistDraft(id: nil, text: "Pay late fee", isDone: false),
                             ])
```

`Tack/Export/ExportDocument.swift`:

```swift
/// M-E: one exported checklist row. Order in the array IS the order (positions are synthesized
/// from enumeration at materialize time, like every other position in the format).
struct ExportChecklistItem: Codable, Equatable {
    var text: String
    var isDone: Bool
}
```

`ExportCard` gains, after `durationMinutes`:

```swift
    // OPTIONAL, defaulted nil — NOT a defaulted non-optional array: synthesized Codable throws
    // keyNotFound on a missing key for a non-optional array (property defaults don't apply to
    // decoding), so the about/durationMinutes optional shape is the ONLY one that lets v1–v3
    // files decode. The exporter always writes the key (empty array when the card has no items,
    // keeping encoding deterministic); importers read `checklist ?? []`.
    var checklist: [ExportChecklistItem]? = nil
```

`formatVersion` → `4`, doc gains `/// v4 (M-E): + ExportCard.checklist (Action Items; array order is the row order).`

`exportCard` gains, after `durationMinutes: card.durationMinutes,`:

```swift
            checklist: card.sortedChecklistItems.map { ExportChecklistItem(text: $0.text, isDone: $0.isDone) },
```

(Note: `checklist` must be passed in the memberwise call in DECLARATION order — place it to match the struct. Swift requires memberwise-init argument order to follow the property order.)

`sanitized(_:calendar:)` — inside the per-card closure, after the duration nilling:

```swift
                    // M-E: drop whitespace-only checklist items, keep order, pass text through
                    // verbatim (the labels-filter posture); nil stays nil (idempotent — a v≤3
                    // file's absent checklist is not rewritten into an empty one).
                    card.checklist = card.checklist.map { items in
                        items.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                    }
```

`Tack/Store/BoardStore.swift` — in `materialize`, after the label-attach loop inside the card loop:

```swift
                    for (itemIndex, exportItem) in (exportCard.checklist ?? []).enumerated() {
                        context.insert(ChecklistItem(text: exportItem.text, isDone: exportItem.isDone,
                                                     position: itemIndex, card: card))
                    }
```

And extend `materialize`'s doc comment's position sentence: "list/card/checklist positions from array enumeration".

- [ ] **Step 4: Run to verify pass** — same command, log `.build/me-task2-green.log` → `** TEST SUCCEEDED **`.

- [ ] **Step 5: Full unit suite** — `make unit`, log `.build/me-task2-unit.log` → green. This is the fixture change's real gate: ListBucketTests/ExportDocumentTests/E-01's self-check path all consume the standard fixture and must be undisturbed (titles/dates/labels unchanged — only one card gained items).

- [ ] **Step 6: Commit**

```bash
git add Tack/Store/FixtureSeeder.swift Tack/Export/ExportDocument.swift Tack/Store/BoardStore.swift TackTests/FixtureSeederTests.swift TackTests/ExportDocumentTests.swift TackTests/ImportDecodeTests.swift TackTests/BoardStoreImportTests.swift
git commit -m "Export v4: checklist array on cards; fixture seeds 2/3 on Return library books (M-E)

ExportChecklistItem {text,isDone}; ExportCard.checklist is an OPTIONAL
defaulted nil (synthesized Codable throws on a missing key for a
non-optional array — the about/durationMinutes precedent is the only
v1-v3-tolerant shape); exporter always writes the key, materialize
enumerates positions, sanitizer drops whitespace-only items (idempotent,
nil untouched). Version gate now accepts 1...4, rejects 5.

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 3: "Action Items" section + card-face fraction + UI tests (UI TDD)

**Files:**
- Modify: `Tack/Support/AccessibilityID.swift` (M-E section)
- Modify: `TackUITests/CardDetailUITests.swift` (three new tests)
- Modify: `Tack/Views/CardDetail/CardDetailView.swift` (staged drafts + section)
- Modify: `Tack/Views/Board/CardView.swift` (fraction chip + `hasMetaLine`)

No new files → no `make gen`.

**Interfaces:**
- Consumes: `ChecklistDraft.drafts(of:)` + `applyCardEdits(checklist:)` (Task 1), the seeded fixture card (Task 2), `reportsTextInputFocus()`, the labelDots/DueDateBadge `.accessibilityRepresentation` pattern, `dueQuickToday` (the M-0 oracle).
- Produces: the staged Action Items section (replacing Task 1's identity bridge), the face fraction, AX ids. **Deliberately NOT changed in v1 (document, don't "complete"):** `CardListRow` (List mode) and the calendar chips do NOT get the fraction — the locked scope is the card FACE's one-extra-slot budget; the other surfaces are a follow-up if wanted.

- [ ] **Step 1: AccessibilityID + failing UI tests**

`Tack/Support/AccessibilityID.swift` — append after the M-D block:

```swift
    // MARK: - M-E: checklists (Action Items)

    /// Card-detail checklist row controls. INDEX-keyed — the app's only index-keyed ids — because
    /// staged rows are anonymous until saved (a nil-id draft has no UUID and text is user-mutable
    /// mid-test). Index = the row's position in the staged drafts array, stable within a sheet
    /// (v1 has no reorder UI).
    static func checkItemToggle(_ index: Int) -> String { "checkitem-toggle-\(index)" }
    static func checkItemText(_ index: Int) -> String { "checkitem-text-\(index)" }
    static func checkItemDelete(_ index: Int) -> String { "checkitem-delete-\(index)" }
    static let checkItemAdd = "checkitem-add"
    /// The card face's done/total fraction — a representation Text (the `cardLabels`/DueDateBadge
    /// pattern) whose value is "<done>/<total>". Prefixed "checklist-", never "card-"
    /// (`cardIdentifiersByPosition` counts `BEGINSWITH "card-"`). Present only when total > 0.
    static func cardChecklist(_ title: String) -> String { "checklist-\(title)" }
```

Append to `TackUITests/CardDetailUITests.swift` (before the Open helper MARK):

```swift
    // MARK: - M-E: Action Items

    /// Add two items on the checklist-free "Book flights" (it has NO meta line at all — labels
    /// none, due date none — so this also proves the fraction ALONE creates the meta line),
    /// toggle one done, Save, assert the face fraction, reopen (drafts seed from the card),
    /// and persist across relaunch.
    func testActionItemsAddToggleSavePersists() {
        launch(fixture: "standard")

        openDetailViaBodyDoubleClick("Book flights")
        XCTAssertTrue(detailSheet.staticTexts["Action Items"].exists,
                      "section header should read Action Items, below Brief")

        element(AccessibilityID.checkItemAdd).click()
        let firstField = element(AccessibilityID.checkItemText(0))
        XCTAssertTrue(firstField.waitForExistence(timeout: timeout))
        firstField.click()
        firstField.typeText("Pack bags")

        element(AccessibilityID.checkItemAdd).click()
        let secondField = element(AccessibilityID.checkItemText(1))
        XCTAssertTrue(secondField.waitForExistence(timeout: timeout))
        secondField.click()
        secondField.typeText("Check passport")

        element(AccessibilityID.checkItemToggle(0)).click()

        hittableButton("Save").click()
        XCTAssertTrue(poll(timeout: timeout) { !self.detailSheet.exists })

        let fraction = element(AccessibilityID.cardChecklist("Book flights"))
        XCTAssertTrue(poll(timeout: timeout) { fraction.exists },
                      "the fraction should appear after Save — it alone creates the meta line")
        XCTAssertEqual(fraction.value as? String, "1/2")

        openDetailViaBodyDoubleClick("Book flights")
        XCTAssertEqual(element(AccessibilityID.checkItemText(0)).value as? String, "Pack bags",
                       "drafts must seed from the persisted rows on reopen")
        XCTAssertEqual(element(AccessibilityID.checkItemText(1)).value as? String, "Check passport")
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(poll(timeout: timeout) { !self.detailSheet.exists })

        relaunchPreservingStore()

        let fractionAfter = element(AccessibilityID.cardChecklist("Book flights"))
        XCTAssertTrue(fractionAfter.waitForExistence(timeout: timeout),
                      "checklist should persist across relaunch")
        XCTAssertEqual(fractionAfter.value as? String, "1/2")
    }

    /// The seeded fixture card's face fraction (asserted here because NO other test opens Return
    /// library books' sheet — that's exactly why it carries the fixture checklist), plus the
    /// Cancel contract: staged toggle + delete + add must all be discarded.
    func testActionItemsCancelDiscardsAndFixtureFraction() {
        launch(fixture: "standard")

        let fraction = element(AccessibilityID.cardChecklist("Return library books"))
        XCTAssertTrue(fraction.waitForExistence(timeout: timeout),
                      "the fixture seeds 3 items (2 done) on Return library books")
        XCTAssertEqual(fraction.value as? String, "2/3")

        openDetailViaBodyDoubleClick("Return library books")
        XCTAssertEqual(element(AccessibilityID.checkItemText(0)).value as? String, "Renew library card",
                       "drafts seed in position order")
        element(AccessibilityID.checkItemToggle(2)).click()   // stage: done the not-done row
        element(AccessibilityID.checkItemDelete(0)).click()   // stage: delete the first row
        element(AccessibilityID.checkItemAdd).click()         // stage: add a row (now index 2)
        let newField = element(AccessibilityID.checkItemText(2))
        XCTAssertTrue(newField.waitForExistence(timeout: timeout))
        newField.click()
        newField.typeText("Staged only")

        hittableButton("Cancel").click()
        XCTAssertTrue(poll(timeout: timeout) { !self.detailSheet.exists })

        XCTAssertEqual(fraction.value as? String, "2/3",
                       "Cancel must discard every staged checklist change")
    }

    /// M-0 oracle, extended (the plan's sheet-layout resolution): 5 staged rows must NOT push
    /// the due-date controls off the fixed-ideal-height sheet — the rows live in a bounded,
    /// content-sized scroller, never in the flexible-layout negotiation.
    func testLongChecklistKeepsDueDateHittable() {
        launch(fixture: "standard")

        openDetailViaBodyDoubleClick("Call plumber")
        for _ in 0..<5 {
            element(AccessibilityID.checkItemAdd).click()
        }
        XCTAssertTrue(element(AccessibilityID.checkItemText(4)).waitForExistence(timeout: timeout),
                      "five staged rows should render")

        let today = element(AccessibilityID.dueQuickToday)
        XCTAssertTrue(today.exists, "due-date quick buttons should exist below the checklist")
        XCTAssertTrue(today.isHittable,
                      "a long checklist must stay bounded — never push the due-date section off-screen")

        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(poll(timeout: timeout) { !self.detailSheet.exists })
        // Belt-and-suspenders: even if these empty rows HAD been saved, whitespace-only drafts
        // drop at the store; either way the face must show no fraction.
        XCTAssertFalse(element(AccessibilityID.cardChecklist("Call plumber")).exists)
    }
```

- [ ] **Step 2: Run to verify failure**

```bash
pkill -f xcodebuild; pkill -f Tack.app
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild -project Tack.xcodeproj -scheme Tack \
  -destination "platform=macOS,arch=$(uname -m)" -derivedDataPath .build/DerivedData \
  -only-testing:TackUITests/CardDetailUITests -parallel-testing-enabled NO test 2>&1 | tee .build/me-task3-red.log
```
Expected: the UI target COMPILES (the AX ids land in this step); the three new tests fail at RUNTIME on missing `checkitem-add`/`checklist-Return library books` elements (the section and chip don't exist), and — important — every PRE-EXISTING CardDetailUITests test stays green (Task 2 changed only Return library books, whose sheet none of them opens). That runtime red against a live fixture is what proves these tests bite.

- [ ] **Step 3: Implement the section + the fraction**

`Tack/Views/CardDetail/CardDetailView.swift`:

1. New state + init seeding (after `_durationMinutes`):

```swift
    @State private var checklistDrafts: [ChecklistDraft]
```
```swift
        _checklistDrafts = State(initialValue: ChecklistDraft.drafts(of: card))
```

2. In `body`, between the Brief `VStack` and `LabelPicker(selected: $labels)`:

```swift
                actionItemsSection
```

3. The section (new private members; place after `footer`):

```swift
    // MARK: - M-E: Action Items (staged, like every other sheet field)

    private static let checklistRowHeight: CGFloat = 28
    /// Rows visible without scrolling. WHY a bounded scroller at all: the Brief editor is the
    /// sheet's ONE flexible element (maxHeight .infinity + layoutPriority(1), floor 120pt) — an
    /// UNbounded checklist would push Labels/Due Date/footer off the fixed-ideal-height sheet,
    /// the exact bug class M-0's testLongBriefScrollsInsideEditorNotSheet pins for the editor.
    /// A FIXED, content-sized height keeps this section out of the flexible-layout negotiation
    /// entirely, and the CAP is deliberately small (4 rows ≈ 112pt): with an empty Brief the
    /// editor sits well above its floor, so the section compresses the EDITOR, never the pinned
    /// due-date controls (testLongChecklistKeepsDueDateHittable is the regression gate). Long
    /// Brief + long checklist at DEFAULT size is the one accepted squeeze — the sheet is
    /// user-resizable since M-0. With ≤4 rows nothing ever scrolls, so row clicks/typing are
    /// unaffected. NOT a native List (nested-scroll + .onMove pitfalls) — a plain NON-lazy
    /// ForEach in a plain ScrollView (non-lazy so below-the-fold rows still exist for AX queries).
    private static let checklistVisibleRowCap = 4

    private var stagedDoneCount: Int { checklistDrafts.filter(\.isDone).count }

    private var checklistRowsHeight: CGFloat {
        CGFloat(min(checklistDrafts.count, Self.checklistVisibleRowCap)) * Self.checklistRowHeight
    }

    private var actionItemsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            // ONE header line: title + staged count + inline Add — an EMPTY checklist costs the
            // sheet ~20pt total, which is what keeps the pre-M-E layout tests green.
            HStack(spacing: 6) {
                Text("Action Items")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !checklistDrafts.isEmpty {
                    // Staged count — live while editing, matching the face fraction after Save.
                    Text("\(stagedDoneCount)/\(checklistDrafts.count)")
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Button {
                    checklistDrafts.append(ChecklistDraft(id: nil, text: "", isDone: false))
                    // Deliberately NO focus move onto the new row: .focused()/FocusState bindings
                    // are the launch-focus pitfall's surface (they killed the keyboard command
                    // surface once already — see CLAUDE.md). The user clicks into the row.
                    // Accepted v1.
                } label: {
                    Label("Add Item", systemImage: "plus")
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .accessibilityIdentifier(AccessibilityID.checkItemAdd)
            }
            if !checklistDrafts.isEmpty {
                ScrollView {
                    VStack(spacing: 0) {
                        // Index identity — deliberate: new drafts have nil ids (ChecklistDraft is
                        // not Identifiable), and v1 has no reorder UI, so the index is stable for
                        // the sheet's lifetime and doubles as the AX-id key.
                        ForEach(checklistDrafts.indices, id: \.self) { index in
                            checklistRow(index)
                        }
                    }
                }
                .frame(height: checklistRowsHeight)
            }
        }
    }

    private func checklistRow(_ index: Int) -> some View {
        HStack(spacing: 8) {
            Button {
                checklistDrafts[index].isDone.toggle()
            } label: {
                Image(systemName: checklistDrafts[index].isDone ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(checklistDrafts[index].isDone ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.plain)
            .help(checklistDrafts[index].isDone ? "Mark as not done" : "Mark as done")
            .accessibilityLabel(checklistDrafts[index].isDone ? "Done" : "Not Done")
            .accessibilityIdentifier(AccessibilityID.checkItemToggle(index))

            TextField("Action item", text: $checklistDrafts[index].text)
                .textFieldStyle(.plain)
                // MANDATORY (CLAUDE.md text-input pitfall): the first NEW text inputs since M-A.
                // Without this, ⌘⌫/⌘N/every menu shortcut fires while the user types an item.
                .reportsTextInputFocus()
                .accessibilityIdentifier(AccessibilityID.checkItemText(index))

            Button {
                checklistDrafts.remove(at: index)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Remove item")
            .accessibilityLabel("Remove Item")
            .accessibilityIdentifier(AccessibilityID.checkItemDelete(index))
        }
        .frame(height: Self.checklistRowHeight)
    }
```

4. `save()` — replace the Task-1 bridge:

```swift
            checklist: checklistDrafts // staged; the store drops whitespace-only drafts
```

`Tack/Views/Board/CardView.swift`:

1. `hasMetaLine` becomes:

```swift
    private var hasMetaLine: Bool {
        !sortedLabelColors.isEmpty || card.dueDate != nil || !card.checklistItems.isEmpty
    }
```

2. `metaLine` gains the fraction between the Spacer and the badge (all of dots + fraction + badge on the ONE line — the locked M-0 budget: at most one extra element, and the fraction takes the slot since no timer exists):

```swift
    private var metaLine: some View {
        HStack(spacing: 6) {
            labelDots
            Spacer(minLength: 0)
            checklistFraction
            if let dueDate = card.dueDate {
                DueDateBadge(card: card, dueDate: dueDate)
            }
        }
    }
```

3. New member, after `labelDots`:

```swift
    /// M-E: the Action Items "done/total" fraction — present only when the card HAS items.
    /// Quiet secondary styling (it's a progress note, not an urgency signal like the badge).
    @ViewBuilder
    private var checklistFraction: some View {
        let total = card.checklistItems.count
        if total > 0 {
            let done = card.checklistItems.filter(\.isDone).count
            HStack(spacing: 3) {
                Image(systemName: "checklist")
                    .font(.system(size: 9))
                Text("\(done)/\(total)")
                    .font(.caption2)
                    .monospacedDigit()
            }
            .foregroundStyle(.secondary)
            // The labelDots/DueDateBadge pattern: a representation Text whose TEXT is the machine
            // payload — plain .accessibilityValue on SwiftUI shapes reads EMPTY under XCUITest on
            // macOS (the M6 finding). measuredRowHeight/DropMath need no change: the fraction
            // shares the existing meta line, so row height is untouched.
            .accessibilityRepresentation {
                Text("\(done)/\(total)")
                    .accessibilityIdentifier(AccessibilityID.cardChecklist(card.title))
            }
        }
    }
```

Then build: `pkill -f xcodebuild; pkill -f Tack.app; make build 2>&1 | tee .build/me-task3-build.log` → `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Run the green set** — same command as Step 2, log `.build/me-task3-green.log`. Expected: `** TEST SUCCEEDED **` — 3 new + all pre-existing CardDetailUITests (the size-band and long-Brief tests open Call plumber, whose checklist is EMPTY at open, so the section contributes ONE ~20pt header line — that lean footprint is a design requirement, not luck). If `testLongBriefScrollsInsideEditorNotSheet` or `testLongChecklistKeepsDueDateHittable` goes red on layout, the fix direction is fixed: shrink the section further (tighter spacing, lower `checklistVisibleRowCap`) or trim the sheet's inter-section spacing — NEVER weaken the hittable oracle and NEVER add a whole-sheet ScrollView. If a typing step fails with "no keyboard focus", check the xcresult recording FIRST (the desktop-notification environmental mode), then verify the click landed on the row's TextField and not the toggle.

- [ ] **Step 5: Commit**

```bash
git add Tack/Support/AccessibilityID.swift Tack/Views/CardDetail/CardDetailView.swift Tack/Views/Board/CardView.swift TackUITests/CardDetailUITests.swift
git commit -m "Action Items section in card detail + face fraction chip (M-E)

Staged checklist drafts below Brief: checkbox + plain TextField
(.reportsTextInputFocus — the first new text inputs since M-A) + remove
button per row, Add Item appends (no auto-focus: the .focused() launch
pitfall), rows in a fixed content-sized 4-row scroller so the section
never pushes Due Date off the sheet (M-0 oracle extended by
testLongChecklistKeepsDueDateHittable). Card face gains a quiet n/m
fraction on the meta line (one-extra-slot budget) wired via the
labelDots representation pattern.

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 4: PRD currency + milestone gate

**Files:**
- Modify: `PRD-Kanban-Board-Mac.md` (§7 shipped marker + Appendix; §4.7-family ONLY if Task 1b ran — already done there)

- [ ] **Step 1: PRD §7 shipped marker** (the M-B/E-02 spec-currency precedent — priority column keeps its historical value, the Reason cell records the ship):

Replace the §7 checklists row with:

```markdown
| Card checklists (sub-tasks) | P2 | **Shipped post-MVP (M-E)** as "Action Items" — a staged checklist section in the card detail sheet (Save/Cancel contract: one `applyCardEdits` commit, one ⌘Z per sheet; no per-item live writes), a done/total fraction on the card face, and export `formatVersion` 4 carrying items. No reorder UI in v1 (insertion order = position). Undo posture per the M-E cascade spike: [Task 1a: "card/list deletes remain undoable — re-verified at three cascade levels" / Task 1b: "card/list deletes are no longer undoable — see §4.7, U-01"] |
```

(Pick the bracket matching the Task 0 verdict.) And the Appendix P2 bullet:

```markdown
- Card checklists (sub-tasks) — **shipped post-MVP (M-E)** as Action Items (see §7)
```

Verification step, not just an edit: `grep -n "checklist" PRD-Kanban-Board-Mac.md` and read every hit — after this task the PRD must nowhere describe checklists as unshipped, and (if 1b) nowhere call card/list deletes undoable.

- [ ] **Step 2: Full unit suite** — `pkill -f xcodebuild; pkill -f Tack.app; make unit 2>&1 | tee .build/me-gate-unit.log` → `** TEST SUCCEEDED **` (spike/sentinel suite included).

- [ ] **Step 3: Mouse-driven UI suites this milestone touched or depends on:**

```bash
pkill -f xcodebuild; pkill -f Tack.app
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild -project Tack.xcodeproj -scheme Tack \
  -destination "platform=macOS,arch=$(uname -m)" -derivedDataPath .build/DerivedData \
  -only-testing:TackUITests/CardDetailUITests -only-testing:TackUITests/BadgeUITests \
  -only-testing:TackUITests/ListViewUITests -only-testing:TackUITests/CalendarViewUITests \
  -only-testing:TackUITests/DragAndDropUITests \
  -parallel-testing-enabled NO test 2>&1 | tee .build/me-gate-ui.log
```

Expected: green. CardDetailUITests carries the new coverage; BadgeUITests proves the badge beside the new fraction chip is undisturbed; ListView/CalendarView prove the other two board surfaces render the fixture's checklist card (they show NO fraction in v1 — by scope) without layout or id fallout; DragAndDropUITests is deliberate insurance — it drops onto Return library books' row, the one card whose face changed. Triage any failure against the environmental playbook (xcresult recording first; control-run committed code) — `KeyboardShortcutUITests`/`LabelFilterUITests` are NOT gates here (documented environmentally-red class); run them opportunistically in the next fresh login session (MANDATORY there if Task 1b ran, since it rewrote a keyboard test).

- [ ] **Step 4: Human checklist (hand to Ty, accumulate with M-A…M-D's)**

Launch against a scratch store — **File ▸ New Tack Window (⌘N) is the second step** (the windowless-launch pitfall):

```sh
open .build/DerivedData/Build/Products/Debug/Tack.app --args --uitest --fixture standard --store-name scratch --reset
```

1. Open Return library books — "Action Items" sits directly below Brief with "2/3" in the header; rows read Renew library card ✓ / Gather books from car ✓ / Pay late fee ○; checkboxes toggle with the count updating live; the X removes a row; Add Item appends an empty row that does NOT steal focus (click into it to type — the documented v1 posture).
2. Staging contract: make checklist changes + a title change, Esc → everything discarded; again with Cancel; again with Save → all committed together; **⌘Z once** reverses the ENTIRE sheet edit including items; **⇧⌘Z** reapplies it — count the rows after redo (the silent-row-loss class is exactly what you're eyeballing for).
3. While the caret is in an item's TextField: Card ▸ Delete Card, File ▸ New Card, and the other editing commands must be grayed out (the `reportsTextInputFocus` gate — the milestone's biggest pitfall surface); click out, and they re-enable.
4. Card face: Return library books shows "⋮≡ 2/3" beside its badge; give one card 8 labels + a due date + items — dots, fraction, and badge share ONE line without wrapping (the one-extra-slot budget); a card with items but no labels/due date (add items to Book flights) grows the meta line with the fraction alone; checking the last item shows "3/3" (v1 keeps the chip at full completion — no auto-hide).
5. Add 8+ items to one card: the rows scroll inside the section (6 visible), Labels/Due Date/Save stay put; resize the sheet taller — everything still composed; a long Brief AND a long checklist together still keep the footer visible.
6. Export via File ▸ Export (with the window open!): the JSON carries `"formatVersion" : 4` and a `"checklist"` array under Return library books; re-import it (Add to Existing) → the copy's items are intact, in order; ⌘Z after import still does nothing (unchanged E-02 posture).
7. Migration: relaunch the SAME scratch store with a pre-M-E build if one is at hand (or trust the additive-entity posture + this line): boards open, no migration crash. Then relaunch the new build WITHOUT `--reset` — items persist.
8. Appearance: `--appearance dark` — checkboxes, the row hairlines, and the face fraction stay legible; the section reads as part of the sheet, not a cut-in well.
9. **Only if Task 1b ran:** delete a card (⌘⌫) and a list — Edit ▸ Undo is DISABLED afterwards and ⌘Z does nothing; the list delete still shows its confirmation dialog; verify the PRD's C-05/L-02/U-01 rows now say exactly that.

- [ ] **Step 5: Commit**

```bash
git add PRD-Kanban-Board-Mac.md
git commit -m "PRD: checklists row marked shipped (M-E)

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```
