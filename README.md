# Kanban

A native macOS kanban board — boards → lists → cards, drag-and-drop, labels, due dates, board
themes, keyboard-driven end to end. SwiftUI + SwiftData, macOS 14+.

## Build / run / test

Requires **Xcode 16+** (macOS 14 SDK) and [XcodeGen](https://github.com/yonaskolb/XcodeGen):

```
brew install xcodegen
```

The `.xcodeproj` is generated, not checked in — `project.yml` is the source of truth. **After
adding/removing/renaming any source file, regenerate the project:**

```
make gen      # xcodegen generate
```

Then:

```
make build    # xcodebuild build
make unit     # KanbanTests only (Swift Testing)
make ui       # KanbanUITests only (XCTest/XCUITest)
make test     # unit + ui
```

The Makefile pins `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`. On a machine where
`xcode-select` points at the Command Line Tools instead of a full Xcode install (`xcodebuild`
needs the full Xcode, CLT alone won't run the test targets), this makes `make` work regardless of
the global `xcode-select` state; override it if Xcode lives somewhere else.

To open in the IDE instead: `make gen && open Kanban.xcodeproj`.

### Running the app manually

`open .build/DerivedData/Build/Products/Debug/Kanban.app` after `make build`, or run it from
Xcode. Test-only launch flags (`--uitest --fixture <name> --store-name <name> --reset
--appearance light|dark`) are parsed by `AppLaunchConfig` and are inert for a normal launch — see
`KanbanUITestCase.launch` for how the UI suite uses them.

### UI-test requirements (read before running `make ui`)

- **Quiet machine.** XCUITest drives real keystroke/click synthesis through Accessibility. On a
  busy machine (heavy CPU load, another app grabbing keyboard focus, the screen locking mid-run)
  keystroke delivery can stall or drop, producing flaky failures that have nothing to do with the
  code under test. Run the UI suite on an otherwise-idle machine with the screen unlocked and
  awake for the duration.
- **One-time automation permission.** The first `make ui` (or any XCUITest run) on a machine
  prompts macOS for Accessibility/Automation permission for the test runner. Grant it once,
  interactively, before expecting `make ui` to succeed non-interactively (e.g. in CI).
- Prefer running the UI suite serially (`-parallel-testing-enabled NO`, already set by `make ui`)
  and, for a large run, splitting by suite (`-only-testing:KanbanUITests/<SuiteName>`) rather than
  one long invocation — easier to triage, and this codebase's own development process did exactly
  that for every milestone gate.

## Architecture

Four layers, dependencies point strictly downward:

1. **Models (`Kanban/Models/`, `@Model`)** — persistent state only: `Board`, `BoardList`, `Card`,
   `CardLabel`, `LabelColor`, `BoardTheme`. SwiftData relationships are unordered, so parents
   expose `sortedLists`/`sortedCards` computed properties — nothing reads raw relationship arrays
   for order.
2. **Pure logic (`Kanban/Store/*.swift`, `Kanban/DragDrop/DropMath.swift`)** — zero SwiftUI/SwiftData
   imports, the TDD core: `Reordering` (position math), `DropMath` (drop point → insertion index),
   `DueDateStatus` (urgency from an injected clock), `SelectionNavigation` (keyboard
   selection/move math over a plain `BoardSnapshot`), `LabelFilter` (OR-semantics card filtering).
   Exhaustively unit-tested without a `ModelContainer`.
3. **`BoardStore` (`Kanban/Store/BoardStore.swift`, `@MainActor @Observable`)** — the *only*
   mutation surface: board/list/card CRUD, moves, label toggles, due dates. Wraps multi-write
   operations in explicit undo groups so one ⌘Z reverses one user action. Injected via
   `.environment`; views never write models directly.
4. **Views (`Kanban/Views/`) + Commands (`Kanban/Commands/`)** — `RootView` (sidebar +
   `NavigationSplitView` detail), `BoardView`/`ListColumnView`/`CardView` (the board surface,
   production drag-and-drop), `CardDetail/` (title/description/labels/due date sheet).
   `AppCommands` is the single source of truth for every keyboard shortcut: each has a visible
   View/Card/Edit/File menu item, gated via `@FocusedValue` (`FocusedValues.swift`) so enablement
   and the text-input/sheet guard live in one place.

**Drag-and-drop** is native SwiftUI (`.draggable`/`.dropDestination` + `Transferable`), proven in
an early de-risking spike (`Views/Spike/`) before any production UI was built on top of it. Its
container/row/footer destination split is FROZEN as of that spike — see the doc comment atop
`ListColumnView` for the empirically-derived coexistence rules (why a card row's destination and
the column's own list-reorder destination can't be restructured casually). Later features that
touch the board surface (e.g. the M11 label filter) deliberately filter only what's *rendered*;
every drop-index computation still reasons about the full, unfiltered card list — see
`ListColumnView.cardList`'s doc comment.

**Undo/redo** rides SwiftData's automatic undo registration (`modelContext.undoManager` wired to
the scene's `@Environment(\.undoManager)`); the system Edit ▸ Undo/Redo items work for free.
`BoardStore` groups multi-write operations explicitly so a single gesture is a single undo step.

## Tests

- **`KanbanTests`** (Swift Testing, no UI): one suite per pure-logic/store area — reordering, drop
  math, due-date status, board/list/card CRUD, cascade delete, label seeding/toggling/filtering,
  selection navigation, undo/redo, and more. Fast, no `ModelContainer` needed for the pure-logic
  suites; an in-memory `ModelContainer` (`Helpers/TestContainer.swift`) backs the store-level ones.
- **`KanbanUITests`** (XCTest/XCUITest): one file per user-facing journey — board CRUD, list CRUD,
  card CRUD, drag-and-drop, card detail, keyboard shortcuts, label filter, board themes, list
  collapse, due-date badges, persistence across relaunch, and a launch smoke test. Deterministic
  fixtures (`FixtureSeeder`: "empty", "standard", "spike") seed an on-disk, per-test SwiftData
  store (`KanbanUITestCase.launch`), so tests never depend on run order or leftover state.

Run everything with `make test`; see the UI-test requirements above before running `make ui`.

## Roadmap (deferred / P2)

Out of scope for the shipped feature set, tracked here for later:

- **Apple Reminders sync** — two-way sync via EventKit/`EKReminder`; needs
  `NSRemindersUsageDescription` and a user-facing permission flow.
- **Spotlight search** — index boards/cards via Core Spotlight so cards are findable
  system-wide.
- **Checklists** — sub-item checklists within a card (Trello-parity feature).
- **Attachments** — file/image attachments on a card.
- **Trello import** — one-time import from a Trello JSON board export (lists, cards, labels).
- **Board cover images** — a per-board header image, independent of the theme system.
- **Optional due-date times** — `Card.includesTime` is already schema-ready (V1, no migration
  needed); the UI currently only ever sets it `false` (date-only, stored as `startOfDay`). Adding
  a time-of-day picker is additive.
- **Soft-delete/restore for boards** — board deletion is intentionally NOT undoable today (a
  SwiftData cascade-delete undo snapshot is fatal to assert on this stack); a soft-delete +
  restore flow would give users a safety net without fighting that platform limitation.
- **Named labels** — today labels are a fixed 8-color palette (`LabelColor`) with no text; custom
  names would improve accessibility (VoiceOver currently only ever hears a color name) and bring
  the model closer to Trello parity.
- **Collaboration / sync** — multi-device or multi-user sync is entirely out of scope; the app is
  single-user, single-Mac, local-SwiftData-store only.
