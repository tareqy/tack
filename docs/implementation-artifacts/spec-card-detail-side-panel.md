---
title: 'Card Detail Side Panel'
type: 'feature'
created: '2026-07-12'
status: 'done'
review_loop_iteration: 0
baseline_commit: '0ce25c44d1df1a700dab102aebef2b9f15104894'
context:
  - '{project-root}/PRD-Kanban-Board-Mac.md'
  - '{project-root}/docs/superpowers/plans/2026-07-08-card-detail-polish.md'
---

# Card Detail Side Panel

<frozen-after-approval reason="human-owned intent — do not modify unless human renegotiates">

## Intent

**Problem:** Tack only presents card details as a modal sheet, which obscures the board workflow and gives users no choice of presentation even though the PRD permits a side panel.

**Approach:** Add an app-wide, persisted Settings choice—Sheet (default) or Side Panel—and route every card-detail entry point through one RootView-owned presentation state. Side Panel uses SwiftUI's native trailing inspector while reusing the existing staged editor and save contract.

## Boundaries & Constraints

**Always:** Preserve Sheet as the default and retain double-click, context-menu, and ⌘O entry points in Board, List, and Calendar views. Preserve staged edits, one `applyCardEdits` call/undo step, ⌘⏎ Save, Esc/Cancel discard, and close-before-delete ordering. The inspector is nonmodal: the board stays visible and safe navigation remains usable, while focused text-input command guards continue to block conflicting mutations. Opening another card or changing board/view mode with dirty drafts must offer “Discard Changes” and “Keep Editing”; never lose drafts silently. Persist the preference app-wide, namespace/reset it for UI tests, keep the current presentation stable if Settings changes mid-edit, key editor identity by card ID, and retain existing accessibility wire values and sheet geometry. Use native trailing inspector chrome, 340/380/520-point min/ideal/max widths, a scrolling form body, and a pinned action footer.

**Ask First:** Changing the default to Side Panel; replacing explicit Save/Cancel with live autosave; adding shortcuts; or changing card/schema/export data.

**Never:** Maintain three duplicated presenters, silently replace a dirty inspector's card, render a deleted SwiftData object, regress existing sheet behavior, or introduce fixed colors/typefaces that break Tack's adaptive macOS design.

## I/O & Edge-Case Matrix

| Scenario | Input / State | Expected Output / Behavior | Error Handling |
|----------|---------------|----------------------------|----------------|
| Default | Missing or unknown preference | Card detail opens in the existing sheet | Fall back to Sheet |
| Side panel | Preference is Side Panel; any supported open action | One right-edge inspector opens for that card; board remains visible | Resolve card by ID; close if it no longer exists |
| Save/close | Inspector contains staged edits | Save commits once and closes; Cancel/Esc discard and close | Never mutate before Save |
| Dirty transition | User opens another card or changes board/mode | Ask to discard or keep editing | Keep Editing cancels the transition |
| Delete | Edited card is deleted | Close presentation before store deletion | Never re-render the deleted model |
| Preference changes mid-edit | Settings changes while detail is open | Current surface remains stable; new choice applies next open | No draft reset |

</frozen-after-approval>

## Code Map

- `Tack/Views/CardDetail/CardDetailPresentation.swift` -- stable preference enum and native Settings form.
- `Tack/Views/RootView.swift` -- owns presented card ID, active presentation, transition guard, sheet, and inspector.
- `Tack/Views/Board/{BoardView,ListBoardView,CalendarBoardView}.swift` -- route all open/delete actions through RootView callbacks.
- `Tack/Views/CardDetail/CardDetailView.swift` -- reusable sheet/inspector editor, explicit close/dirty callbacks, adaptive layout.
- `Tack/Support/{AppLaunchConfig,AccessibilityID}.swift` and `Tack/TackApp.swift` -- isolated defaults key, Settings scene, test reset/override, and presentation markers.
- `TackUITests/CardDetailPresentationUITests.swift` -- side-panel placement, lifecycle, transition, entry-point, and persistence coverage.

## Tasks & Acceptance

**Execution:**
- [x] `Tack/Views/CardDetail/CardDetailPresentation.swift`, `Tack/TackApp.swift`, `Tack/Support/AppLaunchConfig.swift` -- add the Settings preference and deterministic test isolation/override.
- [x] `Tack/Views/RootView.swift`, `Tack/Views/Board/*.swift` -- centralize ID-based presentation, native inspector routing, safe deletion, and dirty-transition decisions.
- [x] `Tack/Views/CardDetail/CardDetailView.swift` -- preserve staged semantics while adding inspector sizing, scrolling body, pinned footer, explicit close, and dirty reporting.
- [x] `Tack/Support/AccessibilityID.swift`, `TackTests/AppLaunchConfigTests.swift`, `TackUITests/CardDetailPresentationUITests.swift` -- cover preference parsing/reset, placement, Save/Cancel/Esc/Delete, dirty transitions, all view modes, and relaunch persistence.
- [x] `PRD-Kanban-Board-Mac.md`, `project.yml`/generated project -- document the shipped option and include new sources.

