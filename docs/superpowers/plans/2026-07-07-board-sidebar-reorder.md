# Board Sidebar Drag-Reorder (B-06) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Drag-and-drop reordering of boards in the sidebar, persisted via `Board.position`, undoable as one ⌘Z step, disabled while the sidebar filter is active.

**Architecture:** Native SwiftUI `List` + `ForEach` + `.onMove` in `SidebarView` (NOT the `Transferable`/`.dropDestination` machinery — that exists for the custom board canvas; `.onMove` is the platform idiom inside a `List`). The view passes SwiftUI's `(IndexSet, Int)` handler arguments straight through to a new `BoardStore.moveBoards(fromOffsets:toOffset:)`, which uses a new pure `Reordering.movedWithin(_:fromOffsets:toOffset:)` overload adopting SwiftUI's `.onMove` index convention end-to-end — so no index translation (and no off-by-one) exists anywhere. No schema change: `Board.position` already exists under `TackSchemaV1`.

**Tech Stack:** SwiftUI + SwiftData (macOS 14+), Swift Testing (unit), XCUITest (UI). Spec: `docs/superpowers/specs/2026-07-07-board-sidebar-reorder-design.md`.

## Global Constraints

- Every `xcodebuild` needs `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` (`xcode-select` on this machine points at Command Line Tools only; the Makefile exports it for you).
- Run `xcodebuild` in the **foreground** and read complete output. Before any run: `pkill -f xcodebuild; pkill -f Tack.app`. A unit-test run past ~6 minutes is a hang, not a slow run — kill it and read the log tail for a FAULT line.
- `Tack.xcodeproj` is gitignored/generated — after adding any new source file, run `make gen`.
- Undoable store mutations MUST be wrapped in exactly one explicit `withUndoGroup` (never rely on `groupsByEvent`); undo/redo unit tests use `TestContainer(withUndo: true)`.
- `Tack/Store/Reordering.swift` must stay free of SwiftUI/SwiftData imports — plain, total, deterministic functions only.
- Drag retries in UI tests must poll the postcondition before retrying (the base class's `drag(_:to:targetNormalizedOffset:until:)` does this — always use it, never raw `press(forDuration:thenDragTo:)`).
- All work happens on `main` (repo practice: no feature branches so far — single-user repo, direct commits).

---

### Task 1: `Reordering.movedWithin(fromOffsets:toOffset:)` — pure ordering math

**Files:**
- Modify: `Tack/Store/Reordering.swift` (add one static function to the existing `enum Reordering`)
- Test: `TackTests/ReorderingTests.swift` (append tests to the existing `@Suite("Reordering")`)

**Interfaces:**
- Consumes: existing private `Reordering.clamp(_:lower:upper:)`.
- Produces: `static func movedWithin<Element>(_ items: [Element], fromOffsets source: IndexSet, toOffset destination: Int) -> [Element]` — SwiftUI `.onMove` convention. Task 2's `BoardStore.moveBoards` calls exactly this.

**Semantics being pinned (SwiftUI `.onMove` / stdlib `move(fromOffsets:toOffset:)` convention):** `fromOffsets` are offsets into the ORIGINAL array; `toOffset` is the insertion offset in the ORIGINAL (pre-removal) array. So for a single element, `toOffset == from` and `toOffset == from + 1` are both the identity, and "drag row 0 just below row 1" arrives as `toOffset == 2`. Total function: out-of-range source offsets are dropped; `toOffset` clamps into `0...count`; empty (post-sanitize) source set and empty array are the identity.

- [ ] **Step 1: Write the failing tests**

Append inside `struct ReorderingTests` (after `normalizedEmpty`, before the closing brace) in `TackTests/ReorderingTests.swift`:

```swift
    // MARK: - movedWithin(fromOffsets:toOffset:) — SwiftUI .onMove convention
    // `toOffset` is the insertion offset in the PRE-REMOVAL array (what SwiftUI's
    // .onMove hands its handler), NOT the element's index in the resulting array.

    @Test("onMove: dragging the first row just below the second arrives as toOffset 2 and swaps them")
    func onMoveDownByOne() {
        let result = Reordering.movedWithin(ids, fromOffsets: IndexSet(integer: 0), toOffset: 2)
        #expect(result == [b, a, c, d])
    }

    @Test("onMove: move first to end (toOffset == count)")
    func onMoveFirstToEnd() {
        let result = Reordering.movedWithin(ids, fromOffsets: IndexSet(integer: 0), toOffset: 4)
        #expect(result == [b, c, d, a])
    }

    @Test("onMove: move last to front")
    func onMoveLastToFront() {
        let result = Reordering.movedWithin(ids, fromOffsets: IndexSet(integer: 3), toOffset: 0)
        #expect(result == [d, a, b, c])
    }

    @Test("onMove: toOffset == source offset is identity")
    func onMoveIdentitySameOffset() {
        let result = Reordering.movedWithin(ids, fromOffsets: IndexSet(integer: 1), toOffset: 1)
        #expect(result == ids)
    }

    @Test("onMove: toOffset == source offset + 1 is ALSO identity (pre-removal convention)")
    func onMoveIdentityNextOffset() {
        let result = Reordering.movedWithin(ids, fromOffsets: IndexSet(integer: 1), toOffset: 2)
        #expect(result == ids)
    }

    @Test("onMove: multi-element IndexSet moves all, preserving their relative order")
    func onMoveMultiElement() {
        let result = Reordering.movedWithin(ids, fromOffsets: IndexSet([0, 2]), toOffset: 4)
        #expect(result == [b, d, a, c])
    }

    @Test("onMove: out-of-range source offsets are dropped, valid ones still move")
    func onMoveInvalidSourceDropped() {
        let result = Reordering.movedWithin(ids, fromOffsets: IndexSet([0, 99]), toOffset: 4)
        #expect(result == [b, c, d, a])
    }

    @Test("onMove: entirely out-of-range source set is identity")
    func onMoveAllInvalidSourceIdentity() {
        let result = Reordering.movedWithin(ids, fromOffsets: IndexSet(integer: 99), toOffset: 0)
        #expect(result == ids)
    }

    @Test("onMove: negative toOffset clamps to start")
    func onMoveNegativeDestinationClamps() {
        let result = Reordering.movedWithin(ids, fromOffsets: IndexSet(integer: 3), toOffset: -5)
        #expect(result == [d, a, b, c])
    }

    @Test("onMove: oversized toOffset clamps to end")
    func onMoveOversizedDestinationClamps() {
        let result = Reordering.movedWithin(ids, fromOffsets: IndexSet(integer: 0), toOffset: 99)
        #expect(result == [b, c, d, a])
    }

    @Test("onMove: empty array is a no-op")
    func onMoveEmptyArray() {
        let result = Reordering.movedWithin([UUID](), fromOffsets: IndexSet(integer: 0), toOffset: 0)
        #expect(result.isEmpty)
    }
```

- [ ] **Step 2: Run the suite to verify it fails to compile**

```sh
pkill -f xcodebuild; pkill -f Tack.app
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project Tack.xcodeproj -scheme Tack \
  -destination "platform=macOS,arch=$(uname -m)" -derivedDataPath .build/DerivedData \
  -only-testing:TackTests/ReorderingTests test
```

Expected: **BUILD FAILURE** — errors on the new tests, e.g. `incorrect argument labels in call (have '_:fromOffsets:toOffset:', expected '_:from:to:')`. (A compile failure of the test target is this step's "failing test".)

- [ ] **Step 3: Implement the overload**

In `Tack/Store/Reordering.swift`, after the existing `movedWithin(_:from:to:)` function (line 19) and before `removed(_:at:)`, add:

```swift
    /// SwiftUI `.onMove` convention (same as the stdlib overlay's `move(fromOffsets:toOffset:)`):
    /// `fromOffsets` are offsets into the ORIGINAL array; `toOffset` is the insertion offset in
    /// the ORIGINAL (pre-removal) array — so for a single element, `toOffset == from` and
    /// `toOffset == from + 1` are both the identity. Total: out-of-range source offsets are
    /// dropped, `toOffset` is clamped into `0...count`. Implemented by hand (not via the
    /// Foundation/SwiftUI overlay method) to keep this file UI-framework-free; the semantics
    /// are pinned by ReorderingTests.
    static func movedWithin<Element>(_ items: [Element], fromOffsets source: IndexSet, toOffset destination: Int) -> [Element] {
        let sourceOffsets = source.filter { items.indices.contains($0) } // ascending: IndexSet iterates in order
        guard !sourceOffsets.isEmpty else { return items }
        let clampedDestination = clamp(destination, lower: 0, upper: items.count)
        // Insertion index in the post-removal array: the destination minus however many
        // moving elements sat before it.
        let insertionIndex = clampedDestination - sourceOffsets.filter { $0 < clampedDestination }.count
        let moving = sourceOffsets.map { items[$0] }
        let sourceSet = Set(sourceOffsets)
        var result = items.enumerated().filter { !sourceSet.contains($0.offset) }.map(\.element)
        result.insert(contentsOf: moving, at: insertionIndex)
        return result
    }
```

(`import Foundation` is already present — `IndexSet` needs nothing new.)

- [ ] **Step 4: Run the suite to verify it passes**

Same command as Step 2. Expected: **TEST SUCCEEDED**, all `Reordering` tests green (existing 17 + new 11).

- [ ] **Step 5: Commit**

```sh
git add Tack/Store/Reordering.swift TackTests/ReorderingTests.swift
git commit -m "Add Reordering.movedWithin(fromOffsets:toOffset:) — SwiftUI .onMove convention (B-06)"
```

---

### Task 2: `BoardStore.moveBoards(fromOffsets:toOffset:)` + `Board` position bookkeeping

**Files:**
- Modify: `Tack/Store/BoardStore.swift` (add `Board: PositionedEntity` conformance at line ~13; add `moveBoards` in the `// MARK: - Boards` section, after `filterBoards`)
- Modify: `Tack/Models/Board.swift:9` (stale comment only)
- Test: `TackTests/BoardStoreBoardTests.swift`, `TackTests/UndoRedoTests.swift`

**Interfaces:**
- Consumes: `Reordering.movedWithin(_:fromOffsets:toOffset:)` (Task 1); existing private `fetchBoards()`, `applyPositions(_:to:)`, `withUndoGroup(_:_:)`, `save()`.
- Produces: `func moveBoards(fromOffsets source: IndexSet, toOffset destination: Int)` on `BoardStore` — Task 3's view handler calls exactly this. Also `extension Board: PositionedEntity {}` (private protocol, same file).

- [ ] **Step 1: Write the failing tests**

Append inside `struct BoardStoreBoardTests` (after `filterBoardsExcludesNonMatches`, before the closing brace) in `TackTests/BoardStoreBoardTests.swift`:

```swift
    @Test("moveBoards reorders and renumbers positions to contiguous 0..<n")
    func moveBoardsReorders() {
        let env = TestContainer()
        let a = env.store.createBoard(name: "A", emoji: nil)
        let b = env.store.createBoard(name: "B", emoji: nil)
        let c = env.store.createBoard(name: "C", emoji: nil)

        // .onMove convention: drag the first board to the end.
        env.store.moveBoards(fromOffsets: IndexSet(integer: 0), toOffset: 3)

        let ordered = [a, b, c].sorted { $0.position < $1.position }
        #expect(ordered.map(\.name) == ["B", "C", "A"])
        #expect(ordered.map(\.position) == [0, 1, 2])
    }

    @Test("identity moveBoards registers no undo step and changes nothing")
    func moveBoardsIdentityNoUndo() {
        let env = TestContainer(withUndo: true)
        let a = env.store.createBoard(name: "A", emoji: nil)
        let b = env.store.createBoard(name: "B", emoji: nil)
        env.undoManager?.removeAllActions() // isolate the move from the creates

        // toOffset == source offset + 1 is the identity under the .onMove convention.
        env.store.moveBoards(fromOffsets: IndexSet(integer: 0), toOffset: 1)

        #expect(env.undoManager?.canUndo == false)
        #expect(a.position == 0)
        #expect(b.position == 1)
    }

    @Test("moveBoards self-heals position gaps left by deleteBoard")
    func moveBoardsHealsGaps() {
        let env = TestContainer()
        let a = env.store.createBoard(name: "A", emoji: nil) // position 0
        let b = env.store.createBoard(name: "B", emoji: nil) // position 1
        let c = env.store.createBoard(name: "C", emoji: nil) // position 2
        env.store.deleteBoard(b) // deleteBoard does NOT renumber — positions are now 0, 2

        // Sidebar (position-sorted) order is [A, C]; move C before A.
        env.store.moveBoards(fromOffsets: IndexSet(integer: 1), toOffset: 0)

        let remaining = [a, c].sorted { $0.position < $1.position }
        #expect(remaining.map(\.name) == ["C", "A"])
        #expect(remaining.map(\.position) == [0, 1])
    }
```

Append inside `struct UndoRedoTests` (before the closing brace) in `TackTests/UndoRedoTests.swift`:

```swift
    @Test("undo of moveBoards restores the previous sidebar order; redo reapplies it")
    func undoRedoMoveBoards() {
        let env = TestContainer(withUndo: true)
        let a = env.store.createBoard(name: "A", emoji: nil)
        let b = env.store.createBoard(name: "B", emoji: nil)
        let c = env.store.createBoard(name: "C", emoji: nil)
        func orderedNames() -> [String] {
            [a, b, c].sorted { $0.position < $1.position }.map(\.name)
        }

        env.store.moveBoards(fromOffsets: IndexSet(integer: 2), toOffset: 0)
        #expect(orderedNames() == ["C", "A", "B"])

        env.undoManager?.undo()
        #expect(orderedNames() == ["A", "B", "C"])

        env.undoManager?.redo()
        #expect(orderedNames() == ["C", "A", "B"])
    }
```

- [ ] **Step 2: Run both suites to verify they fail to compile**

```sh
pkill -f xcodebuild; pkill -f Tack.app
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project Tack.xcodeproj -scheme Tack \
  -destination "platform=macOS,arch=$(uname -m)" -derivedDataPath .build/DerivedData \
  -only-testing:TackTests/BoardStoreBoardTests -only-testing:TackTests/UndoRedoTests test
```

Expected: **BUILD FAILURE** — `value of type 'BoardStore' has no member 'moveBoards'`.

- [ ] **Step 3: Implement**

In `Tack/Store/BoardStore.swift`, extend the `PositionedEntity` conformances (line 13-14) to include `Board`:

```swift
extension Board: PositionedEntity {}
extension BoardList: PositionedEntity {}
extension Card: PositionedEntity {}
```

Then add `moveBoards` in the `// MARK: - Boards` section, directly after `filterBoards` (line ~139):

```swift
    /// B-06: reorders boards in sidebar (position-sorted) order using SwiftUI's `.onMove`
    /// convention — `SidebarView` passes its handler arguments straight through, so no index
    /// translation exists anywhere. Renumbers ALL boards to a contiguous 0..<n (self-healing
    /// any gaps left by `deleteBoard`, which doesn't renumber). Identity moves return BEFORE
    /// opening an undo group, so "drop it back where it was" never eats a ⌘Z step.
    func moveBoards(fromOffsets source: IndexSet, toOffset destination: Int) {
        let boards = fetchBoards().sorted { $0.position < $1.position }
        let ids = boards.map(\.id)
        let newOrder = Reordering.movedWithin(ids, fromOffsets: source, toOffset: destination)
        guard newOrder != ids else { return }
        withUndoGroup("Move Board") {
            applyPositions(newOrder, to: boards)
            save()
        }
    }
```

In `Tack/Models/Board.swift:9`, replace the stale comment:

```swift
    var position: Int          // sidebar order; user-reorderable via drag (B-06)
```

- [ ] **Step 4: Run both suites to verify they pass**

Same command as Step 2. Expected: **TEST SUCCEEDED** — all `BoardStore — Boards` and `Undo/Redo` tests green.

- [ ] **Step 5: Run the full unit suite (guard against cross-suite fallout)**

```sh
pkill -f xcodebuild; pkill -f Tack.app
make unit
```

Expected: **TEST SUCCEEDED**, no failures. (Past ~6 minutes = hang; kill and read the log tail.)

- [ ] **Step 6: Commit**

```sh
git add Tack/Store/BoardStore.swift Tack/Models/Board.swift TackTests/BoardStoreBoardTests.swift TackTests/UndoRedoTests.swift
git commit -m "Add BoardStore.moveBoards — undoable board reorder with gap self-healing (B-06)"
```

---

### Task 3: Wire `.onMove` into `SidebarView`

**Files:**
- Modify: `Tack/Views/Sidebar/SidebarView.swift:26-33` (the `List`)

**Interfaces:**
- Consumes: `store.moveBoards(fromOffsets:toOffset:)` (Task 2); existing `filteredBoards`, `filterQuery`, `selection`.
- Produces: the user-facing feature. No new API. Task 4's UI tests exercise this.

There is no meaningful unit test for a view-modifier wiring — the behavior is covered end-to-end by Task 4's XCUITests (which is why this task and Task 4 are separate commits but one review unit: the feature isn't "verified" until Task 4 runs green).

- [ ] **Step 1: Restructure the List**

In `Tack/Views/Sidebar/SidebarView.swift`, replace lines 26-33:

```swift
            List(filteredBoards, selection: $selection) { board in
                BoardRowView(board: board)
                    .contextMenu {
                        Button("Rename") { renamingBoard = board }
                        Button("Delete", role: .destructive) { boardPendingDeletion = board }
                    }
            }
            .listStyle(.sidebar)
```

with:

```swift
            List(selection: $selection) {
                ForEach(filteredBoards) { board in
                    BoardRowView(board: board)
                        .contextMenu {
                            Button("Rename") { renamingBoard = board }
                            Button("Delete", role: .destructive) { boardPendingDeletion = board }
                        }
                }
                .onMove(perform: moveHandler)
            }
            .listStyle(.sidebar)
```

Then add the handler as a computed property, after `filteredBoards` (line ~16):

```swift
    /// B-06: nil while the sidebar filter is active, which makes rows non-draggable — reordering
    /// a filtered subset is ambiguous relative to the hidden boards. Deliberately the same
    /// emptiness test `BoardStore.filterBoards` uses to return the full array, so "reorder
    /// enabled" and "showing all boards" can never disagree. Passes SwiftUI's `.onMove`
    /// arguments straight through — the index convention is handled in one place
    /// (`Reordering.movedWithin(_:fromOffsets:toOffset:)`), nowhere in the view.
    private var moveHandler: ((IndexSet, Int) -> Void)? {
        guard filterQuery.isEmpty else { return nil }
        return { source, destination in
            store.moveBoards(fromOffsets: source, toOffset: destination)
        }
    }
```

- [ ] **Step 2: Build**

```sh
pkill -f xcodebuild; pkill -f Tack.app
make build
```

Expected: **BUILD SUCCEEDED**.

- [ ] **Step 3: Commit**

```sh
git add Tack/Views/Sidebar/SidebarView.swift
git commit -m "Enable sidebar board drag-reorder via List .onMove, gated off while filtering (B-06)"
```

---

### Task 4: XCUITest end-to-end coverage

**Files:**
- Create: `TackUITests/SidebarReorderUITests.swift`
- Modify: (only if the fallback below triggers) `docs/superpowers/specs/2026-07-07-board-sidebar-reorder-design.md`, `CLAUDE.md`

**Interfaces:**
- Consumes: `TackUITestCase.launch(fixture:)`, `.relaunchPreservingStore()`, `.drag(_:to:targetNormalizedOffset:until:)`, `.poll(timeout:_:)`, `AccessibilityID.board(_:)`, `AccessibilityID.sidebarFilterField`.
- Produces: e2e regression coverage for B-06. Fixture facts the tests rely on: "standard" seeds exactly two boards — "Groceries" (position 0) and "Work" (position 1) — and the letter "o" appears in BOTH names (so a filter of "o" keeps both rows visible for the gate test).

- [ ] **Step 1: Write the UI tests**

Create `TackUITests/SidebarReorderUITests.swift`:

```swift
import XCTest

/// B-06 board sidebar drag-reorder e2e: drag a board row to a new position (order flips,
/// persists across relaunch, and is one ⌘Z step), plus the filter gate (rows are NOT
/// draggable while the sidebar filter is non-empty).
///
/// Order is asserted by comparing row frame `minY` — rows never overlap, so "a above b" is
/// unambiguous. (No `boardIdentifiersByPosition` helper on the base class: a BEGINSWITH
/// "board-" snapshot filter would also match "board-detail" / "board-name-field" /
/// "board-theme-value", and two known rows don't need one.)
final class SidebarReorderUITests: TackUITestCase {

    private let timeout: TimeInterval = 15

    /// Standard fixture order is Groceries, Work. Drag Work above Groceries, assert the
    /// visual order flipped, then relaunch WITHOUT reset and assert the new order persisted.
    func testDragReorderPersistsAcrossRelaunch() {
        launch(fixture: "standard")

        let groceries = boardRow("Groceries")
        let work = boardRow("Work")
        XCTAssertTrue(groceries.waitForExistence(timeout: timeout))
        XCTAssertTrue(work.waitForExistence(timeout: timeout))
        XCTAssertTrue(isAbove(groceries, work), "seeded order should be Groceries, Work")

        // dy 0.1: drop in the TOP portion of the target row so the insertion lands above it.
        drag(work, to: groceries,
             targetNormalizedOffset: CGVector(dx: 0.5, dy: 0.1),
             until: { self.isAbove(work, groceries) })

        XCTAssertTrue(poll(timeout: timeout) { self.isAbove(work, groceries) },
                      "Work should sit above Groceries after the drag")

        relaunchPreservingStore()

        let groceriesAfter = boardRow("Groceries")
        let workAfter = boardRow("Work")
        XCTAssertTrue(workAfter.waitForExistence(timeout: timeout))
        XCTAssertTrue(groceriesAfter.waitForExistence(timeout: timeout))
        XCTAssertTrue(poll(timeout: timeout) { self.isAbove(workAfter, groceriesAfter) },
                      "reordered boards should persist across relaunch")
    }

    /// U-01: the whole reorder is exactly one undo step — a single ⌘Z restores the seeded order.
    func testUndoRestoresOrderAfterDrag() {
        launch(fixture: "standard")

        let groceries = boardRow("Groceries")
        let work = boardRow("Work")
        XCTAssertTrue(groceries.waitForExistence(timeout: timeout))
        XCTAssertTrue(work.waitForExistence(timeout: timeout))

        drag(work, to: groceries,
             targetNormalizedOffset: CGVector(dx: 0.5, dy: 0.1),
             until: { self.isAbove(work, groceries) })
        XCTAssertTrue(poll(timeout: timeout) { self.isAbove(work, groceries) },
                      "the drag must land before undo is meaningful")

        app.typeKey("z", modifierFlags: .command)

        XCTAssertTrue(poll(timeout: timeout) { self.isAbove(groceries, work) },
                      "one ⌘Z should restore the seeded Groceries, Work order")
    }

    /// While the filter is non-empty the `.onMove` handler is nil, so an attempted drag must
    /// not reorder. Filtering by "o" keeps BOTH rows visible (Groceries and Work each contain
    /// an 'o'), so the drag has a real target and the no-op is meaningful.
    func testFilterDisablesReorder() {
        launch(fixture: "standard")

        let groceries = boardRow("Groceries")
        let work = boardRow("Work")
        XCTAssertTrue(groceries.waitForExistence(timeout: timeout))
        XCTAssertTrue(work.waitForExistence(timeout: timeout))

        let filterField = app.descendants(matching: .any)[AccessibilityID.sidebarFilterField]
        XCTAssertTrue(filterField.waitForExistence(timeout: timeout))
        filterField.click()
        filterField.typeText("o")

        XCTAssertTrue(poll(timeout: timeout) { groceries.exists && work.exists },
                      "'o' matches both boards; both rows should stay visible")

        // No `until:` postcondition — the drag is EXPECTED to be a no-op, and a postcondition
        // that never turns true would trigger the helper's one retry for nothing.
        drag(work, to: groceries, targetNormalizedOffset: CGVector(dx: 0.5, dy: 0.1))

        // Give a would-be reorder time to land, then assert it never did.
        Thread.sleep(forTimeInterval: 1.0)
        XCTAssertTrue(isAbove(groceries, work),
                      "order must be unchanged — reorder is disabled while filtering")
    }

    // MARK: - Helpers

    private func boardRow(_ name: String) -> XCUIElement {
        app.descendants(matching: .any)[AccessibilityID.board(name)]
    }

    /// Both rows exist and `a`'s top edge is above `b`'s.
    private func isAbove(_ a: XCUIElement, _ b: XCUIElement) -> Bool {
        a.exists && b.exists && a.frame.minY < b.frame.minY
    }
}
```

- [ ] **Step 2: Regenerate the project (new file)**

```sh
make gen
```

Expected: `xcodegen generate` completes; `Tack.xcodeproj` now includes the new test file.

- [ ] **Step 3: Run the new suite**

```sh
pkill -f xcodebuild; pkill -f Tack.app
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project Tack.xcodeproj -scheme Tack \
  -destination "platform=macOS,arch=$(uname -m)" -derivedDataPath .build/DerivedData \
  -only-testing:TackUITests/SidebarReorderUITests test
```

Expected: **TEST SUCCEEDED**, 3 tests pass.

**Known-risk decision point (from the spec):** the two drag tests drive a native `List` row-reorder through NSTableView's internal drag session, which may prove unautomatable. If a drag test fails, first debug normally (systematic-debugging skill: read the result bundle, try `pressDuration:` 0.8–1.0 via the helper's parameter, check whether the row lifted at all). If after reasonable effort the *drag itself* demonstrably never starts/lands under XCUITest (while working by hand — verify by launching the app manually via `make build` + open, and dragging), apply the spec's fallback: DELETE `testDragReorderPersistsAcrossRelaunch` and `testUndoRestoresOrderAfterDrag`, KEEP `testFilterDisablesReorder` (it only asserts absence of movement), and document the manual-verification stance in the spec's Testing section + a one-line note in CLAUDE.md's Pitfalls. Do NOT loop retrying the same failing drag (the base class already encapsulates the one sanctioned retry).

