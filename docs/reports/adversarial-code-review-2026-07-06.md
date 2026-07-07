# Adversarial Code Review - 2026-07-06

## P0 traceability matrix

| Feature ID | Status | Implementation | Unit tests | UI tests | Notes |
|---|---|---|---|---|---|
| B-01 | PARTIAL | `Kanban/Store/BoardStore.swift:47`, `Kanban/Views/Sidebar/CreateBoardSheet.swift:42` | `BoardStoreBoardTests`, `UndoRedoTests` | `BoardCRUDUITests`, `PersistenceUITests` | Default lists covered; UI create test does not verify created board's default lists. |
| B-02 | PARTIAL | `Kanban/Store/BoardStore.swift:63`, `Kanban/Views/Sidebar/SidebarView.swift:40` | `BoardStoreBoardTests`, `CascadeDeleteTests` | `BoardCRUDUITests` | Board delete is correctly not undoable; no UI relaunch/delete-persistence or "undo does not restore deleted board" assertion. |
| B-03 | IMPLEMENTED | `Kanban/Views/Sidebar/SidebarView.swift:18`, `Kanban/Views/RootView.swift:151` | `SelectionRestoreTests`, filter tests | `BoardCRUDUITests`, `PersistenceUITests` | Search, empty state, selection restore covered. Sidebar collapse persistence unclear/unverified. |
| L-01 | PARTIAL | `Kanban/Store/BoardStore.swift:139`, `Kanban/Views/Board/AddListButton.swift:24` | `BoardStoreListTests` | `ListCRUDUITests`, `PersistenceUITests` | Create/persist covered in full journey. |
| L-02 | PARTIAL | `Kanban/Store/BoardStore.swift:151`, `Kanban/Views/Board/ListColumnView.swift:145` | `BoardStoreListTests` | `ListCRUDUITests` | Confirmation covered; undo after confirmed list delete is not UI-tested. |
| L-03 | IMPLEMENTED | `Kanban/Views/Board/ListColumnView.swift:139`, `Kanban/Store/BoardStore.swift:173` | `ReorderingTests`, `DropMathTests` | `DragAndDropUITests` | Reorder and relaunch covered. |
| C-01 | PARTIAL / SPEC MISMATCH | `Kanban/Views/Board/ListColumnView.swift:315`, `Kanban/Views/Board/BoardView.swift:192` | `BoardStoreCardTests`, `NewCardTargetTests` | `CardCRUDUITests`, `KeyboardShortcutUITests` | Add row, double-click, Cmd+N covered; Return while list-focused is missing. |
| C-02 | SPEC MISMATCH | `Kanban/Views/Board/CardView.swift:51` | `BoardStoreCardTests` | `CardCRUDUITests`, `CardDetailUITests` | PRD says click-to-edit; implementation is double-click/context menu. |
| C-03 | IMPLEMENTED | `Kanban/Views/Board/CardView.swift:95`, `Kanban/Store/BoardStore.swift:245` | `DropMathTests`, `BoardStoreCardTests` | `DragAndDropUITests` | Reorder and relaunch covered. |
| C-04 | IMPLEMENTED | `Kanban/Views/Board/CardView.swift:176`, `Kanban/Views/Board/ListColumnView.swift:404` | `BoardStoreCardTests`, `UndoRedoTests` | `DragAndDropUITests`, `CardCRUDUITests` | Drag, empty-list drop, context menu covered. |
| C-05 | IMPLEMENTED | `Kanban/Store/BoardStore.swift:228`, `Kanban/Commands/AppCommands.swift:40` | cascade/position tests | `KeyboardShortcutUITests`, `CardCRUDUITests` | No dialog and undo/redo covered for card delete. |
| C-06 | PARTIAL | `Kanban/Views/CardDetail/CardDetailView.swift:41`, `Kanban/Store/BoardStore.swift:338` | `BoardStoreCardTests` | `CardDetailUITests` | Description persistence covered; line-break persistence and saving detail-title edit are thin. |
| C-07 / LB-02 | IMPLEMENTED | `Kanban/Views/CardDetail/LabelPicker.swift:27`, `Kanban/Store/BoardStore.swift:302` | `LabelTests`, `LabelFilterTests` | `CardDetailUITests` | Add/remove/multi-label covered. |
| C-08 / D-01 | PARTIAL | `Kanban/Views/CardDetail/DueDatePicker.swift:16`, `Kanban/Store/BoardStore.swift:316` | `LabelTests`, `DueDateQuickOptionTests` | `CardDetailUITests` | Quick options covered; arbitrary DatePicker path starts hidden when due date is nil. |
| C-10 | PARTIAL / SPEC MISMATCH | `Kanban/Store/SelectionNavigation.swift:31`, `Kanban/Commands/AppCommands.swift:100` | `SelectionNavigationTests` | `KeyboardShortcutUITests` | Pure left/right logic exists, but AppCommands exposes only up/down bare-arrow selection. |
| C-11 | IMPLEMENTED | `Kanban/Commands/AppCommands.swift:47`, `Kanban/Views/Board/BoardView.swift:210` | `SelectionNavigationTests`, `UndoRedoTests` | `KeyboardShortcutUITests` | Cmd-arrow moves and undo covered. |
| LB-01 | IMPLEMENTED | `Kanban/Store/BoardStore.swift:34`, `Kanban/Store/FixtureSeeder.swift:16` | `LabelTests`, `FixtureSeederTests` | indirectly via detail tests | Exactly 8/idempotent covered. |
| D-02 / D-03 | PARTIAL | `Kanban/Views/Components/DueDateBadge.swift:22`, `Kanban/Views/Components/DueDateBadgeStyle+Color.swift:23` | `DueDateStatusTests`, `DueDateBadgeStyleTests` | `BadgeUITests` | Semantics covered by accessibility suffix; actual color/pixel verification is outside checked-in tests. |
| E-01 | UNIMPLEMENTED | none found; `Kanban/Commands/AppCommands.swift:22` has no Export | none | none | P0 export path absent. |
| U-01 | PARTIAL | `Kanban/Store/BoardStore.swift:397`, `Kanban/Views/RootView.swift:117` | `UndoRedoTests` | `KeyboardShortcutUITests`, `BoardCRUDUITests` | Not all mutations covered; app undo grouping intentionally violates documented `groupsByEvent=false` invariant. |