**Acceptance Criteria:**
- Given a fresh install, when a card is opened, then the unchanged modal sheet appears.
- Given Side Panel is selected, when any card-detail entry point is used, then the same editor opens at the window's trailing edge and the choice survives relaunch.
- Given either presentation, when Save, Cancel, Esc, or Delete is used, then existing persistence, discard, close, and deletion contracts remain identical.
- Given dirty inspector edits, when a context-changing action is attempted, then Tack requires an explicit discard decision and “Keep Editing” preserves every draft.

## Spec Change Log

## Design Notes

Use Tack's adaptive semantic palette (`windowBackgroundColor`, `textBackgroundColor`, `separatorColor`, board-theme wash, and `accentColor`) and existing type roles (`headline`, `title2`, `body`, `caption`). The signature is an edge-anchored working rail: native divider, compact “Card Details” header/close control, full editor, and pinned actions—no ornamental panel skin.

```text
┌ sidebar ┬ board / list / calendar ┬ Card Details × ┐
│         │ visible working context │ scrolling form │
│         │                         ├────────────────┤
│         │                         │ Delete Cancel Save
└─────────┴─────────────────────────┴────────────────┘
```

## Verification

**Commands:**
- `make gen` -- new Swift sources are included in the generated Xcode project.
- `make unit` -- preference/config and existing store contracts pass.
- `make ui` -- default-sheet regressions plus side-panel workflows pass serially.
- `make build` -- warning-free arm64 macOS build succeeds.

**Results (2026-07-12):** `make gen`, `make unit` (381 tests), and a clean `make build` succeeded. The UI target and all twelve new side-panel scenarios compile, but two `make ui` attempts were stopped by the macOS automation host before test entry (`Timed out while enabling automation mode`). Live verification against isolated UI-test stores confirmed the default sheet, real Settings selection, native side panel, relaunch persistence, dirty card/board transition guards, focused-editor shortcut safety, board-focused Esc, and reconciliation of an external inline rename without stale-save rollback.

## Suggested Review Order

**Presentation orchestration**

- Central UUID state snapshots presentation choice and gates dirty context transitions.
  [`RootView.swift:385`](../../Tack/Views/RootView.swift#L385)

- Native sheet and inspector resolve the same live card editor.
  [`RootView.swift:211`](../../Tack/Views/RootView.swift#L211)

- Transition routing closes safely before board, mode, import, or model destruction.
  [`RootView.swift:434`](../../Tack/Views/RootView.swift#L434)

**Shared editor safety**

- One staged editor branches only at layout, preserving Save and Cancel semantics.
  [`CardDetailView.swift:63`](../../Tack/Views/CardDetail/CardDetailView.swift#L63)

- The native inspector keeps form scrolling separate from pinned actions.
  [`CardDetailView.swift:106`](../../Tack/Views/CardDetail/CardDetailView.swift#L106)

- Three-way reconciliation adopts external clean-field edits while preserving local drafts.
  [`CardDetailView.swift:261`](../../Tack/Views/CardDetail/CardDetailView.swift#L261)

- Date and time fields publish focus so board shortcuts cannot conflict.
  [`DueDatePicker.swift:48`](../../Tack/Views/CardDetail/DueDatePicker.swift#L48)

**Preference and isolation**

- Stable wire values default unknown preferences back to Sheet.
  [`CardDetailPresentation.swift:5`](../../Tack/Views/CardDetail/CardDetailPresentation.swift#L5)

- Settings writes the shared preference without moving an open editor.
  [`CardDetailPresentation.swift:28`](../../Tack/Views/CardDetail/CardDetailPresentation.swift#L28)

- Namespaced test defaults make reset, override, and relaunch deterministic.
  [`AppLaunchConfig.swift:97`](../../Tack/Support/AppLaunchConfig.swift#L97)

- The app scene exposes native macOS Settings.
  [`TackApp.swift:97`](../../Tack/TackApp.swift#L97)

**Routing and commands**

- Board surfaces delegate open and destructive actions to RootView.
  [`BoardView.swift:15`](../../Tack/Views/Board/BoardView.swift#L15)

- Shortcut guards preserve inspector editing without opening windows behind it.
  [`AppCommands.swift:31`](../../Tack/Commands/AppCommands.swift#L31)

**Verification and product contract**

- Twelve UI scenarios cover surfaces, persistence, transitions, commands, and reconciliation.
  [`CardDetailPresentationUITests.swift:10`](../../TackUITests/CardDetailPresentationUITests.swift#L10)

- Launch-config unit tests pin fallback and isolation behavior.
  [`AppLaunchConfigTests.swift:12`](../../TackTests/AppLaunchConfigTests.swift#L12)

- PRD C-12 records user-visible behavior and acceptance.
  [`PRD-Kanban-Board-Mac.md:420`](../../PRD-Kanban-Board-Mac.md#L420)
