# Kanban Board — Native Mac App (Trello Replacement)  
Product name: **Tack** (chosen at open-source publication, 2026-07-07; this historical document uses the working title "Kanban Board" throughout).

## Product Requirements Document (MVP)

**Status:** Draft v1.1  
**Last Updated:** 2026-07-05  
**Author:** Tareq  

---

## Changelog — v1.0 → v1.1

This revision incorporates a verified multi-reviewer PRD review plus user-locked platform decisions. Highlights:

- **Locked platform decisions:** SwiftUI + SwiftData, minimum macOS 14 (Sonoma); local personal builds, App Sandbox on, no signing/notarization; full test pyramid (unit + XCUITest).
- **Resolved the due-date contradiction** (C-08 vs D-01): date-only in the MVP UI, an explicit overdue definition, and an `includesTime` schema flag reserved for post-MVP time-of-day support without migration.
- **Rewrote §6 Data Model** to be implementable: concrete fields per entity, cascade-delete rules, ordering invariants, and schema versioning.
- **Moved "small teams" out of MVP target users** (§3) into a post-MVP note; the MVP is single-user and local-only, no collaboration/sync.
- **Pulled JSON export (E-01) and urgency color-coding (D-03) into MVP**; added **Undo/Redo (U-01)** as a first-class P0 feature, and added keyboard-only card navigation/movement (C-10, C-11) as P0.
- **Rewrote §1** to describe the MVP honestly; demoted Spotlight search and Apple Reminders sync to an explicit roadmap sentence instead of headline promises.
- **Rewrote A-04:** drag-and-drop uses SwiftUI `.draggable`/`.dropDestination` with `Transferable` payloads (not `DragGesture`/`NSDraggingSource`); added a de-risking spike and a context-menu fallback.
- **Card delete is now undo-based** (⌘⌫, no confirmation dialog, Finder pattern); board/list deletes keep their confirmation dialogs. List deletes are also undoable; board deletes are confirmation-only — not undoable (SwiftData platform limitation, see §4.7).
- **Replaced the keyboard shortcuts table**; dropped the bare `+` shortcut (conflicted with typing).
- **Declared dark mode an MVP baseline** (SwiftUI makes it near-free); only custom-theme contrast polish remains P1.
- **Replaced D-04's placeholder API** (`remindctl`/`eventkitd`) with the real EventKit framework (`EKReminder`, `NSRemindersUsageDescription`); still P2/roadmap.
- **Fixed traceability/consistency bugs:** Story 3 now correctly cites C-03/C-04; fixed a pre-existing mismatch where B-04 (P1) was listed in the Boards P0 MVP-scope line.
- **New sections:** §4.6 Data Export, §4.7 Undo & Redo, §9 Acceptance Criteria & Testing, §10 Success Metrics & Non-Functional Requirements. The Appendix priority matrix was regenerated from the revised section tables.
- **Final-review corrections (post-implementation):** dropped the *Return-on-focused-list* card-creation alias (§4.3 table, C-01, §9.3 C-01) — it was a redundant entry point with no unique capability, and ⌘N is the canonical keyboard creation path (design's sanctioned focus-routing fallback). Corrected the ⌘F shortcut description to "Toggle label filter bar" to match the implementation (it shows/hides the bar; it is not a focus command), and added the implemented ⌘O (open selected card) and ⇧⌘E (E-01 JSON export) rows to the app-wide shortcuts table.
- **Pre-ship cleanup:** §9.8 now records that E-01's save-panel leg is manually verified rather than XCUITest-driven (sandboxed, remote-hosted `NSSavePanel`, same class of platform limitation as the board-delete note), while export content correctness stays fully automated via the `--export-to` test hook.
- **Post-implementation correction:** C-02's description (§4.3 table, §9.3) said "click to edit"; the shipped interaction is double-click the title (or context menu ▸ Rename Card) — a single click selects the card instead, consistent with C-01/C-04's click-to-select convention. Both mentions are corrected to match.

---

## Table of Contents

- [1. Overview & Vision](#1-overview--vision)
- [2. Problem Statement](#2-problem-statement)
- [3. Target Users](#3-target-users)
- [4. Core Feature Set (MVP)](#4-core-feature-set-mvp)
  - [4.1 Boards](#41-boards)
  - [4.2 Lists](#42-lists)
  - [4.3 Cards](#43-cards)
  - [4.4 Labels](#44-labels)
  - [4.5 Due Dates & Reminders](#45-due-dates--reminders)
  - [4.6 Data Export](#46-data-export)
  - [4.7 Undo & Redo](#47-undo--redo)
- [5. User Stories](#5-user-stories)
- [6. Data Model](#6-data-model)
- [7. Out of Scope for MVP](#7-out-of-scope-for-mvp)
- [8. Assumptions & Constraints](#8-assumptions--constraints)
- [9. Acceptance Criteria & Testing](#9-acceptance-criteria--testing)
- [10. Success Metrics & Non-Functional Requirements](#10-success-metrics--non-functional-requirements)

---

## 1. Overview & Vision

A **native Mac Kanban Board app** that delivers a fast, local-first, keyboard-driven project management experience — a direct replacement for Trello without the web-browser dependency, slow load times, or account lock-in.

The MVP delivers the core Kanban mental model (boards → lists → cards) with native macOS performance and idioms: drag-and-drop, full keyboard navigation, undo/redo, and dark mode support out of the box. All data lives locally on disk in a SwiftData/SQLite store — there is no account, no server, and no network dependency, so the app works fully offline by construction. Users can export their data to JSON at any time, so switching away is never blocked by lock-in.

Cloud sync, Spotlight search across boards, and Apple Reminders sync are compelling native-Mac capabilities, but they are explicit **roadmap** items for a future release — not MVP promises (see §7).

> **One-line pitch:** *Trello meets Finder — fast, local-first, and built for Mac.*

---

## 2. Problem Statement

| Pain Point | Current Workaround |
|------------|-------------------|
| Trello requires a browser → slow, clunky | Users open Safari/Chrome in a tab (or install the desktop app which is just Electron) |
| Web apps can't use macOS keyboard shortcuts natively | Users memorize non-standard shortcuts or don't use them at all |
| No offline-first experience on Trello | Users lose access when disconnected; data only lives in the cloud |
| Search across boards is slow (server-side) | Users rely on labels + manual scanning |
| Apple Reminders integration requires third-party bridges | No first-class macOS-native option exists for Kanban → Reminders sync |

---

## 3. Target Users

| Segment | Description |
|---------|-------------|
| **Individual Mac users** | Personal task management — freelancers, writers, students who currently use Trello or Apple Notes for tracking |
| **Trello refugees** | Users frustrated with Trello's pricing changes, slow web performance, or feature creep |

> **Post-MVP note:** Small teams (2–8 people) are a target segment for a future release, once multi-user collaboration/sync ships (see §7). The MVP is single-user and local-only — there is no collaboration or sync of any kind.

---

## 4. Core Feature Set (MVP)

### 4.1 Boards

Boards are the top-level container — a visual workspace for organizing work into columns (lists).

| # | Feature | Priority | Notes |
|---|---------|----------|-------|
| B-01 | Create board with name + icon/emoji | P0 | Default: 3 empty lists ("To Do", "In Progress", "Done") |
| B-02 | Rename / delete boards | P0 | Delete requires confirmation (cards may exist) and is **not undoable** — a SwiftData platform limitation (undo snapshotting of an on-disk Board delete fatally asserts), so board delete relies on the confirmation dialog alone (see §4.7, U-01). Rename and all other board mutations remain undoable via ⌘Z |
| B-03 | Board sidebar listing — collapsible, searchable | P0 | Sidebar persists across app restarts. If no boards exist (first launch), shows an empty-state onboarding view (see A-02, §8) instead of an empty list |
| B-04 | Board background themes/colors | P1 | 6 preset palettes + custom hex picker; baseline light/dark adaptation is automatic via SwiftUI — contrast auditing for *custom* themes is deferred (see §7) |
| B-05 | Board cover image (unsplash integration) | P2 | Post-MVP if time permits |
| B-06 | Reorder boards in sidebar (drag-and-drop) | P1 | Native macOS row reorder (SwiftUI `List` `.onMove`); disabled while the sidebar filter is active; one undo step (⌘Z); order persists across relaunch. Added post-MVP |

**MVP Scope:** B-01, B-02, B-03

---

### 4.2 Lists

Lists are columns within a board — the primary organizational unit of Kanban flow.

| # | Feature | Priority | Notes |
|---|---------|----------|-------|
| L-01 | Create list with name | P0 | Inline edit; "Add List" button at board's right edge |
| L-02 | Rename / delete lists | P0 | Delete requires confirmation (cards may exist); **not undoable since M-E** (same spike-forced detach discipline as board delete — see §4.7, U-01); rename remains undoable |
| L-03 | Reorder lists via drag-and-drop | P0 | SwiftUI `.draggable`/`.dropDestination` with visual ghost indicator during drag (see A-04, §8) |
| L-04 | Collapse/expand lists | P1 | "Archive" is post-MVP |
| L-05 | List background colors | P2 | Optional visual distinction between columns |

**MVP Scope:** L-01, L-02, L-03

---

### 4.3 Cards

Cards are individual tasks/items within a list — the most interactive element in the app.

#### Card Creation & Display

| # | Feature | Priority | Notes |
|---|---------|----------|-------|
| C-01 | Create card with title (inline) | P0 | Canonical creation path is the always-visible "+ Add card" row at the bottom of the list; double-clicking empty list space is an alias for the same action. ⌘N is the keyboard creation path (focused list, else first list — see Keyboard Shortcuts below) |
| C-02 | Edit card title inline | P0 | Double-click the title (or context menu ▸ Rename Card) to edit inline; Enter to save, Esc to cancel; a single click selects the card |
| C-03 | Reorder cards within a list (drag-and-drop) | P0 | SwiftUI `.draggable`/`.dropDestination`; visual ghost indicator during drag; snap-to-grid animation |
| C-04 | Move cards between lists (drag-and-drop) | P0 | Cards can be dropped on the target list area; keyboard/VoiceOver alternative is C-11 (⌘+←/→) or the context-menu "Move to List" fallback (see A-04, §8) |
| C-05 | Delete card (no confirmation; NOT undoable since M-E) | P0 | `⌘⌫` deletes the focused/selected card immediately with **no confirmation dialog** (Finder `⌘⌫` pattern). **Not undoable since M-E** — the checklist cascade spike showed SwiftData's undo of a card delete violating integrity once cards carry checklist items (see §4.7, U-01), so card delete now uses the board-delete detach discipline. Follow-up: a confirmation dialog or soft-delete should replace the lost safety net (see §7 soft-delete row) |

#### Card Detail View

When a card is clicked, it opens an expanded detail view (modal or side panel).

| # | Feature | Priority | Notes |
|---|---------|----------|-------|
| C-06 | Title + description editing | P0 | Rich text not required for MVP — plain text with line breaks. Stored in the schema as `details` (see §6) |
| C-07 | Add label(s) to card (see §4.4) | P0 | Fixed palette of 8 colors; click to add, click again to remove; multi-label support |
| C-08 | Set due date (see §4.5) | P0 | Date picker, **date-only by default** — see §4.5 for the overdue definition. Optional time-of-day + duration **shipped post-MVP (M-B)**; schema carries `includesTime`/`durationMinutes` (see §6, §7) |
| C-09 | Activity log — who created/moved/edited the card | P1 | Post-MVP if time permits; single-user edit history, independent of multi-user collaboration (see §7) |

#### Keyboard Navigation & Movement

Drag-and-drop must not be the only way to select or move a card — this is required for the power-user story (§5, Story 5) and for VoiceOver users.

| # | Feature | Priority | Notes |
|---|---------|----------|-------|
| C-10 | Keyboard-navigate card selection | P0 | Arrow keys move the selected/focused card within a list (up/down) or into the adjacent list (left/right), matching visual adjacency — no mouse required |
| C-11 | Keyboard-move selected card | P0 | ⌘+arrow reorders the selected card within its list (up/down) or moves it to the adjacent list (left/right) at the corresponding position; produces the same persisted result as the equivalent drag-and-drop (C-03/C-04); undoable via ⌘Z |

**MVP Scope:** C-01, C-02, C-03, C-04, C-05, C-06, C-07, C-08, C-10, C-11

#### Keyboard Shortcuts

> Scope note: this table is app-wide (boards, lists, and cards), not limited to card actions — it supersedes any shortcut mentioned elsewhere in §4.

| Shortcut | Action |
|---|---|
| ⌘N | New card (focused list, else first list of active board) |
| ⇧⌘N | New board |
| ⌥⌘N | New list |
| ⌘⌫ | Delete selected card (no dialog; not undoable since M-E — see §4.7) |
| ⌘O | Open selected card's detail |
| ⌘⏎ / Esc | Save & close card detail / cancel-close |
| ⌘Z / ⇧⌘Z | Undo / Redo |
| ⌃⌘S | Toggle sidebar |
| ⌘1–⌘9 | Select nth board |
| ⇧⌘E | Export all boards to JSON |
| ⇧⌘I | Import Boards… |
| ⌘F | Toggle label filter bar |

The bare `+` shortcut is dropped — it conflicts with normal typing. Every shortcut has a corresponding menu-bar item (SwiftUI `Commands`); **the menu bar is the source of truth**. Canonical card creation is always the "+ Add card" row at the bottom of a list; double-click is an alias for it, and ⌘N is the keyboard creation path — not separate mechanisms. (A Return-on-focused-list alias was considered but dropped: it was a redundant entry point with no unique capability, and ⌘N — a first-class menu command — is the canonical keyboard creation path. This is the design's sanctioned focus-routing fallback.) In addition to the table above, arrow keys and ⌘+arrow keys provide keyboard-only card navigation and movement — see C-10/C-11 above.

---

### 4.4 Labels

Labels provide visual categorization of cards without disrupting the board layout.

| # | Feature | Priority | Notes |
|---|---------|----------|-------|
| LB-01 | Predefined color palette (8 colors) | P0 | Fixed global palette of exactly 8 rows (Red, Orange, Yellow, Green, Blue, Indigo, Purple, Pink), seeded idempotently at first launch (see §6). Label *names* (beyond color) are P1 |
| LB-02 | Add/remove labels on individual cards | P0 | Toggle in card detail view; click to add, click again to remove |
| LB-03 | Search/filter by label | P1 | Post-MVP — filter bar above boards; ⌘F focuses it |

**MVP Scope:** LB-01, LB-02

---

### 4.5 Due Dates & Reminders

Due dates add time-awareness to cards, with native macOS integration.

Due dates are **date-only by default** (no time-of-day). Optional time-of-day + a duration **shipped post-MVP (M-B)**. A date-only card is **overdue** when its `dueDate` is earlier than the start of today in the user's local time zone (unchanged since MVP — i.e. it goes overdue at the end of its due day). A timed card (`includesTime == true`) is **overdue** strictly past `dueDate + durationMinutes` (duration is optional; `nil` or non-positive is treated as `0`, so a bare point-in-time due goes overdue the instant it passes) — short of that, it falls back to the same day-based bucketing as a date-only card (a still-upcoming slot later today reads as "due today", not some intermediate state). Both are evaluated at render/read time and need no background job. The "Today"/"Tomorrow"/"Next Week" quick options (D-01) remain date-only and reset any staged time-of-day/duration back to none. The schema stores `includesTime` (default `false`) and an optional `durationMinutes` alongside `dueDate` so both could be added without a data migration (see §6, §7).

| # | Feature | Priority | Notes |
|---|---------|----------|-------|
| D-01 | Set due date on card (date-only by default) | P0 | Date picker in card detail view; "Today", "Tomorrow", "Next Week" quick options (always date-only; reset any staged time-of-day/duration); stored as start-of-day local time with `includesTime == false`. Optional time-of-day + duration **shipped post-MVP (M-B)** — see §4.5 |
| D-02 | Show due date badge on card | P0 | Visual indicator directly on the card surface (no need to open detail); cards with **no due date show no badge at all** |
| D-03 | Color-code by urgency | P0 | For cards that have a due date: Overdue = **red**, Due today = **orange**, Due tomorrow = **amber**, Due later than tomorrow = neutral **gray** (not green — green reads as "done", and the app has no explicit done/complete state in MVP). Cards with no due date show no badge (see D-02) |
| D-04 | Sync due dates → Apple Reminders | P2 | Post-MVP/roadmap. Uses the **EventKit** framework (`EKReminder`); requires `NSRemindersUsageDescription` in `Info.plist` and Reminders access authorization/entitlement |

**MVP Scope:** D-01, D-02, D-03

---

### 4.6 Data Export

Local-first storage without an export path is exactly the lock-in this app exists to help users escape (see §2's critique of Trello). Export is therefore pulled into MVP.

| # | Feature | Priority | Notes |
|---|---------|----------|-------|
| E-01 | Export all boards to a JSON file | P0 | Standard macOS save panel (sandbox-compatible via user-selected file write, e.g. `fileExporter`/`NSSavePanel`); exports the full board/list/card/label graph |
| E-02 | Backup/restore — import a previously exported JSON file | P1 | Shipped post-MVP. Two modes chosen via a dialog after the file is picked and decoded: **Add to Existing** (appends after current boards) and **Replace All Boards** (deletes existing boards first; unavailable for zero-board backups). ⇧⌘I / File menu. Malformed JSON, missing required fields, or a `formatVersion` outside `1...current` hard-reject the whole file (the gate is tolerant of older versions since v2/M-A: old files decode with missing optional fields as nil; files from NEWER app versions are rejected) — nothing imported, user-visible error; everything else decodable is sanitized quietly (unknown label names dropped, `dueDate` re-normalized to local start-of-day when time-of-day isn't included, `durationMinutes` nilled when date-only or non-positive, `customThemeHex` canonicalized-or-nil). **Neither mode is undoable** — per the recorded in-memory undo spike (multi-board-graph undo/redo silently dropped 3rd-level Card inserts on redo), both Add to Existing and Replace All detach the undo manager and clear the undo stack, exactly like board delete (see §4.7, U-01); ⌘Z after an import does nothing. Export/Import menu items gray out while a text editor has focus, matching the other editing commands' enablement |

**MVP Scope:** E-01 (E-02 shipped post-MVP, see above)

---

### 4.7 Undo & Redo

All mutating operations — create/rename/move/reorder of boards, lists, and cards; label toggles; due-date edits — are undoable, backed by the standard `UndoManager` and exposed through the standard Edit menu and ⌘Z/⇧⌘Z. The exceptions are **all three delete operations — board, list, and card deletion**, none of which is undoable: board deletion because an on-disk Board delete's undo snapshotting fatally asserts (see B-02), and list/card deletion since **M-E** because the same class of fatal assert reproduces one cascade level shallower once a card carries checklist items (the `ChecklistUndoOnDiskTests` spike, Task 0 of the M-E plan; see §4.3 C-05, §4.2 L-02). Any delete — board, list, or card — **clears the undo stack outright**, since earlier registered groups may reference the now-deleted rows. Board/card *creation* undo is unaffected and works normally.

| # | Feature | Priority | Notes |
|---|---------|----------|-------|
| U-01 | Undo/redo for all mutations | P0 | `UndoManager`-backed (NSUndoManager); standard Edit menu items; ⌘Z / ⇧⌘Z. Session undo history holds at least 50 steps (see §10, N-04). **All three deletes — board (B-02), list (L-02), and card (C-05) — are excluded and not undoable**: board deletion because SwiftData's undo snapshotting of an on-disk Board delete fatally asserts (crash-forced platform limitation; see B-02 and §7 roadmap), and list/card deletion since M-E because the identical fatal-assert class reproduces one cascade level shallower once checklist items exist (`ChecklistUndoOnDiskTests`, M-E Task 0). Each delete clears the undo stack outright. All other board/list/card mutations, including creation, remain undoable |

**MVP Scope:** U-01

---

## 5. User Stories

### As an individual user:
1. **I want to quickly create a new board for a project** so I can start organizing my tasks immediately.  
   → *Covers B-01 (create board with name + default lists)*

2. **I want to add cards to a list by just typing** so I don't have to click around.  
   → *Covers C-01 (inline card creation), L-01*

3. **I want to drag and drop cards between lists** so my workflow feels natural.  
   → *Covers C-03 (reorder within a list), C-04 (move between lists)*

4. **I want to see which tasks are due today or overdue** at a glance from the board view.  
   → *Covers D-01, D-02, D-03 (due date, badge, and color-coded urgency — all in MVP scope)*

### As a power user:
5. **I want keyboard shortcuts for everything** so I never have to leave my hands on the keyboard.  
   → *Covers all keyboard shortcuts and menu commands (§4.3), plus keyboard-only card navigation and movement (C-10, C-11) and undo/redo (U-01)*

6. **I want to categorize cards with colors (labels)** so related work is visually grouped.  
   → *Covers LB-01, LB-02*

### As a Trello refugee:
7. **I want the same Kanban mental model I already know** — boards, lists, and cards in that order.  
   → *Covers B-01 (default 3 empty lists), L-01, C-01*

8. **I don't want to be forced into a web browser or create an account just to get started, and I want my data back if I ever leave.**  
   → *Implied constraint: local-first data storage, no mandatory auth for MVP; data portability via JSON export (E-01, §4.6)*

---

## 6. Data Model

### 6.1 Entities

**Board**
- `id`: UUID (unique)
- `name`: String
- `emoji`: String? (optional)
- `position`: Int
- `themeName`: String
- `customThemeHex`: String? (optional; used when `themeName == .custom`)
- `createdAt`: Date
- `lists`: [BoardList] — **cascade delete** (deleting a board deletes its lists and, transitively, their cards)

**BoardList** *(the Kanban "List"; named `BoardList` in code to avoid collision with SwiftUI's `List` view — the PRD still refers to it as "List")*
- `id`: UUID
- `name`: String
- `position`: Int
- `isCollapsed`: Bool
- `createdAt`: Date
- `cards`: [Card] — **cascade delete**

**Card**
- `id`: UUID
- `title`: String
- `details`: String? (optional — this is the PRD's "description" field; named `details` in the schema)
- `position`: Int
- `dueDate`: Date? (optional; when `includesTime == false`, stored normalized to start-of-day in the local time zone at the moment it is set; when `includesTime == true`, stores the raw wall-clock slot start)
- `includesTime`: Bool (default `false`; user-settable as of **M-B** — see §4.5, §7)
- `durationMinutes`: Int? (optional; only meaningful when `includesTime == true`; nilled when date-only or non-positive — see §4.5, §7)
- `createdAt`: Date
- `updatedAt`: Date
- `labels`: [Label] — many-to-many; **nullify on delete** in both directions (deleting a Label removes it from any cards without deleting the cards; deleting a Card removes its label associations without deleting Labels)

**Label**
- `id`: UUID
- `colorName`: String (unique)
- Fixed global palette of **exactly 8 rows**, seeded **idempotently** at first launch (Red, Orange, Yellow, Green, Blue, Indigo, Purple, Pink — see LB-01). Re-running the seed against an existing store must not create duplicates or violate the `colorName` uniqueness constraint.
- User-facing label *names* (beyond color) are P1 (see §7).

### 6.2 Ordering

Sibling order — lists within a board, cards within a list — is a contiguous integer `position` in `0..<n`, **renumbered on every insert/move/delete** so that for the current set of siblings, positions are always exactly `0, 1, …, n-1` with no gaps or duplicates. List/card counts per parent are expected to stay small (dozens, not thousands), so full renumbering on move is cheap and keeps the invariant simple to state and unit-test (see §9).

### 6.3 Cascade Rules (summary)

| Delete… | Effect |
|---|---|
| Board | Cascades to its BoardLists, which cascade to their Cards |
| BoardList | Cascades to its Cards |
| Card | Removes its Label associations (nullify); Labels are untouched |
| Label | Removes the association from any Cards that had it (nullify); Cards are untouched |

All of the above are undoable (see §4.7, U-01), **except all three deletes — Board, List, and Card** — none of which is undoable: Board deletion is a SwiftData platform limitation (undo snapshotting of an on-disk Board delete fatally asserts), and List/Card deletion joined it since **M-E**, once cards carry checklist items (the same fatal-assert class reproduces one cascade level shallower — see the `ChecklistUndoOnDiskTests` spike). Board and List deletes both require a confirmation dialog before the delete is committed (see B-02, L-02); neither is undoable. Card delete has no confirmation dialog and, since M-E, is not undoable either — deletion is now permanent and the undo stack clears (see C-05).

### 6.4 Schema Versioning

The SwiftData schema is versioned from **v1** using `VersionedSchema`, with an explicit migration plan (`SchemaMigrationPlan`) wired up starting with the first shipped build — even if that initial plan has no migrations yet. This is what lets fields like `includesTime` (§4.5) and future additions land in later schema versions via additive, non-destructive migrations instead of requiring data loss or a fresh store.

### 6.5 Storage

SQLite via SwiftData (no Core Data fallback). Local-first; zero network/sync dependency for MVP.

---

## 7. Out of Scope for MVP

These are explicitly deferred beyond the MVP, with an indicative roadmap priority:

| Feature | Roadmap Priority | Reason |
|---------|------|--------|
| Multi-user collaboration / real-time sync (incl. card comments/discussion) | P2 | Requires backend infrastructure; not part of the "native Mac replacement" pitch. Also blocks the "small teams (2–8)" segment (§3) until shipped |
| Card checklists (sub-tasks) | P2 | Nice-to-have but adds complexity to the card detail view |
| Attachments / file uploads | P2 | Needs a storage/sync model; low priority for MVP |
| Card activity log | P1 | Tracked as C-09 (§4.3); single-user edit history, independent of multi-user collaboration |
| Apple Watch companion | P2 | Small screen doesn't suit Kanban well |
| Custom-theme dark/light contrast audit & accessibility polish | P1 | Baseline dark/light mode adaptation ships in MVP for free via SwiftUI; deeper contrast auditing for *custom* board themes (B-04) is deferred |
| Cloud sync | P2 | Local-first means data lives on disk; multi-device sync needs backend infrastructure |
| Optional due-date time-of-day | P1 | **Shipped post-MVP (M-B)** — see §4.5. Schema carried an `includesTime` flag (default `false`) from v1 so this landed without a migration; `durationMinutes` was added as an additive optional field (§6) |
| Search across all boards (Spotlight integration) | P2 | Useful, but deferred to roadmap (§1) |
| Apple Reminders sync (EventKit) | P2 | Deferred to roadmap (§1); see D-04 |
| Trello import (from Trello's JSON export) | P1 | Feasible from Trello's own data export format; table stakes for Trello refugees switching over |
| Soft-delete/restore for boards (undo replacement) | P1 | Platform-forced deferral: board delete is currently confirmation-gated and not undoable because SwiftData's undo snapshotting of an on-disk Board delete fatally asserts (see B-02, U-01). A soft-delete + restore ("Recently Deleted") flow would give back reversibility without relying on `UndoManager` |

---

## 8. Assumptions & Constraints

| # | Assumption | Impact |
|---|-----------|--------|
| A-01 | The app targets **macOS 14 (Sonoma)** as the minimum OS version | SwiftUI features in use (`.draggable`/`.dropDestination`, current SwiftData APIs) require macOS 14+; no macOS 13 or earlier support |
| A-02 | First launch shows an **empty-state onboarding view** with a prominent "Create your first board" action; the app must handle a **zero-board state** everywhere (sidebar, shortcuts, etc.), not assume a board is always open | Removes the "always at least one active board" assumption from v1.0; all board-dependent UI must gracefully degrade to the empty state |
| A-03 | No authentication required for MVP — local-only data | Simplifies onboarding but means "multi-device" doesn't work out of the box |
| A-04 | Card and list drag-and-drop uses SwiftUI's **`.draggable`/`.dropDestination`** modifiers with `Transferable` payloads — **not** `DragGesture`/`NSDraggingSource`, which are a different, incompatible interaction layer | An early de-risking spike is planned to validate drag-and-drop feel/performance on large boards before broader feature work begins. If `.draggable`/`.dropDestination` proves insufficient, the fallback is a context-menu **"Move to List"** action (keyboard nav C-10/C-11 ships regardless as the accessible path) |
| A-05 | Default list names ("To Do", "In Progress", "Done") are English-only for MVP | Can be localized in a future app release |
| A-06 | Distribution is **local personal builds only** — App Sandbox enabled, ad-hoc/no code signing, no notarization | No Mac App Store submission or Developer ID pipeline for MVP; simplifies build/release but restricts installs to the author's own Macs |
| A-07 | All builds and test suites run **headlessly via `xcodebuild`** | Enables scripted verification of the Definition of Done (§9) without a GUI dependency |
| A-08 | The SwiftData schema is **versioned from v1** using `VersionedSchema` with an explicit migration plan | Protects the `includesTime` due-date flag and future schema growth from requiring destructive migrations |

---

## 9. Acceptance Criteria & Testing

Given/When/Then acceptance criteria for every P0 feature row in §4.

### 9.1 Boards

- **B-01 — Create board.** Given the app is open (with or without existing boards), when the user creates a new board and supplies a name, then a new board appears in the sidebar with three default lists ("To Do", "In Progress", "Done") and zero cards, and it persists after relaunch.
- **B-02 — Rename/delete board.** Given an existing board, when the user renames it, then the sidebar and any open views reflect the new name immediately and after relaunch. Given an existing board (with or without cards), when the user deletes it, then a confirmation dialog appears; when confirmed, the board and all its lists/cards are removed from the UI and the persisted store. The delete is **not undoable** (SwiftData platform limitation — see §4.7, U-01), so the confirmation dialog is the sole guard against accidental loss; the app must remain responsive after the delete.
- **B-03 — Board sidebar.** Given at least one board exists, when the app launches, then the sidebar lists all boards in their saved order from the previous session. Given zero boards exist, when the app launches, then the empty-state onboarding view (A-02) is shown instead. Given the sidebar search field has focus, when the user types a substring of a board name, then only matching boards remain visible.
- **B-06 — Reorder boards in sidebar.** Given boards A, B, C in that order, when the user drags C to the first position, then the sidebar shows C, A, B, the order persists after relaunch, and a single ⌘Z restores A, B, C. Given the sidebar filter is non-empty, board rows cannot be dragged (reordering is available only in the unfiltered list).

### 9.2 Lists

- **L-01 — Create list.** Given a board is open, when the user creates a new list with a name, then the list appears at the right edge of the board and persists after relaunch.
- **L-02 — Rename/delete list.** Given an existing list, when the user renames it, then the new name is reflected immediately and after relaunch. Given a list (with or without cards), when the user deletes it, then a confirmation dialog appears; when confirmed, the list and its cards are removed immediately; ⌘Z does NOT restore them — deletion is permanent and the undo history is cleared (not undoable since M-E — see §4.7).
- **L-03 — Reorder lists.** Given a board with lists A, B, C (in that order), when the user drags list C to the first position, then the board shows C, A, B, and the order persists after relaunch.

### 9.3 Cards

- **C-01 — Create card.** Given a list is visible, when the user activates the "+ Add card" row (by click, by double-clicking empty list space, or via ⌘N), then a new card is created at the bottom of that list in title-edit mode.
- **C-02 — Edit card title inline.** Given a card, when the user double-clicks its title, types a new value, and presses Return, then the new title is saved and persisted; pressing Esc instead discards the edit and restores the previous title.
- **C-03 — Reorder cards within a list.** Given a list with cards X, Y, Z (in that order), when the user drags X to position 2, then the list shows Y, X, Z, and the order persists after relaunch.
- **C-04 — Move cards between lists.** Given a board with lists A and B, when the user drags card X from A onto position 2 of B, then X appears at position 2 of B (and is removed from A), and the order persists after relaunch.
- **C-05 — Delete card.** Given a selected card, when the user presses ⌘⌫, then the card is removed immediately with no confirmation dialog; ⌘Z does NOT restore it — deletion is permanent and the undo history is cleared (not undoable since M-E — see §4.7).
- **C-06 — Title + description editing.** Given a card detail view, when the user edits the description (`details`) field and saves (⌘⏎), then the updated text (including line breaks) persists and is shown correctly on reopen and after relaunch.
- **C-07 — Add labels.** Given a card detail view, when the user clicks a label swatch, then the label is applied to the card and shown on the card face; clicking the same swatch again removes it; multiple labels can be applied simultaneously.
- **C-08 — Set due date.** Given a card detail view, when the user picks a date (no time), then the card's `dueDate` is stored as that date at local start-of-day with `includesTime == false`, and the due-date badge (D-02) reflects it immediately.
- **C-10 — Keyboard-navigate card selection.** Given a card is focused, when the user presses an arrow key, then selection moves to the adjacent card in the same list (up/down) or into the adjacent list (left/right) matching visual adjacency, with no mouse interaction required.
- **C-11 — Keyboard-move selected card.** Given a card is selected, when the user presses ⌘+arrow, then the card reorders within its list (up/down) or moves to the adjacent list at the corresponding position (left/right), producing the same persisted result as the equivalent drag-and-drop (C-03/C-04), and the move is undoable via ⌘Z.

### 9.4 Labels

- **LB-01 — Fixed label palette.** Given a fresh install, when the app launches for the first time, then exactly 8 Label rows exist (one per fixed `colorName`) with no duplicates; relaunching the app again does not create additional rows.
- **LB-02 — Add/remove labels on cards.** Covered by C-07 above (restated here for traceability to §4.4): toggling is idempotent and reflected on the card face immediately.

### 9.5 Due Dates

- **D-01 — Set due date.** (See C-08.) Given the quick-option buttons ("Today"/"Tomorrow"/"Next Week"), when the user clicks one, then the date field populates with the corresponding date at local start-of-day.
- **D-02 — Due date badge.** Given a card with a due date, when the board is displayed, then a badge showing the due date is visible on the card face without opening the detail view. Given a card with no due date, when the board is displayed, then no badge is shown on the card face.
- **D-03 — Color-code by urgency.** Given the current local date and a card that has a due date, when its due date is before today, then its badge is **red** (overdue); when equal to today, **orange**; when equal to tomorrow, **amber**; when later than tomorrow, neutral **gray** — never green. Cards with no due date show no badge (see D-02).

### 9.6 Data Export

- **E-01 — Export to JSON.** Given at least one board exists, when the user chooses Export (menu or shortcut), then a standard save panel appears; when the user picks a location and confirms, then a JSON file is written containing all boards, lists, cards, and label assignments, and the file can be re-parsed to reconstruct the same data graph.
- **E-02 — Import from JSON.** (a) Given a previously exported JSON file, when the user imports it, then the boards/lists/cards/labels/due dates/themes it contains are restored in the same order as the source. (b) Add to Existing is **not undoable** — per the recorded spike outcome (§4.6), it detaches the undo manager and clears the undo stack, exactly like board delete; ⌘Z after an Add import does nothing. (c) Replace All Boards deletes the existing boards first, is also not undoable and clears the undo stack, and is unavailable for a zero-board backup. (d) Given an invalid file (malformed JSON, missing required fields, or an unsupported `formatVersion`), when the user attempts to import it, then nothing is imported and an error is shown stating the existing boards are unchanged. (The `NSOpenPanel` leg is manually verified, not XCUITest-driven; content correctness is automated via `--import-from` — see §9.8.)

### 9.7 Undo/Redo

- **U-01 — Undo/redo for all mutations.** Given any undoable mutating action (create/rename/move/reorder of a board, list, or card; label toggle; due-date edit), when the user presses ⌘Z, then that single action is fully reverted, including position/order; when the user then presses ⇧⌘Z, then the action is reapplied. This holds for at least 50 consecutive undoable actions in one session (see §10, N-04). **Board, list, and card deletion are all excluded** — none is undoable (board: a SwiftData platform limitation; list/card: the same fatal-assert class since M-E, once cards carry checklist items — see §4.7), and each clears the undo stack outright; undoing a board/list/card *creation* is supported and, after it, the app remains responsive.

### 9.8 Testing Strategy & Definition of Done

- **Unit tests (Swift Testing)** cover model/store logic in isolation: position/ordering invariants (contiguous `0..<n`, correct renumbering on insert/move/delete) for lists and cards; cascade-delete behavior (Board→BoardList→Card, Label nullify-on-delete in both directions); due-date normalization (`includesTime == false` → start-of-day) and urgency color derivation (D-03); idempotent label-palette seeding (LB-01); and undo/redo stack behavior (U-01), including redo-after-undo and history depth ≥ 50.
- **XCUITest end-to-end tests** drive the full app for: board/list/card CRUD journeys; drag-and-drop (list reorder, card reorder, card move-between-lists); every shortcut in the §4.3 Keyboard Shortcuts table plus keyboard navigation (C-10/C-11); relaunch-persistence (perform mutations, terminate, relaunch, assert state matches); JSON export producing a well-formed, re-importable file; and delete-permanence flows (card no-confirmation and not undoable since M-E; list confirm-then-not-undoable since M-E; board confirm-only and not undoable — all three clear the undo stack outright), with a post-delete responsiveness check, and undoing a board *create* is verified to leave the app responsive). **E-01's save-panel leg is manually verified, not XCUITest-driven** — the standard save panel presented by Export is a sandboxed, remote-hosted `NSSavePanel` that XCUITest cannot reliably automate (platform limitation, same class as the board-delete note above); export CONTENT correctness (a well-formed, re-importable JSON file matching the seeded fixture) is still fully automated via the sanctioned `--export-to` test-only launch hook, which writes, reads back, and decodes the export outside the save panel. **B-06's reorder-drag leg is manually verified, not XCUITest-driven** — dragging a sidebar board row goes through NSTableView's native row-reorder session, which neither XCUITest's gesture synthesis nor a CGEvent-posted drag (`.cghidEventTap`) can commit (platform limitation, same class as the E-01 save-panel note above; the underlying mechanism is uninstrumented). The filter-gate leg IS automated (`SidebarReorderUITests.testFilterDisablesReorder`, which only asserts absence of movement and so isn't exposed to this limitation), and the reorder logic itself is fully unit-covered (`Reordering`'s `.onMove`-convention overload; `BoardStore.moveBoards`, including undo/redo and position-gap self-healing); the drag is confirmed working via a documented 30-second manual procedure (see the B-06 design spec). **E-02's open-panel leg is manually verified, not XCUITest-driven** (2026-07-08, PASS) — the standard open panel presented by Import is a sandboxed, remote-hosted `NSOpenPanel`, the same class as the E-01 save-panel note above; import CONTENT correctness (round trip, replace, invalid-file rejection, and mode-dialog cancel) is still fully automated via the sanctioned `--import-from`/`--import-mode` test-only launch hooks, which decode and import outside the open panel (see the E-02 design spec for the manual procedure, which must open a window via ⌘N first — `open`-launched `--uitest` instances start windowless on this host).
- **Definition of Done** for MVP scope: every P0 acceptance criterion in §9.1–9.7 passes, and both the unit and XCUITest suites are green when run headlessly via `xcodebuild` (see A-07).

---

## 10. Success Metrics & Non-Functional Requirements

| # | Requirement | Target |
|---|---|---|
| N-01 | Cold launch time | < 1 s from process start to an interactive board view |
| N-02 | Large-board performance | A board with 500 cards scrolls and supports drag-and-drop at 60 fps on Apple Silicon |
| N-03 | Autosave / crash safety | Every mutation is persisted (autosaved) within 1 s; force-quitting immediately after a mutation must not lose it |
| N-04 | Undo depth | Undo history holds at least 50 steps per session (see U-01) |
| N-05 | Keyboard-only usability | The entire app — board/list/card CRUD, reordering, moving cards, label toggling, due dates, export — is usable start-to-finish without a mouse |
| N-06 | VoiceOver accessibility | VoiceOver can read card content and move cards between lists/positions (via C-10/C-11), not solely via drag-and-drop |

---

## Appendix: Quick Reference — Feature Priority Matrix

**P0 — Must-Have (MVP)**
- B-01 Create board (name + emoji, default 3 lists)
- B-02 Rename/delete board (confirm; delete not undoable — see §4.7)
- B-03 Board sidebar (collapsible, searchable, persists; empty-state onboarding)
- L-01 Create list
- L-02 Rename/delete list (confirm; not undoable — see §4.7)
- L-03 Reorder lists (drag-and-drop)
- C-01 Create card (inline, "+ Add card" row)
- C-02 Edit card title inline
- C-03 Reorder cards within a list
- C-04 Move cards between lists
- C-05 Delete card (no confirmation; not undoable — see §4.7)
- C-06 Card title + description editing
- C-07 Add label(s) to card
- C-08 Set due date (date-only)
- C-10 Keyboard-navigate card selection
- C-11 Keyboard-move selected card
- LB-01 Fixed 8-color label palette
- LB-02 Add/remove labels on cards
- D-01 Set due date
- D-02 Due date badge on card
- D-03 Color-code by urgency (red/orange/amber/gray)
- E-01 Export all boards to JSON
- U-01 Undo/redo for all mutations
- Keyboard shortcuts & menu-bar commands (SwiftUI `Commands`, source of truth — §4.3)

**P1 — Should-Have (Phase B)**
- B-04 Board background themes (6 presets + custom hex)
- L-04 Collapse/expand lists
- C-09 Card activity log
- LB-03 Search/filter by label (⌘F)
- E-02 Backup/restore — import exported JSON (shipped post-MVP; Add to Existing / Replace All, neither undoable — see §4.6)
- Optional due-date time-of-day (shipped post-MVP; `includesTime`/`durationMinutes` — see §4.5)
- Custom-theme dark/light contrast audit & accessibility polish
- Trello import (from Trello's JSON export)

**P2 — Nice-to-Have (Roadmap)**
- B-05 Board cover image (Unsplash)
- L-05 List background colors
- D-04 Sync due dates → Apple Reminders (EventKit)
- Multi-user collaboration / real-time sync (also unlocks the "small teams" segment, §3)
- Card checklists (sub-tasks)
- Attachments / file uploads
- Apple Watch companion
- Cloud sync
- Search across all boards (Spotlight integration)

---

*End of PRD v1.1 — locked scope for implementation.*