## Executive summary

Ship readiness: **Red**

- P0 JSON export is not implemented at all.
- P0 keyboard-only promises are incomplete: C-10 lacks left/right UI command wiring, and Return-on-focused-list creation is missing.
- P0 inline card title editing does not match the PRD interaction contract.
- Undo behavior has real drift from the repository's own non-negotiable invariant.
- Persistence failures are silently swallowed in `BoardStore.save()`, which can create false UI success.

Top 5 risks by user impact:

1. Users cannot export data despite export being the anti-lock-in MVP promise.
2. Keyboard-only/VoiceOver workflow is incomplete for selection and export.
3. Undo correctness is only partially proven and has architecture exceptions.
4. Save/fetch failures can silently lose or misrepresent persisted state.
5. Several acceptance criteria pass only through indirect/happy-path tests.

## Findings table

| ID | Severity | Category | Location | Issue | Evidence | Recommendation | PRD ref |
|---|---|---|---|---|---|---|---|
| F-001 | P0 | Spec compliance | `Kanban/Commands/AppCommands.swift:22` | JSON export is absent. | File menu only defines New Card/List/Board; repository search for `Export`, `json`, `fileExporter`, and `NSSavePanel` finds no export feature code. | Add export DTOs, menu item, save panel/fileExporter, sandbox write path, unit parse test, UI export test. | E-01 |
| F-002 | P0 | Spec compliance / A11y | `Kanban/Commands/AppCommands.swift:100` | Bare left/right keyboard selection is not wired. | Commands expose Select Previous/Next only; pure logic supports `.left/.right`. | Add left/right selection commands and UI tests crossing adjacent lists. | C-10, N-06 |
| F-003 | P0 | Spec compliance | `Kanban/Views/Board/ListColumnView.swift:311` | Return while a list is focused does not create a card. | Only add-row submit and Cmd+N token open the editor; no focused-list Return command exists. | Define list focus, publish focused list, wire Return to existing add-card editor. | C-01 |
| F-004 | P0 | Spec compliance | `Kanban/Views/Board/CardView.swift:51` | Inline title edit requires double-click/context menu, not click. | `beginEditOn: .doubleClick`; single click selects. | Either update PRD or implement click-to-edit without breaking selection. | C-02 |
| F-005 | P1 | Architecture | `Kanban/Commands/AppCommands.swift:23` | Command guard is incomplete. | New Card/List/Board and Cmd+1..9 bypass `guardedMutation`; only delete/move/filter/select up/down use it. | Route all mutating/navigation commands through text/sheet guard or explicitly document exceptions and test them. | U-01 / commands |
| F-006 | P1 | Architecture / Correctness | `Kanban/Views/RootView.swift:117`, `Kanban/Store/BoardStore.swift:266` | Undo invariant is violated/contradicted. | RootView deliberately keeps `groupsByEvent=true`; cross-list move bypasses `withUndoGroup` with manual undo. | Reconcile invariant vs implementation, then add app-level undo grouping tests for mixed operations. | U-01 |
| F-007 | P0 | Correctness | `Kanban/Store/BoardStore.swift:444` | Persistence errors are swallowed. | `try? context.save()` and `try? fetch` fall back silently. | Make saves/fetches throw or surface an error state; assert/fail in tests. | N-03 |
| F-008 | P1 | Testing | `KanbanTests/UndoRedoTests.swift:98` | Undo depth test is too narrow. | 50-step test covers only `createBoard`; no exhaustive undo/redo for list delete, card title, labels, due dates, theme, mixed stack. | Add a table-driven undo contract suite over every undoable store mutation except board delete. | U-01 |
| F-009 | P1 | Performance / Testing | `PRD-Kanban-Board-Mac.md:426` | NFRs are mostly unverified. | No 500-card fixture, cold launch timing, autosave-under-force-quit, or fps test found. | Add repeatable smoke/perf harnesses or mark NFRs as manually verified with scripts. | N-01..N-06 |

