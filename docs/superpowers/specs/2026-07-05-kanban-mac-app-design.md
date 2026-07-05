# Kanban Board — Native Mac App: PRD Revision + Full Development & E2E Test Plan

## Context

Tareq has a draft PRD (`PRD-Kanban-Board-Mac.md`, v1.0) for a local-first native macOS Kanban app — a Trello replacement built on boards → lists → cards. The repo is greenfield: the PRD is the only file. The request is threefold:

1. Review the PRD and fix/improve it (a 6-lens multi-agent review with adversarial verification is producing confirmed findings).
2. Plan the full development of the app.
3. Plan end-to-end testing.

## Locked decisions (user-confirmed 2026-07-05)

- **Stack:** SwiftUI + SwiftData, **minimum macOS 14 (Sonoma)** — raised from the PRD's macOS 13 floor because SwiftData requires macOS 14. Resolves the PRD's A-01 contradiction.
- **Distribution:** local personal builds only (xcodebuild / Xcode run). App Sandbox stays **on** so notarization/App Store remain possible later; no signing/notarization work planned.
- **Scope:** Phase A = all MVP P0 features; Phase B = P1 features (board themes, list collapse, urgency colors, label filter, dark-mode polish). P2 = roadmap notes only.
- **Testing:** full pyramid — TDD unit tests on model/store layer + XCUITest e2e for core journeys (CRUD, drag-and-drop, keyboard shortcuts, relaunch persistence). Everything headless via `xcodebuild`.

## Part 1 — PRD revisions (produce PRD v1.1 as the first implementation step)

Findings from a 6-lens review (consistency, feasibility, HIG/UX, data model, testability, product), each adversarially fact-checked — 45/46 findings confirmed. Edit `PRD-Kanban-Board-Mac.md` to v1.1 with:

### Critical fixes
1. **§6 + A-01 — stack contradiction:** SwiftData requires macOS 14; A-01 says macOS 13. Fix per locked decision: macOS 14+, SwiftData.
2. **C-08 vs D-01 — due-date time contradiction:** C-08 says "optional time", D-01 says "date only". Fix: **date-only MVP UI**; overdue = past start-of-day local time; schema carries an `includesTime` flag (default false) so optional time lands later with no migration.
3. **§6 — data model not implementable:** add `Board.icon` (emoji, required by B-01), `Board.position` + timestamps, `List.createdAt`; labels = fixed 8-color enum stored per card (`Set<LabelColor>`) — confirmed as the PRD's consistent intent; optional label *names* deferred to P1 (accessibility/Trello parity). Replace integer `position` re-numbering with an explicitly specified ordering strategy (see Part 2). Define cascade deletes (board → lists → cards) and commit to schema versioning from v1.
4. **§3 vs §7 — "small teams" segment unserved:** move teams to post-MVP; add **JSON export/backup to MVP** (also fixes the lock-in hypocrisy in §2 and the single-unexportable-copy risk).
5. **§1 — vision overpromises:** Spotlight + Reminders sync headline the vision but are P2/v1.1. Rewrite §1 around the MVP; move those to a roadmap line.
6. **A-04 — drag-and-drop misspecified:** "SwiftUI `DragGesture` / NSDraggingSource" mixes incompatible layers. Specify SwiftUI `.draggable`/`.dropDestination` + `Transferable`; schedule an early de-risking spike (Part 3, M2).

