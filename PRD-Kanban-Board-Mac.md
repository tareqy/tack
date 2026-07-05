# Kanban Board — Native Mac App (Trello Replacement)  
## Product Requirements Document (MVP)

**Status:** Draft v1.0  
**Last Updated:** 2026-07-05  
**Author:** Tareq  

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
- [5. User Stories](#5-user-stories)
- [6. Data Model (High-Level)](#6-data-model-high-level)
- [7. Out of Scope for MVP](#7-out-of-scope-for-mvp)
- [8. Assumptions & Constraints](#8-assumptions--constraints)

---

## 1. Overview & Vision

A **native Mac Kanban Board app** that provides a fast, local-first project management experience as a direct replacement for Trello — without the web-browser dependency, slow load times, or account lock-in.

The app delivers core Kanban functionality (boards → lists → cards) with native macOS performance, keyboard shortcuts, Spotlight search integration, and Apple Reminders sync. Users can work fully offline; cloud sync is an optional enhancement.

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
| **Small teams (2–8 people)** | Teams that want lightweight project boards without Jira's complexity or Asana's overhead |
| **Trello refugees** | Users frustrated with Trello's pricing changes, slow web performance, or feature creep |

---

## 4. Core Feature Set (MVP)

### 4.1 Boards

Boards are the top-level container — a visual workspace for organizing work into columns (lists).

| # | Feature | Priority | Notes |
|---|---------|----------|-------|
| B-01 | Create board with name + icon/emoji | P0 | Default: 3 empty lists ("To Do", "In Progress", "Done") |
| B-02 | Rename / delete boards | P0 | Delete requires confirmation (cards may exist) |
| B-03 | Board sidebar listing — collapsible, searchable | P0 | Sidebar persists across app restarts |
| B-04 | Board background themes/colors | P1 | 6 preset palettes + custom hex picker |
| B-05 | Board cover image (unsplash integration) | P2 | Post-MVP if time permits |

**MVP Scope:** B-01, B-02, B-03, B-04  

---

### 4.2 Lists

Lists are columns within a board — the primary organizational unit of Kanban flow.

| # | Feature | Priority | Notes |
|---|---------|----------|-------|
| L-01 | Create list with name | P0 | Inline edit; "Add List" button at board's right edge |
| L-02 | Rename / delete lists | P0 | Delete requires confirmation (cards may exist) |
| L-03 | Reorder lists via drag-and-drop | P0 | Native macOS drag with visual ghost indicator |
| L-04 | Collapse/expand lists | P1 | "Archive" is post-MVP |
| L-05 | List background colors | P2 | Optional visual distinction between columns |

**MVP Scope:** L-01, L-02, L-03  

---

### 4.3 Cards

Cards are individual tasks/items within a list — the most interactive element in the app.

#### Card Creation & Display

| # | Feature | Priority | Notes |
|---|---------|----------|-------|
| C-01 | Create card with title (inline) | P0 | Double-click an empty space in a list to add; keyboard: `+` while focused on list |
| C-02 | Edit card title inline | P0 | Click to edit, Enter to save, Esc to cancel |
| C-03 | Reorder cards within a list (drag-and-drop) | P0 | Visual ghost indicator during drag; snap-to-grid animation |
| C-04 | Move cards between lists (drag-and-drop) | P0 | Cards can be dropped on the target list area |
| C-05 | Delete card with confirmation | P0 | `⌘Backspace` keyboard shortcut for fast delete |

#### Card Detail View

When a card is clicked, it opens an expanded detail view (modal or side panel).

| # | Feature | Priority | Notes |
|---|---------|----------|-------|
| C-06 | Title + description editing | P0 | Rich text not required for MVP — plain text with line breaks |
| C-07 | Add label(s) to card (see §4.4) | P0 | Up to 8 colors in color picker; multi-label support |
| C-08 | Set due date (see §4.5) | P0 | Date picker + optional time |
| C-09 | Activity log — who created/moved/edited the card | P1 | Post-MVP if time permits |

**MVP Scope:** C-01, C-02, C-03, C-04, C-05, C-06, C-07, C-08  

#### Keyboard Shortcuts (Cards)

| Shortcut | Action |
|----------|--------|
| `Enter` on focused list item | Create new card at bottom of list |
| `⌘N` while board is active | Create card in the first (leftmost) list |
| `⌘⏎` (Return) on card title field | Save and close detail view |
| `Esc` on any focused element | Close detail view / cancel edit |

---

### 4.4 Labels

Labels provide visual categorization of cards without disrupting the board layout.

| # | Feature | Priority | Notes |
|---|---------|----------|-------|
| LB-01 | Predefined color palette (8 colors) | P0 | Standard: Red, Orange, Yellow, Green, Blue, Indigo, Purple, Pink |
| LB-02 | Add/remove labels on individual cards | P0 | Toggle in card detail view; click to add, click again to remove |
| LB-03 | Search/filter by label (optional for MVP) | P1 | Post-MVP — filter bar above boards |

**MVP Scope:** LB-01, LB-02  

---

### 4.5 Due Dates & Reminders

Due dates add time-awareness to cards, with native macOS integration.

| # | Feature | Priority | Notes |
|---|---------|----------|-------|
| D-01 | Set due date on card (date only) | P0 | Date picker in card detail view; "Today", "Tomorrow", "Next Week" quick options |
| D-02 | Show due date badge on card | P0 | Visual indicator directly on the card surface (no need to open detail) |
| D-03 | Color-code by urgency | P1 | Overdue = red, Today = orange, Tomorrow = green, No date = gray |
| D-04 | Sync due dates → Apple Reminders | P2 | Post-MVP — uses `remindctl` or native `eventkitd` API if available |

**MVP Scope:** D-01, D-02  

---

## 5. User Stories

### As an individual user:
1. **I want to quickly create a new board for a project** so I can start organizing my tasks immediately.  
   → *Covers B-01 (create board with name + default lists)*

2. **I want to add cards to a list by just typing** so I don't have to click around.  
   → *Covers C-01 (inline card creation), L-01*

3. **I want to drag and drop cards between lists** so my workflow feels natural.  
   → *Covers C-04, C-05, C-06*

4. **I want to see which tasks are due today or overdue** at a glance from the board view.  
   → *Covers D-01, D-02, D-03*

### As a power user:
5. **I want keyboard shortcuts for everything** so I never have to leave my hands on the keyboard.  
   → *Covers all §4 keyboard shortcuts*

6. **I want to categorize cards with colors (labels)** so related work is visually grouped.  
   → *Covers LB-01, LB-02*

### As a Trello refugee:
7. **I want the same Kanban mental model I already know** — boards, lists, and cards in that order.  
   → *Covers B-01 (default 3 empty lists), L-01, C-01*

8. **I don't want to be forced into a web browser or create an account just to get started.**  
   → *Implied constraint: local-first data storage, no mandatory auth for MVP*

---

## 6. Data Model (High-Level)

```
Board
├── id: UUID
├── name: String
├── background: Color/Theme
└── lists: [List]
    ├── id: UUID
    ├── name: String
    ├── position: Int (for ordering)
    └── cards: [Card]
        ├── id: UUID
        ├── title: String
        ├── description: String?
        ├── position: Int (for ordering within list)
        ├── labels: [Label]
        │   └── color: Color
        ├── dueDate: Date?
        ├── createdAt: Date
        └── updatedAt: Date

```

**Storage:** SQLite (via SwiftData or Core Data) — local-first, zero sync required for MVP.

---

## 7. Out of Scope for MVP

These are explicitly deferred to post-MVP releases:

| Feature | Reason |
|---------|--------|
| Multi-user collaboration / real-time sync | Requires backend infrastructure; not part of "native Mac replacement" pitch |
| Card checklists (sub-tasks) | Nice-to-have but adds complexity to card detail view |
| Attachments / file uploads | Storage model needed; low priority for MVP |
| Card comments / activity log | Collaboration feature — deferred with multi-user work |
| Apple Watch companion | Small screen doesn't suit Kanban well |
| Dark mode / accessibility polish | Expected baseline for a native Mac app, but not blocking the MVP |
| Cloud sync / backup export | Local-first means data lives on disk; export is a convenience feature |
| Search across all boards (Spotlight integration) | Useful but can be added in v1.1 |

---

## 8. Assumptions & Constraints

| # | Assumption | Impact |
|---|-----------|--------|
| A-01 | The app runs on macOS 13+ (Ventura) as minimum version | SwiftUI is available; no need for older framework compatibility |
| A-02 | Users will have at least one active board open when launching the app | Sidebar persistence assumption |
| A-03 | No authentication required for MVP — local-only data | Simplifies onboarding but means "multi-device" doesn't work out of the box |
| A-04 | Card drag-and-drop uses native SwiftUI `DragGesture` / NSDraggingSource | Avoids third-party dependencies; may need custom rendering for smooth feel |
| A-05 | Default list names ("To Do", "In Progress", "Done") are English-only for MVP | Can be localized in v1.1+ |

---

## Appendix: Quick Reference — Feature Priority Matrix

```
P0 (Must-Have)    P1 (Should-Have)   P2 (Nice-to-Have)
────────────────  ────────────────   ─────────────────
Board CRUD        Board themes       Board cover images
List CRUD         List collapse      List background colors
Card CRUD         Card activity log  Attachments / files
Card drag-drop    Label search/filter Card checklists
Label assignment  Dark mode polish   Search across all boards
Due date setting  Apple Reminders    Apple Watch companion
Keyboard shortcuts Sync/backup export
```

---

*End of PRD v1.0 — ready for review and iteration.*