## Architecture audit

- BoardStore only mutation surface: **Pass with caveat**. Views route writes through store; `FixtureSeeder` writes direct only for test seeding/spike.
- Every mutation one explicit undo group, `groupsByEvent=false`: **Fail**. App wiring keeps default event grouping; cross-list move uses manual registration.
- Board delete not undoable: **Pass**. `BoardStore.deleteBoard` detaches undo and clears stack.
- Drag/drop destination layout frozen: **Pass** for expanded board; collapsed pill is additive and uses the documented dual-import pattern.
- Label filter render-only: **Pass**. `ListColumnView` renders filtered cards but drop math uses full lists.
- Commands at WindowGroup and gated by FocusedValue/sheet: **Partial**. Scene-level placement is correct; guard coverage is incomplete.
- SwiftData unordered relationships sorted by `position`: **Pass mostly**. Ordering reads use `sortedLists`/`sortedCards`; raw arrays are used mainly for counts.
- UI tests base launch/access IDs/drag polling: **Pass**. Harness uses fixture launch and postcondition polling.

## Test quality audit

False confidence tests:

- `make unit` passed, but unit scope cannot detect missing export UI or command shortcuts.
- D-03 tests assert semantic suffixes, not actual rendered colors.
- U-01's 50-step depth test covers one operation type only.

Missing edge cases:

- Export JSON creation/reparse.
- Return on focused list, bare left/right selection.
- List delete undo in UI.
- Mixed undo stack across labels/due dates/list/card operations.
- Filter plus drag/drop behavior.
- Description line breaks.
- 500-card board and force-quit autosave.

UI determinism risks:

- Harness is generally strong, especially drag postcondition polling.
- Some tests still use fixed sleeps (`KeyboardShortcutUITests` guard test), which can hide timing races.

## Security & sandbox

Sandbox entitlements are present in `project.yml` and `Kanban/Kanban.entitlements`. No network/sandbox escape found. The export entitlement is unused because E-01 is absent. Production container open failure is handled, but mutation save failures are not surfaced.

## Performance & NFR

- N-01 cold launch: unverified.
- N-02 500-card 60fps drag/scroll: unverified.
- N-03 autosave/crash safety: weakened by swallowed `save()` errors; no force-quit test.
- N-04 undo depth: partially verified with 50 board creates only.
- N-05 keyboard-only: fails today because export is absent and C-10/C-01 keyboard paths are incomplete.
- N-06 VoiceOver: only indirectly supported via keyboard movement; no VoiceOver/readability audit.

## Positive observations

- Store mutation surface is mostly well centralized.
- Drag/drop coexistence rules are unusually well documented and regression-tested.
- SwiftData schema is versioned from v1.
- UI test fixture isolation and relaunch-preserving store design are solid.
- Card detail staging gives a clean single-commit model.

## Suggested review order for follow-up passes

1. `Kanban/Commands/**`, `Kanban/Views/Board/**`: keyboard-only compliance.
2. `Kanban/Store/BoardStore.swift`, `Kanban/Views/RootView.swift`: undo grouping contract.
3. New `Kanban/Export/**`: E-01 design and sandboxed save panel.
4. `Kanban/Store/**`: error propagation and persistence failure handling.
5. `KanbanUITests/*`: acceptance-criterion gaps and flake hardening.
6. `Kanban/Views/CardDetail/**`: due date picker and line-break behavior.
7. `Kanban/Views/Board/**`: filter plus drag/collapse interactions.
8. NFR harness: 500-card fixture, cold launch timing, force-quit autosave.

## Verification

- Ran `make unit`: passed, 192 tests.
- Did not run the full UI suite.
