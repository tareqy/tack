# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Native macOS Tack app — a kanban board, Trello replacement: SwiftUI + SwiftData, macOS 14+, single-user, local-only, App Sandbox on. The spec is `PRD-Kanban-Board-Mac.md` (feature IDs like C-08, U-01 referenced in commits/comments come from it); the design doc is `docs/superpowers/specs/2026-07-05-kanban-mac-app-design.md`.

## Commands

`Tack.xcodeproj` is **gitignored and generated** — after adding/removing/renaming source files or editing `project.yml`, run:

```sh
make gen          # xcodegen generate
```

```sh
make build        # build the app
make unit         # unit tests (TackTests, Swift Testing)
make ui           # UI tests (TackUITests, XCUITest; serial, result bundle in .build/results/)
make test         # unit + ui
```

Single test (note `DEVELOPER_DIR` — `xcode-select` on this machine points at Command Line Tools only, so every bare `xcodebuild` needs it; the Makefile exports it for you):

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project Tack.xcodeproj -scheme Tack \
  -destination "platform=macOS,arch=$(uname -m)" -derivedDataPath .build/DerivedData \
  -only-testing:TackTests/BoardStoreCardTests test          # a suite
# -only-testing:TackTests/BoardStoreCardTests/addCardAppends  # one test
# -only-testing:TackUITests/CardCRUDUITests                   # a UI suite
```

Manual hand-test against a scratch store (never touches real data):

```sh
open .build/DerivedData/Build/Products/Debug/Tack.app --args --uitest --fixture standard --store-name scratch --reset
```

### xcodebuild process rules

- Run `xcodebuild` in the **foreground** and read complete output. Background runs orphan themselves; concurrent runs deadlock on the shared DerivedData lock.
- Before any run: `pkill -f xcodebuild; pkill -f Tack.app`.
- A unit-test run past ~6 minutes is a **hang, not a slow run** (classically an NSUndoManager exception killing the Swift Testing runner — see Pitfalls). Kill it and read the log tail for a FAULT line.
- UI runs are legitimately slow: `make ui`/`make test` ≈ 20–25 min (74 tests, serial). `tee` xcodebuild output to a log under `.build/` and read it to completion — long foreground commands can get auto-backgrounded, and an unread gate is not a gate.

## Architecture

Three targets (defined in `project.yml`): `Tack` (app), `TackTests` (Swift Testing, unit), `TackUITests` (XCUITest — also compiles `Tack/Support/AccessibilityID.swift` so test code shares the app's identifier constants).

### Layers

- `Tack/Models/` — SwiftData `@Model` entities (Board → BoardList → Card, plus CardLabel) under a **versioned schema** (`TackSchema.swift`: `TackSchemaV1` + migration plan). Schema changes need a new version + migration stage.
- `Tack/Store/BoardStore.swift` — the **only mutation surface** for the model graph. Every method wraps its writes + save in exactly one explicit undo group (`withUndoGroup`), so each store call is one user-facing ⌘Z step. Pure ordering/selection logic lives beside it (`Reordering`, `SelectionNavigation`, `SelectionRestore`, `DropMath` in DragDrop) as free functions unit-tested without a container. Views never write to `ModelContext` directly.
- `Tack/Store/ModelContainerFactory.swift` — three containers: `production()` (on-disk), `inMemory()` (unit tests), `uiTest(storeName:reset:)` (on-disk per-test store under the sandbox's `Application Support/UITest/`).
- `Tack/Views/` — `RootView` (NavigationSplitView: `Sidebar/` + `Board/`), `CardDetail/`, shared `Components/`. `Views/Spike/` is a minimal board kept alive as the drag-and-drop e2e regression path.
- `Tack/Commands/` — menu-bar commands (`AppCommands`), attached at the WindowGroup **scene** level (commands registered inside the split view never register). `FocusedValues.textInputFocused` gates editing commands (see Pitfalls).
- `Tack/DragDrop/` — `Transferable` payloads (`CardTransfer`, `ListTransfer`) + `DropMath`. **Architecture invariant:** SwiftUI `.dropDestination` does not dispatch by payload type — a destination swallows every drag landing on it, and stacked different-typed destinations shadow each other. Hence: column container accepts ListTransfer only, card rows accept CardTransfer, and the list footer is ONE dual-import destination (`ColumnDropPayload`) that routes both. Do not refactor back to "one typed destination per payload". (Sidebar board reorder deliberately uses native `List` `.onMove` instead of this machinery — see Pitfalls.)

### Launch paths (`TackApp.init` branches on `AppLaunchConfig`)

- **Production:** on-disk container; failure to open shows `DatabaseErrorView` instead of crashing.
- **`--uitest`:** per-test on-disk store (`--store-name`), seeded by `FixtureSeeder` (`--fixture standard|spike|...`), optionally wiped (`--reset`), appearance forced via `--appearance light|dark`. Animations are stripped for determinism.
- **`--uitest --fixture spike`:** boots `SpikeBoardView` directly (drag regression path).

### UI-test harness

Subclass `TackUITestCase`. `launch(fixture:)` gives each test its own named on-disk store (and clears its namespaced selection UserDefaults key); `relaunchPreservingStore()` relaunches without `--reset` to assert persistence. Query elements by `AccessibilityID` constants. Use the base class's drag helper rather than raw `press(forDuration:thenDragTo:)`.

## Pitfalls (hard-won — check before "fixing")

- **NSUndoManager in unit tests:** no run loop is pumped, so `groupsByEvent` never opens a group; a `registerUndo` outside explicit begin/end grouping throws, and under Swift Testing that **hangs the runner forever**. This rule is asymmetric with the running app: `TestContainer` sets `groupsByEvent = false` for headless unit tests (no run loop to open event groups), but the app's window undo manager keeps the default `groupsByEvent = true` — forcing it false there crashed on-disk SwiftData registrations that happen outside BoardStore's explicit groups (autosave, relationship maintenance; see the M7 crash evidence at `RootView.wireUndoManager`). `BoardStore.init`'s own `groupsByEvent = false` line is therefore a no-op in the app (the window's undo manager is attached later, in `RootView.wireUndoManager`) and only takes effect in tests. What both modes actually rely on is `BoardStore`'s explicit per-operation grouping; keep that when adding undoable mutations, and use `TestContainer(withUndo: true)` in tests.
- **Board delete is not undoable** — SwiftData fatally asserts when undo-snapshotting an on-disk cascade delete of a Board. `BoardStore.deleteBoard` detaches the undoManager around the delete and clears the stack; the PRD documents this. Don't "fix" it by re-enabling undo there.
- **No window on `--uitest` launch:** macOS doesn't auto-present the WindowGroup window under XCUITest; `TackUITestCase.ensureWindow` (⌘N nudge) handles it — always launch through the base class.
- **`.accessibilityIdentifier` on an ancestor shadows child ids** — never identify an ancestor of a container you query by id (this is why `RootView` hangs `root-view` off a sibling `Color.clear`).
- **Drag retries must poll the postcondition** before retrying; an instant `.exists` check triggers a spurious second drag that corrupts state.
- **`Reordering.movedWithin` has two overloads with different destination conventions:** `(from:to:)` takes the target index in the *resulting* array (used by `moveList`/`moveCard`); `(fromOffsets:toOffset:)` takes SwiftUI's *pre-removal* insertion offset (used by `moveBoards`). `.onMove` handlers must use the offsets overload — the index one silently off-by-ones down-moves.
- **Native `List` `.onMove` row-reorder cannot be driven by synthetic input** (confirmed for the B-06 sidebar): under XCUITest's `press(forDuration:thenDragTo:)` the row lifts and live-previews the reorder, but the drop never commits; CGEvent drags (posted at the HID event tap, `.cghidEventTap`) fail harder — they never even initiate the reorder preview — while the *same* CGEvent technique commits the board-canvas `Transferable` drag fine. So the limitation is NSTableView's native row-drag session under synthetic input (internal mechanism uninstrumented). Human-verified working with a real mouse (2026-07-08; 30-second procedure in the B-06 spec's Testing section). `SidebarReorderUITests` keeps only the filter-gate test; the reorder logic is unit-covered (`Reordering`, `BoardStore.moveBoards`), not e2e-covered.
- **Text-input focus detection:** `firstResponder` is useless in SwiftUI here (always a private proxy). The working pattern is the `textInputFocused` `@FocusedValue` published by every TextField/TextEditor, plus an action-level re-check including `NSApp.keyWindow?.isSheet`. New text fields must publish it or menu shortcuts will fire while typing.
