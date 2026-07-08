# Board Sidebar Reordering (Drag & Drop) — Design

## Context

Tack's sidebar lists boards sorted by `Board.position`, but that order is frozen at creation time — the PRD v1.1 deliberately left board drag-reorder out of MVP scope (the `Board.position` declaration carries the comment "PRD: no board drag-reorder"). Meanwhile the PRD's undo section (§4.7, U-01) already names "move/reorder of **boards**, lists, and cards" as undoable — a latent inconsistency. This feature adds drag-and-drop reordering of boards in the sidebar, resolving that inconsistency in favor of shipping the feature.

Everything needed already exists: `Board.position` drives the sidebar's `@Query(sort: \Board.position)`, `BoardStore` has the `moveList`/`applyPositions`/`withUndoGroup` pattern to mirror, and `Reordering` holds the pure ordering math. **No schema change or migration is required.**

## Locked decisions (user-confirmed 2026-07-07)

- **Filter gating:** reordering is **disabled while the sidebar filter is active**. Dragging within a filtered subset has ambiguous semantics relative to hidden boards; Finder/Mail-style behavior is to allow manual ordering only in the unfiltered view.
- **Scope: drag-only.** No keyboard shortcut or context-menu move. Matches the list-reorder precedent (L-03 is drag-only); a keyboard path would be a follow-up covering lists and boards consistently.
- **Approach: native `List` + `ForEach` + `.onMove`** (not `Transferable`/`.dropDestination`). The sidebar is a real SwiftUI `List`, where `.onMove` is the platform idiom and provides the native row-reorder interaction (lift, insertion indicator, autoscroll, drop animation) for free. The `Transferable` machinery in `Tack/DragDrop/` exists because the board canvas is a custom `HStack` layout that must build drag-and-drop by hand; using it inside a `List` would fight the native machinery, require hand-built insertion indicators, and risk the destination-shadowing pitfalls documented in CLAUDE.md.

## Design

### 1. Store layer

New method on `BoardStore`:

```swift
func moveBoards(fromOffsets source: IndexSet, toOffset destination: Int)
```

Shape mirrors `moveList(_:to:)`: fetch boards sorted by `position`, compute the new ID order, `applyPositions(_:to:)`, `save()` — all inside a single `withUndoGroup("Move Board")` so the whole reorder is exactly one ⌘Z step (satisfying U-01).

The ordering math is a new pure overload in `Reordering`:

```swift
static func movedWithin<Element>(_ items: [Element], fromOffsets: IndexSet, toOffset: Int) -> [Element]
```

It adopts **SwiftUI's `.onMove` convention** (`IndexSet` of source offsets + pre-removal insertion offset) end-to-end, so the view hands SwiftUI's handler arguments straight through to the store and no index-convention translation exists anywhere — eliminating the classic destination-index off-by-one. To keep `Reordering`'s documented "plain, total, deterministic" contract, the function sanitizes inputs before applying the standard-library `move(fromOffsets:toOffset:)` semantics: source offsets outside `0..<count` are dropped; `toOffset` is clamped to `0...count`; an empty (post-sanitize) source set is the identity.

### 2. View layer

`SidebarView` restructures its list from `List(filteredBoards, selection: $selection)` to:

```swift
List(selection: $selection) {
    ForEach(filteredBoards) { board in
        BoardRowView(board: board)
            .contextMenu { /* unchanged */ }
    }
    .onMove(perform: filterQuery.isEmpty ? moveBoards : nil)
}
```