### Section-level fixes
- **C-05:** card delete = **undoable, no confirmation dialog** (NSUndoManager, ⌘Z — the Finder ⌘⌫ pattern); board/list deletes keep confirmation (bigger blast radius) and are also undoable. Adds undo/redo as an explicit MVP feature (was entirely missing; flagged by 3 reviewers).
- **Shortcuts:** ⌘N = new *card* (primary-object convention per Things/OmniFocus), ⇧⌘N = new board, ⌥⌘N = new list (replaces the undiscoverable bare `+`); one canonical card-creation flow ("+ Add card" row at list bottom) with double-click/Return aliases; define the focus model. **All shortcuts live in the menu bar** (SwiftUI `Commands`) for discoverability/HIG compliance.
- **Keyboard navigation + keyboard card-move** (arrow keys, ⌘+arrows): required to make story 5 true and to keep VoiceOver users from being locked out by drag-only movement.
- **Dark mode → MVP baseline** (nearly free in SwiftUI; can't practically be "deferred" anyway).
- **D-03:** tomorrow = amber (green reads as "done"); overdue cutoff defined explicitly.
- **D-04:** correct `remindctl`/`eventkitd` → EventKit framework (`EKReminder`) + `NSRemindersUsageDescription`.
- **Story 3 traceability:** cites C-04/C-05/C-06 → should be C-03/C-04. **Story 4** depends on D-03 (P1) → pull D-03 into MVP scope (it's trivial once badges exist).
- **A-02:** false on first launch → replace with a specified empty-state/onboarding flow ("Create your first board").
- **Appendix matrix:** regenerate from section tables (currently contradicts B-04/dark-mode/D-04 priorities).

### New PRD sections
- **§9 Acceptance criteria & testing:** Given/When/Then per P0 feature + Definition of Done.
- **§10 Success metrics & NFRs:** cold launch < 1s; 500-card board scrolls/drags at 60fps; autosave/crash-safety; undo depth.
- **§8 addition:** distribution/sandboxing constraint (local builds, App Sandbox on, no signing).
- **Roadmap note:** Trello import (P1) — table stakes for the "Trello refugee" segment, feasible from Trello's JSON export.

## Part 2 — Architecture & project scaffold

### Project generation: XcodeGen
`brew install xcodegen`; declarative `project.yml` is the source of truth, `.xcodeproj` is generated and gitignored. Chosen over Tuist (heavier, more failure modes), hand-written pbxproj (error-prone), and SwiftPM (cannot declare a `bundle.ui-testing` target — hard requirement). **Rule: after any file add/remove, run `xcodegen generate`.**

Key `project.yml` settings: `deploymentTarget: macOS 14.0`; `SWIFT_VERSION: 5.0` (Swift-5 language mode on the Swift 6 compiler — avoids strict-concurrency churn); `CODE_SIGN_IDENTITY: "-"` (ad-hoc "Sign to Run Locally" — sandbox entitlement still applies, zero signing setup); App Sandbox **on** + `files.user-selected.read-write` (future export); custom UTTypes `com.tareq.kanban.card` / `.list` declared for drag payloads. Three targets: `Kanban` (app), `KanbanTests` (unit, **Swift Testing** framework), `KanbanUITests` (`bundle.ui-testing`, XCTest — required by XCUITest). A `Makefile` wraps `gen / build / unit / ui / test`.

### Directory layout

```
kanban/
├── project.yml, Makefile, .gitignore
├── Kanban/
│   ├── KanbanApp.swift            # @main: WindowGroup + Commands + container wiring
│   ├── Kanban.entitlements
│   ├── Models/    Board, BoardList, Card, CardLabel, LabelColor, BoardTheme(PhB), KanbanSchema
│   ├── Store/     BoardStore, Reordering, DueDateStatus, FixtureSeeder, ModelContainerFactory
│   ├── DragDrop/  CardTransfer (Transferable payloads), DropMath (pure insertion math)
│   ├── Views/     RootView; Sidebar/…; Board/ (BoardView, ListColumnView, CardView,
│   │              AddListButton, InsertionIndicator, LabelFilterBar-PhB);
│   │              CardDetail/ (CardDetailView, LabelPicker, DueDatePicker);
│   │              Components/ (InlineEditableText, LabelChip, DueDateBadge)
│   ├── Commands/  AppCommands (menu bar = shortcut source of truth), FocusedValues
│   └── Support/   AccessibilityID (shared with UI-test target), AppLaunchConfig
├── KanbanTests/   Reordering, DropMath, DueDateStatus, BoardStore{Board,List,Card},
│                  Label, CascadeDelete, UndoRedo tests + Helpers/TestContainer
└── KanbanUITests/ KanbanUITestCase (base: fixtures, drag helpers) + one file per journey
```

### Architecture (4 layers, dependencies point down)
- **Models (@Model):** persistent state only; parents expose `sortedLists`/`sortedCards` computed props (SwiftData relationships are unordered — never rely on array order).
- **Pure logic:** `Reordering` (position math → `[(id, newPosition)]`), `DropMath` (drop point → insertion index), `DueDateStatus` (urgency with injected clock) — zero framework imports, the TDD core.
- **`BoardStore` (@MainActor, @Observable):** the *only* mutation surface — CRUD, moves, label toggles, due dates; wraps multi-write ops in named undo groups; `ensureLabelsSeeded()`. Injected via `.environment`. Views never write models directly.
- **Views:** sidebar via `@Query(sort: \Board.position)`; board views hold `@Bindable` models for fine-grained observation; all ordering read through sorted props.

**Undo/redo:** assign SwiftUI's `@Environment(\.undoManager)` to `modelContext.undoManager` → SwiftData auto-registers undo for every change; Edit ▸ Undo/Redo works for free. `BoardStore` groups multi-write ops (`beginUndoGrouping`/`setActionName`) so one ⌘Z = one user action. Fallback if auto-undo is over-granular: explicit `registerUndo` closures in store methods (contained swap thanks to single mutation surface).

### SwiftData schema V1 (versioned from day one)
`KanbanSchemaV1: VersionedSchema` + `KanbanMigrationPlan` (empty stages) — any later change = `KanbanSchemaV2` + migration stage, never in-place edits.

- **Board:** id (unique), name, emoji?, position, themeName, customThemeHex?, createdAt; lists `.cascade`.
- **BoardList** (named to avoid SwiftUI.List collision): id, name, position, isCollapsed (Phase B field, in V1 from day one), board?; cards `.cascade`.
- **Card:** id, title, details? (`description` collides with NSObject), position, dueDate? (stored as startOfDay when `includesTime == false`), includesTime, createdAt, updatedAt, list?; labels many-to-many `.nullify`.
- **CardLabel:** colorName (unique) — exactly 8 rows, seeded idempotently at launch; global (PRD's consistent intent is a fixed palette); entity-over-enum-array so Phase-B `#Predicate` filtering and future named labels are additive migrations.
- **Ordering:** contiguous integers 0..<n, renumber-on-move via pure `Reordering` functions (incl. `normalized()` self-healing). Tens of cards per list → O(n) rewrites are negligible; trivially assertable in tests; no rebalancing.

### Keyboard shortcut map (menu bar is source of truth)
| Shortcut | Action |
|---|---|
| ⌘N / ⇧⌘N / ⌥⌘N | New card (first list, or focused list) / new board / new list |
| Return (list focused) | New card at bottom of focused list |
| ⌘⌫ | Delete selected card — **no dialog, undoable** |
| ⌘⏎ / Esc | Save & close detail / cancel-close |
| ⌘Z / ⇧⌘Z | Undo / redo (automatic via Edit menu) |
| ⌃⌘S | Toggle sidebar (free with NavigationSplitView) |
| ⌘1–⌘9 | Select nth board |
| ⌘F | Focus label filter (Phase B) |

Bare `+` from the PRD is dropped (conflicts with typing). Commands enabled/routed via `@FocusedValue` (single `FocusTarget` enum); every action has a menu item, so XCUITest can drive via `typeKey` or `app.menuBars` fallback.

## Part 3 — Milestone sequence (TDD; each = failing tests → implement → verify)

**Phase A (MVP):**
- **M0 — Scaffold & walking skeleton:** install XcodeGen; `project.yml`, Makefile, entitlements, placeholder window; 1 trivial unit test + 1 XCUITest asserting the window. Verify `make gen && make build && make unit && make ui` — proves the whole toolchain (incl. the one-time macOS automation-permission prompt) before any product code.
- **M1 — Schema + store core (pure TDD, no UI):** all models, migration plan, container factory, `Reordering`, `BoardStore` CRUD. Unit suites: Reordering (boundaries, cross-list splice, normalize), BoardStore board/list/card (create board ⇒ 3 default lists; renumbering invariants), Label seeding idempotence + toggle, CascadeDelete (orphan counts zero; labels survive), UndoRedo (one undo step per op), DueDateStatus (fixed clock, midnight boundaries).
- **M2 — Drag-and-drop spike (de-risking gate):** prove native `.draggable(CardTransfer)`/`.dropDestination` + `Transferable` (free native drag ghost via `preview:`; works across independent ScrollViews; XCUITest-drivable). Insertion index from per-row `.dropDestination` + `DropMath` midline rule; `isTargeted` drives `InsertionIndicator`. Minimal 2-column debug board under `--uitest --fixture spike`; e2e test: coordinate drag cross-list, relaunch, assert persisted. **Exit gate: 3 consecutive green runs or invoke Risk-1/2 fallbacks now.**
- **M3 — App shell:** NavigationSplitView, board CRUD (name+emoji, 3 default lists), sidebar filter, `@AppStorage` selection restore, empty state. e2e: BoardCRUD + selected-board-restored-after-relaunch.
- **M4 — Lists UI:** columns, inline rename (`InlineEditableText`), add/delete list, list reordering via spike mechanism. e2e: ListCRUD + reorder-lists.
- **M5 — Cards UI + production drag-and-drop:** inline create (double-click / Return / ⌘N), inline edit, ⌘⌫ delete, reorder within list + cross-list move with indicator; context-menu "Move to List ▸" as the accessible non-drag alternative. e2e: CardCRUD + 3 drag suites (within-list, across-lists, to-empty-list).
- **M6 — Card detail:** sheet with title/description/`LabelPicker` (8 chips)/`DueDatePicker` (Today/Tomorrow/Next Week); chips + `DueDateBadge` on card face. e2e: CardDetail suite.
- **M7 — Command layer + undo + persistence (Phase A done):** full shortcut map via `AppCommands`/`FocusedValues`, ⌘1–9, undo wired end-to-end, animation-disable under `--uitest`. e2e: KeyboardShortcut suite (every mapping incl. undo-of-move) + full Persistence suite.

**Phase B (P1):**
- **M8 — Board themes:** 6 presets + custom hex (fields already in V1 — no migration). e2e: theme persists across relaunch.
- **M9 — List collapse:** chevron → narrow pill (name+count); collapsed lists still valid drop targets (append).
- **M10 — Urgency colors + dark-mode polish:** badge colors from `DueDateStatus` (overdue red, today orange, **tomorrow amber**, later-than-tomorrow gray; no due date = no badge); light/dark asset-catalog audit; badge exposes status via `accessibilityValue`.
- **M11 — Label filter + wrap-up:** `LabelFilterBar` (8 chips, OR-filter, ⌘F), filtered/total count in list headers; README + P2 roadmap notes (Reminders sync via EventKit, Spotlight, checklists, Trello import).

## Part 4 — E2E test plan (XCUITest)

- **Isolation & seeding:** `KanbanUITestCase.launch(fixture:reset:storeName:)` passes `--uitest --reset --fixture <name> --store-name <testName>`; store lives at `Application Support/UITest/<name>.sqlite` **inside the sandbox container** (name-indirection because a sandboxed app can't write to arbitrary paths). `relaunchPreservingStore()` powers persistence tests. Fixtures ("empty", "standard" Groceries/Work boards, "spike") are deterministic; fixture due dates computed relative to launch so urgency tests never rot. `--uitest` also disables animations and state restoration.
- **Accessibility IDs:** shared `AccessibilityID` enum compiled into both targets — `board(name)` → `"board-Groceries"`, `list(name)`, `card(title)`, `addCardButton(list)`, `dueDateBadge(cardTitle)`, `labelChip(color)`; semantic `accessibilityValue`s (due status, theme) so tests assert meaning, not pixels.
- **Drag drivability:** `card.coordinate(...).press(forDuration: 0.5, thenDragTo: target)` with hover-jiggle + one retry; precise reorders target destination card's top/bottom third (matches DropMath midline rule); `assertCardOrder(in:)` compares vertical frame order.
- **Shortcuts:** `app.typeKey(_:modifierFlags:)`; menu items also asserted (existence + enabled state) so discoverability is itself tested.
- **Invocations** (wrapped in Makefile): `xcodegen generate`; `xcodebuild -project Kanban.xcodeproj -scheme Kanban -destination 'platform=macOS,arch=arm64' -derivedDataPath .build/DerivedData [-only-testing:KanbanTests | -only-testing:KanbanUITests -parallel-testing-enabled NO -resultBundlePath .build/results/…xcresult] [build|test]`.
- **Caveat:** "headless" = no Xcode GUI; XCUITest still needs a logged-in Aqua session and a one-time automation/accessibility permission grant (surfaced deliberately at M0).

## Part 5 — Top risks & fallbacks

1. **`.dropDestination` insertion UX jank** (indicator flicker, dead zones, no auto-scroll) → M2 spike gate; per-row destinations; `ScrollViewReader` auto-scroll near edges. Fallback ladder: list-level highlight + append-only cross-list drops → "Move to List ▸" menu guarantees the feature → AppKit `NSDragging*` via `NSViewRepresentable` for columns only.
2. **XCUITest drag flakiness under xcodebuild** → animations off, coordinate drags + retry, serial testing, semantic/relaunch-based assertions. Fallback: one smoke drag e2e; fine-grained ordering coverage lives in `Reordering` unit tests + menu-path e2e (same store code path).
3. **SwiftData sharp edges** (M2M quirks, undo granularity, unordered relationships) → all mutations through `BoardStore`; explicit int positions; unique+idempotent label seeding; UndoRedo tests in M1 before any UI. Fallbacks: labels → `[LabelColor]` array via V2 migration; undo → manual `registerUndo`.
4. **Toolchain drift** (XcodeGen/Xcode versions, sandbox+signing surprises) → M0 proves generate→build→unit→ui on this machine; ad-hoc signing; Makefile pins invocations. Fallback: commit generated `.xcodeproj` as artifact, or swap to Tuist (only `project.yml` changes).
5. **Shortcut/focus routing complexity** → menu-bar-first with `@FocusedValue` gating (enabled-state assertable), single `FocusTarget` enum, pure command-routing helpers unit-tested in M7. Fallback: drop Return-on-focused-list (redundant entry point; no PRD capability lost).

## Execution order

1. Revise `PRD-Kanban-Board-Mac.md` → v1.1 per Part 1 (and save the design spec to `docs/superpowers/specs/`).
2. `git init` + initial commit (PRD v1.1 + spec).
3. M0 → M11 in order, TDD per milestone, committing at each green milestone.

## Verification

- **Per milestone:** unit target green (`make unit`), then affected XCUITest flows green (`make ui`); previously-green suites stay green.
- **Phase A acceptance:** full XCUITest pass + keyboard-only walkthrough (create board → lists → cards → labels → due date → move card → undo → relaunch, no mouse) + manual drag-and-drop feel check.
- **Final:** full suite + PRD §9 acceptance criteria walked through one by one; relaunch persistence and 500-card fixture scroll/drag smoke per the new NFRs.