- [ ] **Step 4: Commit**

```sh
git add TackUITests/SidebarReorderUITests.swift
git commit -m "Add SidebarReorderUITests — drag reorder, persistence, undo, filter gate (B-06)"
```

(If the fallback triggered, also `git add` the spec + CLAUDE.md edits and say so in the commit body.)

---

### Task 5: PRD sync + full-suite ship gate

**Files:**
- Modify: `PRD-Kanban-Board-Mac.md` (three edits: feature table ~line 104, §8 acceptance criteria ~line 380, §9 e2e list ~line 423)

**Interfaces:**
- Consumes: shipped behavior from Tasks 1–4 (the PRD text must describe what actually shipped — if Task 4's fallback triggered, reflect it in the §9 wording as noted below).
- Produces: PRD v1.1 stays the single source of truth; B-06 becomes a referenceable feature ID.

- [ ] **Step 1: Add the feature-table row**

In `PRD-Kanban-Board-Mac.md`, directly after the B-05 row (line ~104, `| B-05 | Board cover image (unsplash integration) | P2 | Post-MVP if time permits |`), insert:

```markdown
| B-06 | Reorder boards in sidebar (drag-and-drop) | P1 | Native macOS row reorder (SwiftUI `List` `.onMove`); disabled while the sidebar filter is active; one undo step (⌘Z); order persists across relaunch. Added post-MVP |
```

- [ ] **Step 2: Add the §8 acceptance criterion**

Directly after the **B-03** story (line ~380, the paragraph beginning `- **B-03 — Board sidebar.**`), insert:

```markdown
- **B-06 — Reorder boards in sidebar.** Given boards A, B, C in that order, when the user drags C to the first position, then the sidebar shows C, A, B, the order persists after relaunch, and a single ⌘Z restores A, B, C. Given the sidebar filter is non-empty, board rows cannot be dragged (reordering is available only in the unfiltered list).
```

- [ ] **Step 3: Extend the §9 e2e drag list**

In the §9 XCUITest paragraph (line ~423), change

```markdown
drag-and-drop (list reorder, card reorder, card move-between-lists)
```

to

```markdown
drag-and-drop (list reorder, card reorder, card move-between-lists, board sidebar reorder)
```

(If Task 4's fallback triggered, instead append to that paragraph a sentence documenting board-reorder drag as manually verified with the filter gate still automated — mirroring the E-01 save-panel note's pattern.)

- [ ] **Step 4: Full-suite ship gate**

```sh
pkill -f xcodebuild; pkill -f Tack.app
make test
```

Expected: **TEST SUCCEEDED** for both TackTests and TackUITests — the whole pyramid green, including all pre-existing suites (the SidebarView restructure in Task 3 must not have regressed BoardCRUDUITests / PersistenceUITests / KeyboardShortcutUITests).

- [ ] **Step 5: Commit**

```sh
git add PRD-Kanban-Board-Mac.md
git commit -m "PRD sync: add B-06 board sidebar drag-reorder (feature row, §8 criterion, §9 e2e)"
```