- macOS provides the full native row-reorder interaction; no custom drag code, no new `Transferable` payload, no accessibility-identifier changes.
- **Filter gate:** the `.onMove` handler is `nil` unless `filterQuery.isEmpty` — deliberately the same emptiness test `BoardStore.filterBoards` uses to return the full array, so "reorder enabled" and "showing all boards" can never disagree. When the handler is `nil`, rows are simply not draggable.
- Selection binding, `BoardRowView`, context menu, rename sheet, and delete confirmation are untouched. (`Board.id` is a `UUID` stored property, so `ForEach`'s implicit `Identifiable` conformance keeps the `UUID?` selection binding working exactly as before.)

### 3. Model, PRD, docs

- **No schema change.** `Board.position` already exists under `TackSchemaV1`; no new schema version or migration stage.
- Delete the stale comment on `Board.position` ("sidebar order == creation order for now (PRD: no board drag-reorder)").
- **PRD amendments:**
  - New feature row **B-06 — Reorder boards in sidebar (drag-and-drop)**, P1, with notes: disabled while the sidebar filter is active; undoable via ⌘Z (single undo step); order persists across relaunch.
  - New §8 acceptance criterion **B-06**: given boards A, B, C (in that order), when the user drags C to the first position, the sidebar shows C, A, B; the order persists after relaunch; ⌘Z restores A, B, C; while the sidebar filter is non-empty, rows cannot be dragged.
  - §9 XCUITest list: add board reorder to the drag-and-drop journeys (with the automation caveat below if it materializes).

### 4. Edge cases

- **Filter active** → handler is `nil`; rows aren't draggable. No error states to design.
- **Zero or one board** → `.onMove` is trivially inert.
- **Multi-select drag** → sidebar selection is single-`UUID` today, but the `IndexSet`-based API handles a multi-row drag correctly for free if selection ever becomes multi.
- **Position gaps** (e.g. after board deletes, which don't renumber) → `movedWithin` operates on array offsets of the position-sorted array, and `applyPositions` rewrites contiguous `0..<n`, so gaps self-heal on the first reorder.

### 5. Testing

**Unit (TackTests):**

- `Reordering.movedWithin(fromOffsets:toOffset:)` semantics: down-move (destination past source), up-move, identity moves, empty set, out-of-range source offsets dropped, out-of-range destination clamped, multi-element `IndexSet`.
- `BoardStore.moveBoards`: reorders and renumbers positions to contiguous `0..<n`; a single undo restores the original order; redo reapplies. Uses `TestContainer(withUndo: true)` with explicit undo grouping per the CLAUDE.md pitfalls (never rely on `groupsByEvent` in headless tests).

**UI (TackUITests):**

- New suite (e.g. `SidebarReorderUITests`): seed a multi-board fixture, drag one board row to a new position using the base class's drag helper, **polling the postcondition before any retry** (per the drag pitfall), assert the new visual order (row frame ordering), then `relaunchPreservingStore()` and assert the order persisted.
- Filter-gate test: type a filter query, attempt the same drag, assert the order is unchanged.

**Known risk (flagged up front):** XCUITest driving a native `List` row-reorder on macOS goes through NSTableView's internal drag session — unlike the custom board-canvas drags already covered by e2e — and may prove flaky or unautomatable. If it does, the fallback is: keep full store-level unit coverage, keep the filter-gate UI test (it only asserts *absence* of movement), and document the reorder drag as manually verified — the same class of documented platform limitation as the PRD's E-01 save-panel note.

**Outcome: the risk materialized.** `SidebarReorderUITests` was implemented with all three tests from this spec; the two drag tests (`testDragReorderPersistsAcrossRelaunch`, `testUndoRestoresOrderAfterDrag`) failed consistently. A `.xcresult` screen-recording review showed the row visually reordering mid-drag (SwiftUI's live drag-over-reorder preview) but the order snapping back to the seeded Groceries/Work on release — the drop never commits. Retrying with `pressDuration`/`holdDuration` tuned to 0.9s/1.0s (per the base class helper's parameters) made no difference. A follow-up review round (2026-07-08) tested the other synthetic-input path: CGEvent-posted drags (`leftMouseDown` → interpolated `leftMouseDragged` steps → hold → `leftMouseUp`, posted via `.cghidEventTap` — hardware-equivalent at the HID level and entirely outside XCUITest's gesture-synthesis pipeline) **also fail to commit the sidebar row drop**; across many parameter variations they never even initiated the reorder preview, while the *identical* CGEvent technique run as a control **did commit** a card reorder on the Spike board's `Transferable`/`.dropDestination` drag path. So the limitation is not "synthetic input doesn't work here" — it is specific to NSTableView's native row-drag session under synthetic input, and the internal mechanism is uninstrumented (an earlier claim that a CGEvent drag committed this reorder could not be reproduced and is superseded by the human verification below). The feature itself is **human-verified working**: on 2026-07-08 the user hand-dragged "Work" above "Groceries" with a real mouse against a fixture-seeded Debug build and the reorder stuck. To re-verify manually in ~30 seconds: `open .build/DerivedData/Build/Products/Debug/Tack.app --args --uitest --fixture standard --store-name humancheck --reset`, then drag Work above Groceries in the sidebar — the order should stick, and persist if you relaunch the same command without `--reset` (afterwards, delete the `humancheck.sqlite*` store under the sandbox's `Application Support/UITest/`). Per the fallback: `testDragReorderPersistsAcrossRelaunch` and `testUndoRestoresOrderAfterDrag` were deleted from `TackUITests/SidebarReorderUITests.swift`; `testFilterDisablesReorder` (which only asserts absence of movement, so it isn't exposed to this limitation) was kept and passes. Unit coverage (`Reordering`, `BoardStore.moveBoards`, including its one-undo-step behavior) remains the automated regression backstop.

## Out of scope

- Keyboard or context-menu board reordering (possible follow-up together with list keyboard-reorder).
- Reordering while a filter is active.
- Any change to list/card drag-and-drop or to the `Tack/DragDrop/` machinery.
