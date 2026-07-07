# AI Build Coordination Ledger

Append-only progress ledger kept by the coordinating model during development
(referenced by AI_BUILD_REFLECTION.md). Committed verbatim after publication.

> NOTE: commit hashes below predate the post-publication history rewrite that
> corrected author identity — they will not resolve in this repository. Commit
> SUBJECTS are unchanged; map entries to current history by subject. "Kanban"
> is the pre-rename working title of Tack.

---

# SDD Progress Ledger — Kanban Mac app

Plan: /Users/ty/.claude/plans/hey-claude-i-have-piped-gadget.md

Task 1: complete (commits 94bd787..ebc22f5, review clean after 1 fix round)
  Carried minors for final review: §9.4 LB-02 is restatement-by-reference to C-07; accepted deviation: badge colors = red/orange/amber/gray-for-later, no badge when no due date; Board.position mutation mechanism = creation order (Task 5 must pin down in sidebar).
Task 2 (M0): complete (commits 7e1ae7d..34891b7, review clean)
  Minors carried: GENERATE_INFOPLIST_FILE set at settings.base instead of test-targets-only; rootView a11y identifier sits on the placeholder Text — recheck when RootView gains real content (M3).
  Ops note: Makefile exports DEVELOPER_DIR (machine has CLT-only xcode-select).
Task 3 (M1) debugging note: unit suite hung 3x — root cause NSUndoManager exception ("must begin a group before registering undo") in UndoRedoTests via BoardStore.moveCard: no run loop in unit tests => groupsByEvent never opens a group; exception killed the main-actor test task and Swift Testing waited forever. Fix directed: explicit begin/endUndoGrouping in withUndoGroup; groupsByEvent=false in TestContainer. Process rule added: implementer briefs must mandate FOREGROUND xcodebuild runs + zombie pkill before runs + ~6min hang watchdog.
Task 3 (M1): complete (commit 65fff93, review clean, 63 unit tests green)
  Minors carried: ensureLabelsSeeded sits on undo stack (empty group risk); save() is try? (needs error channel when UI lands); updateDetails untested. Coverage gap noted: no dedicated undo tests for delete ops / same-list moveCard (M7 should add).
  Design note: hybrid undo — SwiftData auto everywhere except cross-list moveCard (explicit registerUndo, recursive re-registration); groupsByEvent=false + explicit per-op grouping REQUIRED (M7 UI wiring must preserve).
Task 4 (M2): complete (commit 19b73b9, review clean, gate 3x green, 80 unit tests)
  SPIKE VERDICT: native .draggable/.dropDestination mechanism PROVEN — no fallbacks needed. Recipe: press 0.6s + hold 0.4s; cross-list drop on footer zone; reorder at target top-third (dy 0.15); poll-before-retry.
  Minors carried: try! on uiTest container path; unused seeded container on plain --uitest smoke path; AppLaunchConfig static/instance API redundancy.
  M3 MUST: confirm real (non-XCUITest) launch presents a window (WindowGroup quirk); keep root-view id for smoke; keep spike fixture working (drag e2e regression).
Task 5 (M3): complete (commit 13065df, review clean, 93 unit + 11 UI tests green)
  Minors carried: next-selection-on-delete branch untested (extract pure helper later); no final else in KanbanApp content builder; try! production() force-crashes on corrupt store (needs graceful failure — schedule in M7 or final fixes); smoke asserts invisible Color.clear marker.
  Host quirks found: NavigationSplitView drops .accessibilityIdentifier (use sibling Color.clear marker); sidebar-column .toolbar lands in unreachable overflow (attach toolbar to NavigationSplitView).
  Window quirk resolved: XCUITest-only; real launches present windows fine; ensureWindow stays.
Task 6 (M4): complete (commits ff51fa5..8d07811, review clean after 1 fix round, 100 unit + 16 UI green)
  Important fixed: defaultSize 1440x850 so Add List visible on fresh boards (verified vs ListCRUD only; M5's full-suite runs are the full gate).
  Minors carried: Esc-cancel paths (list rename/add-list field) untested; scrollColumnsToTrailingEnd uses bounded sleeps not poll; insertion indicator not edge-aware (matches spike); AddListButton duplicates trim/guard logic of InlineEditableText.
  New host trap recorded: ScrollView-clipped pixels swallow clicks while isHittable==true — use scrollColumnsToTrailingEnd pattern for right-edge interactions.
  M5 note in source: ListColumnView columns carry ListTransfer destinations; CardTransfer coexistence must be verified empirically.
Task 7 (M5): complete (commit 5a65449, review clean, 100 unit + 26 UI green x2)
  KEY FINDING (memory + code docs): SwiftUI dropDestination does NOT dispatch by payload type; child destinations swallow all types; stacked typed destinations shadow. Architecture: container=ListTransfer, rows=CardTransfer, footer=dual-import ColumnDropPayload. Do not refactor back.
  Minors carried: double-click-title rename lacks direct e2e (ASSIGNED to M6 brief); rapid-entry "no focus loss" not strictly asserted; latent edge: list-drag released onto a card row is swallowed (tall columns only); add-card button is a 44pt card-drop dead zone; .onDeleteCommand deferred to M7 (needs focusable rows).
  Env watch: 3 "Failed to activate application" launch flakes in one run, clean in both final runs.
Task 8 (M6): complete (commit 2990bdb, review clean, 111 unit + 34 UI green x2)
  Deviation accepted (evidence-backed): .accessibilityRepresentation replaces .accessibilityValue on card-face dots/badge (macOS AX surfaces StaticText content as .value under XCUITest; scoped to 2 components).
  Minors carried: includesTime reset only inside dueDateChanged branch (latent for time-of-day support); Return-inserts-newline in description + DatePicker field control not e2e-pinned; cross-card staged-value non-leakage relies on sheet(item:) semantics, not a test.
  Harness note: >10min foreground commands get auto-backgrounded by the subagent harness itself — briefs should have implementers tee to a log and read it fully after (M6 did this correctly).
Task 9 (M7): complete (commits cec599d + 9ebdaec hardening, review + re-review clean) — PHASE A / MVP DONE
  Final state: 151 unit + 47 UI tests green. Menu-bar command layer, focus model, undo wiring, arrow-key navigation, keyboard card-move, full persistence journey.
  ADJUDICATED platform limitations (PRD synced): board DELETION not undoable (SwiftData cascade-delete undo-snapshot fatal assert; confirmation-gated; soft-delete on roadmap); board CREATION undo verified SAFE + e2e-pinned; Edit menu shows plain "Undo" (SwiftUI doesn't surface action names).
  Guard mechanism: textInputFocused focused-value published by all 9 text inputs (responder checks impossible — SwiftUI.KeyViewProxy) + action-level guardedMutation (isSheet). 
  Minors open for Phase B/final: no e2e deletes card-bearing board; post-reattach same-event registration residue (theoretical); edge-list menu enablement e2e; left-direction empty-skip unit test; one-shot 47-test single-process run not yet green post-fix (next full gate closes free).
Task 10 (M8): code complete + review APPROVED PENDING GATE (commit 141b3e8, 172 unit green, 2/3 theme e2e passed)
  BLOCKED on quiet machine: machine-wide XCUITest keystroke-delivery stalls (user on a call; proven environmental by pristine-HEAD bisect). Gate checklist from reviewer: (1) testCustomHexTheme e2e (the only true keystroke proof), (2) all 7 regression suites green post-diff, (3) testInvalidHexRejected re-run alongside, (4) full ~50-test coverage shown per-suite.
  Minors carried: swatch grid may wrap in 260pt popover (M10 visual pass owns); ThemeResolution resolved twice per render; unknown-preset+valid-hex case implied not literal in matrix.
  M9 brief staged; M9's verification run doubles as this gate.
Task 10 (M8): COMPLETE — quiet-machine gate satisfied during M9 verification (testCustomHexTheme PASS, testInvalidHexRejected PASS, all regression suites green in the 54/54 run). Commit 141b3e8.
Task 11 (M9): implementation + gate complete (commit 6599439, 175 unit + 54 UI green across 11 suites) — review pending.
  Takeover note: original implementer died on repeated infra errors; fresh agent verified inherited code (no product changes needed) and fixed one test-infra bug: cardIdentifiersByPosition raced SwiftUI re-render after drops — now uses atomic container.snapshot() read (shared helper; DragAndDrop suite verified unaffected).
Task 11 (M9): complete (commits 6599439 + 3d761d3 fixes, review + re-review clean, 176 unit + 55 UI)
  Fixed in review round: setCollapsed no-op guard (guard-before-group pattern); list-drop-on-pill e2e (the one unique path).
  Minor carried: collapsed pill hides list name from AX tree (VoiceOver reaches it via chevron label only); midline-center drop assumption in the pill e2e is slightly delicate.
Task 12 (M10): complete (commit 2f002e8, review clean, 186 unit + 57 UI green)
  Urgency colors per PRD policy (screenshot-verified both appearances); dark-mode audit table delivered; audit-driven contrast fixes (label chips, theme swatches, default swatch opacity).
  Minors carried: amber-vs-orange margin rests on brightness not hue; --appearance flag not gated on --uitest (consistent with codebase pattern); one known-class SmokeUITests ensureWindow flake (retried clean).
Task 13 (M11): complete — FINAL FEATURE MILESTONE, Phase B done (192 unit + 62 UI green across 12 suites; full gate run suite-by-suite).
  Label filter (LB-03) shipped as PURE VIEW STATE on BoardView (BoardStore untouched, as specced): `LabelFilter.visibleCards` (OR semantics) threads through `ListColumnView`'s render loop only; every drop-index computation (`appendCard`/`dropOnRow`/`handleDrop`) deliberately still reasons about the FULL `sortedCards` — documented in code, not touched. Count badge format migrated to "visible/total" while a filter is active, plain total otherwise (collapsed pills too); no existing assertion needed editing (they never activate a filter, so the sanctioned migration turned out to be a no-op in practice).
  KEY FINDING: a bare (no-modifier) `.keyboardShortcut(.escape, modifiers: [])` Commands `Button` does NOT fire (proved via a live UI run: ⌘F worked, plain Esc silently did nothing). Switched Esc-hide-and-clear to `.onExitCommand` on `BoardView` — the SAME mechanism every other Esc-cancel in this app already uses (inline rename/add-card/add-list fields, the card-detail sheet) — which also gives "Esc in an editor keeps its cancel semantics" for free via ordinary responder-chain precedence, no explicit textInputFocused/isSheet guard needed for THAT path (the ⌘F toggle itself still uses the established guardedMutation/textInputFocused gate).
  Carried cleanups closed: SelectionNavigation left-direction empty-list-skip unit test (mirrors the existing right-direction one); KeyboardShortcutUITests.testMenuItemsExistAndEnabledStates extended with edge-list Move-Card-Left/Right disablement.
  README.md added at repo root (build/run/test, quiet-machine + one-time automation permission note, 4-layer architecture sketch, test layout, P2 roadmap).
  Minor carried for the final review: confirmationDialog-vs-global-Esc interaction (e.g. delete-list confirm open while the filter bar is also visible) was reasoned about but not e2e-pinned — believed safe (confirmationDialog is presented sheet-style, same reasoning as the card-detail sheet already relying on), not empirically proven the way the bare-Esc Commands finding was.
Task 13 (M11): complete (commit 65e863e, review clean, 192 unit + 62 UI green) — ALL FEATURE MILESTONES DONE
  Esc via .onExitCommand (Commands .escape shortcut proven non-firing on this platform); README + roadmap shipped; carried cleanups landed (left-skip unit test, edge-list enablement e2e).
  Important carried to FINAL REVIEW: Esc-while-confirmationDialog-open interaction reasoned-not-tested (low probability). Minor: LabelFilter re-derives label colors instead of CardLabel.color (pre-existing pattern inconsistency).
  Note: human commit 32efd66 (AGENTS.md/CLAUDE.md by Tareq) sits between M10 and M11 — in the final review range but not agent work.
Task 14: COMPLETE — final whole-branch review + fix wave + re-review + cleanups (commits ed740ea, 915a820)
  Final verdict: READY TO SHIP. 209 unit + 72+ UI tests green across 14 suites.
  Fix wave delivered: E-01 JSON export (the review's Critical catch — P0 silently omitted by all milestones), keyboard pass (bare-arrow bootstrap, ⌘O open card, collapse-aware ⌘N, Return-alias PRD sync), BoardSnapshot visibility seam (collapse+filter aware nav/moves, selection clearing), 3 regression e2es, housekeeping batch, pre-ship minors.
  E-01 save-panel leg MANUALLY VERIFIED 2026-07-06 17:54: ⇧⌘E → panel → user-saved to ~/Downloads/Kanban Export 2026-07-06.json → decoded: formatVersion 1, both boards, exact fixture lists/cards, labels [green,blue]/[red], 4 due dates. (Remote-hosted sandboxed NSSavePanel unreachable by both XCUITest and System Events — automation limit confirmed twice.)
PROJECT COMPLETE.
Post-v0.1.0: adversarial report (docs/reports/, pre-fix-wave snapshot) triaged 2026-07-07 — 3 surviving items fixed in 85502d7: bare left/right selection commands wired (C-10 complete in all 4 directions, e2e-pinned); C-02 PRD wording synced to implemented double-click-edit interaction; CLAUDE.md undo invariant corrected to the adjudicated asymmetric groupsByEvent reality. Remaining report items confirmed already-fixed (fix wave) or accepted-as-roadmap (save() error channel, undo contract suite, NFR timing/force-quit).
