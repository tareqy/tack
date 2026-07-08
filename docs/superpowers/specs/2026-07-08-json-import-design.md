# JSON Import (Backup/Restore) — Design (E-02)

## Context

E-01 shipped one half of data portability: File ▸ Export All Boards… (⇧⌘E) writes the full board/list/card/label graph as deterministic JSON (`ExportEnvelope`, `formatVersion: 1`, sorted keys, ISO-8601 dates, relationships encoded purely by nesting — no IDs). The PRD tracks the other half as **E-02 — Backup/restore: import a previously exported JSON file** (§4.6, P1, deferred in §7). This feature closes the loop: a backup you can't restore is half a feature.

Format facts that shape everything (all verified against `Tack/Export/ExportDocument.swift`):

- **No identifiers anywhere in the format** — model UUIDs are deliberately omitted, so duplicate detection by identity is impossible; the honest semantics are append-as-new or replace-all, never merge.
- `ExportDocument.decode` ignores `formatVersion`; the importer must gate it explicitly.
- Foundation's `.iso8601` strategy rejects fractional seconds; `BoardList.createdAt` is absent from the format and must be synthesized; nil optionals are key-omitted; unknown keys are silently ignored.
- `ExportJSONDocument.init(configuration:)` is a stub explicitly reserved for E-02 — it stays unused (we import via URL, not `ReadConfiguration`); its comment gets updated to say so.

## Locked decisions (user-confirmed 2026-07-08)

- **Two modes, chosen per import** via a dialog after the file is picked and decoded: **Add to Existing** (append after current boards) and **Replace All Boards** (delete everything first, then load). The format's lack of IDs rules out merge; re-importing a file in append mode duplicates its boards — acceptable, nothing is ever lost.
- **Undo, split and spike-gated:** append is **one undoable ⌘Z step** ("Import Boards"), contingent on an on-disk spike proving multi-board-graph undo/redo neither hits the SwiftData fatal assert nor silently corrupts on redo; if the spike fails, append falls back to non-undoable (detach + documented) with **no interface change**. Replace is **always non-undoable** — the exact `deleteBoard` detach-and-clear pattern (a mode that deletes Boards has no other option; see CLAUDE.md pitfalls).
- **Validation: hard-reject only structural failure** — malformed JSON, missing required fields, `formatVersion != 1` → nothing imported, user-visible error. Everything else in a decodable file is **sanitized quietly**: unknown label names dropped, `dueDate` re-normalized to local start-of-day when `includesTime == false`, ordering taken from array order (DTO position values are ignored at materialization — pinned by the store-level scrambled-positions test, not the sanitize tests), `themeName` kept verbatim (render-time `resolve` already maps unknowns to the default theme — that *is* the fallback), `customThemeHex` canonicalized-or-nil.
- **Empty backups guard Replace only:** a zero-board envelope (as produced by exporting an empty store — note the format's required `exportedAt` key must still be present) decodes fine and may be *added* (a no-op), but **Replace All is unavailable for it** — closing the one total-data-loss vector (wiping every board behind a dialog reading "Import 0 Boards") without rejecting a valid file.
- **Format stays v1.** No UUID/`formatVersion` bump in E-02; the explicit version gate added here is exactly the hook a future v2 needs.

## Design

The winning shape (from a three-design panel judged on codebase fit, risk, and maintenance cost): **zero new app-target source files** — the existing `ExportEnvelope` DTOs are the import carrier, the codec grows a pure import half, and `BoardStore` grows the two mode methods.

### 1. Codec layer — pure decode + validate + sanitize (`Tack/Export/ExportDocument.swift`)

```swift
enum ImportError: Error, Equatable, LocalizedError {
    case unreadable(detail: String)   // file-read failure (missing/unreadable file — wrapped by the
                                      // read step in both the fileImporter completion and the launch
                                      // hook), malformed JSON, missing required field, undecodable date
    case unsupportedVersion(Int)      // formatVersion != ExportDocument.formatVersion
    case emptyReplace                 // replace-all requested with a zero-board envelope
    case saveFailed(detail: String)   // context.save() threw; wrapped at the store boundary after rollback
    var errorDescription: String? { get }   // user-facing alert copy
    var recoverySuggestion: String? { get } // second alert line; always ends in the invariant
    var caseName: String { get }            // stable token for the e2e marker ("unreadable", "saveFailed", …)
}

extension ExportDocument {
    static func decodeForImport(_ data: Data, calendar: Calendar = .current) throws -> ExportEnvelope
}
```

`decodeForImport` = decode (`JSONDecoder`, `.iso8601`; any `DecodingError` → `.unreadable` — Codable non-optionality enforces required fields for free) → explicit `guard envelope.formatVersion == ExportDocument.formatVersion else throw .unsupportedVersion(...)` → pure sanitize returning a rewritten `ExportEnvelope`:

- card labels filtered to `LabelColor` rawValues, deduplicated, reordered to palette order;
- `dueDate` → `calendar.startOfDay` when `includesTime == false` (calendar injectable so the rule is table-testable under a pinned time zone);
- `customThemeHex` → canonical form or nil (preserves the store's "never persist unparsable hex" invariant);
- `themeName`, `exportedAt`, and all DTO `position` fields are **not** rewritten — themes resolve at render, and the materializer never reads DTO positions (see below), so sanitizing them would be dead code.

Sanitization is **idempotent** (`sanitize ∘ sanitize == sanitize`), pinned by a unit test.

### 2. Store layer — materialization, undo, atomicity (`Tack/Store/BoardStore.swift`)

The store's first throwing methods:

```swift
@MainActor @discardableResult
func importBoards(_ envelope: ExportEnvelope, importedAt: Date = .now) throws -> [Board]        // append

@MainActor @discardableResult
func replaceAllBoards(with envelope: ExportEnvelope, importedAt: Date = .now) throws -> [Board] // replace
```

Both share a private `materialize(_:basePosition:importedAt:)`: memberwise `Board`/`BoardList`/`Card` construction with fresh UUIDs (`createBoard` is deliberately **not** used — it injects three default lists), board positions `basePosition + arrayIndex` where `basePosition = (max existing ?? -1) + 1` for append and `0` for replace, list/card positions from array enumeration (**DTO positions are dead by construction** — no trust-the-file path exists), `BoardList.createdAt` synthesized from the single `importedAt` (injectable for deterministic tests), and labels attached by **fetching the existing unique 8-row `CardLabel` palette into a dictionary and appending those rows** — never inserting, mirroring `toggleLabel`'s guard: a missing palette row is skipped, never created.

**Atomicity — reject means zero writes.** Decode/gate/sanitize run entirely before any store call. Materialization performs all inserts with no intermediate saves, then exactly **one `context.save()`** — one SQLite transaction, so a committed import is all-or-nothing. On save failure: `context.rollback()` discards every unsaved insert (and, in replace mode, revives the unsaved deletes), then the error is wrapped as `ImportError.saveFailed(detail:)` and thrown — on-disk state is untouched, which is why every error message can truthfully say *"Nothing was imported. Your existing boards are unchanged."* Wrapping at the store boundary means the alert and the e2e marker only ever see `ImportError`.

**Undo — append (spike-gated).** `withUndoGroup`'s closure is non-throwing (`() -> Void`), so `importBoards` uses an **inline, defer-closed undo bracket** instead — leaving the shared helper untouched (it is the most safety-critical shared code in the app; three documented pitfalls hang off it). `importBoards` first **returns early (before opening the bracket, before any save) when `envelope.boards.isEmpty`** — the `moveBoards` identity no-op precedent, so an empty Add never eats a ⌘Z step. Then: hold the manager, `beginUndoGrouping()` / `setActionName("Import Boards")`, and install a `defer` that closes the group on the held manager, reattaches it to the context, and — if a failure flag was set — calls `removeAllActions()`. Success path: materialize → save → defer closes the group; one ⌘Z then deletes every imported board/list/card and detaches label joins (palette rows untouched — fetched, not inserted); Edit menu reads "Undo Import Boards". Failure path: the catch sets the flag, **detaches the manager from the context** (so rollback's reverts can't register), calls `context.rollback()`, and throws — the defer then closes the still-open group, reattaches, and clears the stack (the group referenced discarded objects — same rationale as `deleteBoard`'s stack clear). Net order on failure: detach → rollback → close group → reattach → clear stack → throw, with the defer guaranteeing the group can never be left open on any exit path.

**Undo — replace (always non-undoable).** `replaceAllBoards` first guards `!envelope.boards.isEmpty else throw ImportError.emptyReplace` (defense in depth behind the dialog-level guard), then detaches the manager for the entire delete-all + materialize + save span with `defer { reattach; removeAllActions() }` — verbatim the `deleteBoard` pattern. Delete-existing and insert-new share the one save, so a failed replace can never leave deleted-but-not-replaced data.

### 3. UI layer (`AppCommands`, `FocusedValues`, `RootView`, `EmptyStateView`)

- **Menu:** File ▸ **Import Boards…** (⇧⌘I, symmetric with ⇧⌘E), directly after Export All Boards… in the existing scene-level `CommandGroup`. Routed through `guardedMutation`; enabled whenever `boardSelection` is published — effectively always, **including at zero boards** (restore-into-empty is the headline case) — **except while a text editor has focus**: both Import and Export gray out on `textInputFocused` (amended post-manual-gate 2026-07-08 — `guardedMutation` already swallowed the action while typing, but an enabled-looking menu item whose mouse click silently no-ops is a trap for the mouse path; the gray-out matches the Delete/Open/Move Card items' existing pattern, and the action-level guard stays as belt-and-suspenders). New `BoardSelectionActions.importBoards: () -> Void` closure — a `Commands` value cannot present a `.fileImporter`, so the command flips `RootView` state (the E-01 pattern).
- **Empty state:** `EmptyStateView` gains a secondary **"Import from Backup…"** button wired to the same closure, with a new `AccessibilityID` constant.
- **File pick → read:** `.fileImporter` on `RootView` (`allowedContentTypes: [.json]`, single file). The completion calls `startAccessingSecurityScopedResource()` **unconditionally and ignores its return for the read** (it returns `false` for URLs already covered by the entitlement on macOS 14 — gating the read on it would break legitimate imports), gates only the paired `stop` on that Bool, reads the bytes, and calls `decodeForImport`.
- **Mode dialog:** success sets `pendingImport` **after a hop to the next main-queue tick** (a same-tick fileImporter→confirmationDialog presentation race is a known SwiftUI hazard; verify by hand during implementation whether the hop is needed and record the result here). `confirmationDialog`, title *"Import N Boards"* with counts in the message — *"This file contains N boards (L lists, C cards). 'Add to Existing' keeps your current boards and adds the imported ones after them. 'Replace All Boards' deletes your M current boards first — replacing cannot be undone."* Buttons: **Add to Existing** (default), **Replace All Boards** (`role: .destructive`; **omitted when the envelope has zero boards**, with the message noting why), **Cancel** (clears `pendingImport`, no mutation). Copy stays silent on append undoability (spike-dependent).
- **Post-import selection:** `if let first = imported.first { selectedBoardID = first.id }` — mirrors board creation; the `if let` means an empty append never clears an existing selection, and after Replace the dead selection is repointed.
- **Errors:** the app's **first `.alert`** — title "Import Failed", message from `ImportError.errorDescription` (unreadable: *"This file couldn't be read as a Tack export. It may be damaged or not a Tack export file."*; unsupportedVersion(n): *"This file uses export format version n. This version of Tack can only import version 1."*; saveFailed: *"Tack couldn't save the imported boards."* with the detail), second line from `recoverySuggestion` always ending *"Nothing was imported. Your existing boards are unchanged."* Every error reaching the alert is an `ImportError` (the store wraps save failures), so no generic-`Error` path exists.

### 4. Test hook — `--import-from` / `--import-mode` (mirrors `--export-to`)

XCUITest cannot drive the remote-hosted `NSOpenPanel` (same class as E-01's save panel, PRD §9), and the sandboxed runner cannot place files in the app's container — so the app produces its own input: a prior launch exports via `--export-to` into the shared `Application Support/UITest/` dir, and the JSON **survives `--reset`** (which deletes only the sqlite files).

- `AppLaunchConfig` gains `importFrom: String?` (`--import-from <filename>`, resolved against `ModelContainerFactory.uiTestDirectory()`) and `importMode: String?` (`--import-mode add|replace|ask`, default add). `add`/`replace` decode and import directly (deterministic content tests); `ask` decodes and presents the **real mode dialog**, letting a test drive its buttons — the only automatable path onto the dialog, since the panel is undriveable. Both flags `--uitest`-gated in `RootView.init` like `exportTo`; **no static passthrough** (`exportTo` has none either).
- `RootView.runImportSelfCheckIfNeeded()` (`.onAppear` + one-shot guard; import deliberately drops export's extra `.onChange(of: boards.count)` re-trigger — that leg exists because export reads the `@Query`, while import reads the file and store directly) reads the file (a read failure is wrapped as `.unreadable`), then routes through the **same completion path the dialog buttons use** — production `decodeForImport`, the store method for the requested mode, and the §3 post-import selection rule (so `selectedBoardID` repoints exactly as in the production flow) — and publishes a detached-`accessibilityRepresentation` marker `import-self-check` (new `AccessibilityID`): success → `ok|<ALL post-import board names in position order>|<first list's card titles>` computed from **live post-import store state** (the only oracle distinguishing add from replace when names duplicate); failure → `error|<ImportError.caseName>`; dialog dismissed under `ask` mode → `cancelled` — stable tokens, never localized copy.
- `TackUITestCase.launch` gains `importFrom:`/`importMode:` parameters. `relaunchPreservingStore()` deliberately re-passes **neither** flag — a preserved-store relaunch can never double-import (and `FixtureSeeder` skips non-empty stores), which is what makes the persistence leg valid. This non-forwarding is intentional; do not "fix" it.

### 5. Model, PRD, docs

- **No schema change.** `TackSchemaV1` untouched; import format version and schema version remain independent axes.
- **PRD amendments:** §4.6 E-02 row → shipped (two modes, ⇧⌘I, undo contract per spike outcome, v1-only gate, whole-file rejection, empty-backup Replace guard); §7 — remove the deferred backup/restore row (singular), and move E-02 out of the deferred P1 list in the Appendix Feature Priority Matrix; §4.3 shortcuts table adds ⇧⌘I; §9 new acceptance criteria (round trip restores boards/lists/cards/labels/due dates/themes in order; append is one ⌘Z step *or* documented non-undoable per spike; Replace deletes first, clears the undo stack, and is unavailable for empty backups; an invalid file imports nothing and shows an error) plus an automation note mirroring E-01's save-panel paragraph: open-panel leg manually verified, content correctness automated via `--import-from`.
- **README:** add JSON import (two modes, ⇧⌘I) to the feature summary alongside JSON export; the roadmap's **Trello import** entry stays — it is a different feature and remains deferred.
- **CLAUDE.md:** the launch-paths `--uitest` bullet gains `--export-to`, `--import-from`, and `--import-mode` (none of the three are currently documented there); a new Pitfalls entry **only if** the spike fails or the real-app ⌘Z check diverges from the headless spike (the M7 precedent).
- Update the `ExportJSONDocument.init(configuration:)` stub comment: E-02 shipped via URL-based `.fileImporter`; the `ReadConfiguration` path remains unused by design.
- New test files ⇒ `make gen` before building.

## Edge cases

- **Empty envelope** — decodes as valid (pinned by an existing export test); Add is a true no-op: `importBoards` returns early before opening the undo bracket and before any save, so it neither mutates nor eats a ⌘Z step, and preserves selection. Replace is unavailable (dialog omits the button; store throws `.emptyReplace` as the backstop, which is also what the hook publishes if a test forces the combination).
- **Duplicate board names after append** — legal (no model uniqueness); the sidebar renders duplicates fine. No test *appends* a fixture's export into a store still containing that fixture, so duplicate board-name identifiers never coexist on screen (the Replace and Cancel legs import the standard fixture's own export into itself, but replace deletes the originals in the same save and cancel never imports).
- **Fractional-second timestamps** (hand-edited/third-party files) — hard-reject as `.unreadable`; our exporter never emits them. A lenient date strategy is a contained future change inside `decodeForImport`.
- **Unknown label / theme / hex garbage** — sanitized per the locked decision; the palette invariant (exactly 8 `CardLabel` rows) is asserted in every store-level test.
- **Save failure mid-import** — single-save + rollback means on-disk state is provably pre-import; alert states the unchanged guarantee.
- **`--import-from` under a launch order where the window undo manager isn't wired yet** — `context.undoManager` may be nil, so the inline bracket degrades to a plain run; harmless for e2e determinism, and it means **the e2e never exercises the undo path** — that is exactly what the spike suite and the manual ⌘Z check cover.
- **Security-scoped read from unusual volumes** — the read proceeds regardless of `startAccessing…`'s Bool; exercised once manually with a file on an external/iCloud location.

## Testing

**Spike first (blocking, step 1):** `ImportUndoOnDiskTests` — an **on-disk** store (`ModelConfiguration(url:)` under a temp dir; in-memory provably cannot reproduce the Board-delete assert), `UndoManager(groupsByEvent = false)` attached, labels seeded, store **pre-seeded with existing data via store ops and saved**. Two separate tests, because interleaving bare saves with undo/redo cannot "match app autosave" headlessly (with `groupsByEvent = false`, save-time registrations outside a group are exactly the documented hang; and any post-undo registration would clear the redo stack, corrupting the oracle):

1. **Undo/redo fidelity:** `importBoards` a 2-board envelope (lists, cards, labels, due dates) → undo → assert exactly the seeded state (boards, 8 labels) → redo → assert the **full graph including Card↔label re-attachment by identity** → undo again. No interleaved saves. **Silent wrong-state-after-redo counts as spike failure**, not just the crash — the `moveCard` broken-redo precedent proves crash-free redo can still corrupt.
2. **On-disk commit of the undone state:** import → undo → `context.save()` → assert only the seeded boards persist (fresh fetch). This is the assert-adjacent moment — committing the undo-driven cascade delete of Boards to disk — isolated in its own test so a failure here is unambiguous. No redo after the save (a post-undo save may legitimately invalidate redo; that is standard NSUndoManager behavior, not corruption).

Run isolated, foreground (`-only-testing`); >6 min = the documented hang, `EXC_BREAKPOINT` = the assert. **Before enacting the fallback, triage the FAULT line:** a registration thrown *outside* the import group (a headless-config artifact) means rework the spike, not the feature; a fault *inside* `importBoards`'s own group, the undo, the redo, or the post-undo save is a genuine failure → enact the fallback (detach pattern, PRD + CLAUDE.md updated, suite reduced to an on-disk materialize smoke). Pass → suite stays as the permanent on-disk undo regression.

**Spike outcome (2026-07-08): FAIL — the gate resolved one task early, in-memory.** During Task 1's TDD cycle, `appendIsOneUndoStep` crashed deterministically (3/3 identical runs) on `redo()`: SwiftData's automatic undo registration restored the Board and BoardList levels of the imported graph but **silently dropped every third-level Card** (the crash was an index into the resulting empty `sortedCards`; instrumented and confirmed as missing rows, not reordering). This is exactly the criterion the spike defines as failure — silent wrong-state-after-redo, the `moveCard` broken-redo precedent at one more level of nesting — observed in the in-memory harness, which is the *weaker* environment (the on-disk spike could only have failed harder; per `deleteBoard`'s evidence, in-memory never even reproduces the on-disk assert class). The on-disk undo/redo spike test is therefore moot and was not pursued; `ImportUndoOnDiskTests` ships as an on-disk materialize smoke instead. **Fallback enacted per the locked decision:** `importBoards` uses the `deleteBoard` detach discipline (manager detached for the span, reattached + `removeAllActions()` in a defer) — append import is **not undoable** and clears the undo stack, exactly like board delete; the empty-envelope early return is unchanged. §2's defer-closed-bracket design is superseded by this outcome. Consequences threaded through the rest of the feature: the mode dialog stays silent on undoability (already specced), the manual ship-gate ⌘Z check now asserts ⌘Z does *nothing* after an Add import, and PRD §4.6/§9 + a new CLAUDE.md pitfall document the contract (Task 9). Separately, Task 1 exposed a test-oracle bug worth remembering: `ObjectIdentifier` is not a stable identity oracle for SwiftData models across saves (instances are refaulted; PASS/FAIL varied run-to-run) — label-identity assertions use `persistentModelID`.

**Unit — `ImportDecodeTests`** (pure, no container): happy round trip modulo sanitization; malformed JSON / missing required key / missing `formatVersion` → `.unreadable`; versions 0 and 2 → `.unsupportedVersion`; fractional-second date → `.unreadable`; label filter/dedupe/reorder table; due-date normalization with a pinned-time-zone calendar (both `includesTime` values); hex canonicalization; empty-boards decodes; sanitize idempotence.

**Unit — `BoardStoreImportTests`** (`TestContainer(withUndo: true)`, in-memory): append-into-empty materializes the exact graph with labels attached **by identity** to pre-fetched palette rows and `CardLabel` count staying 8; append-after-existing-max (existing positions `[0,5]` → imported get 6,7; existing untouched); scrambled DTO positions materialize as array order; append is one undo step (undo → pre-import count, redo → full graph); replace deletes existing, keeps palette; replace clears the undo stack (`canUndo == false && canRedo == false`); replace with empty envelope throws `.emptyReplace` and mutates nothing; **append with empty envelope is a no-op that registers no undo step** (`canUndo` unchanged); returned `[Board]` matches envelope order; **byte-equality round trip** — seed container A via store ops with content exercising **every format field** (two-plus boards, one with emoji + custom theme hex and one default; multiple lists including a collapsed one; cards with details, multiple labels, and due dates with `includesTime == false`), `makeEnvelope`→encode with fixed `exportedAt`→`decodeForImport`→import into fresh container B **whose 8-row palette is seeded first** (`ensureLabelsSeeded` — `TestContainer` does not seed it, and an unseeded B would silently drop every label), re-encode B with the same fixed `exportedAt`, assert **byte equality** (leaning on the encoder's documented determinism — the strongest cheap oracle).

**Unit — `AppLaunchConfigTests`:** `--import-from`/`--import-mode` parse rows (present, absent, trailing-flag nil).

**UI — `ImportUITests`:**
- Menu item exists and is **enabled on both `empty` and `standard` fixtures** (never clicks through — the panel is undriveable).
- **Canonical round trip:** launch(standard, exportTo:) → assert export marker → relaunch(empty, importFrom:) → assert `ok|Groceries,Work|Buy milk,…` marker, sidebar rows, post-import selection showing Groceries → `relaunchPreservingStore()` → boards persist (no-double-import by construction).
- **Replace leg:** launch(standard, exportTo:) → relaunch(standard, importFrom:, importMode: replace) → assert exactly 2 board rows (not 4) and Edit ▸ Undo disabled.
- **Error leg:** `--import-from does-not-exist.json` → marker `error|unreadable`, sidebar unchanged.
- **Dialog Cancel path:** launch(standard, exportTo:) → relaunch(standard, importFrom:, importMode: ask) → the real mode dialog presents → click Cancel via the existing `hittableButton` helper (built for confirmation dialogs) → assert the sidebar still shows exactly the two fixture boards and the marker reads `cancelled`. (Only the Cancel path; the panel itself stays manual.)
- Empty-state Import button presence on the `empty` fixture.

**Manual-gate outcome (2026-07-08): PASS, with two findings.** The user ran the full procedure against a fixture-seeded Debug build: real `NSOpenPanel` round trip, Add to Existing (correct 4-board sidebar, imported Groceries selected), ⌘Z/⇧⌘Z after Add correctly did **nothing** (no crash — the non-undoable contract from the spike fallback held in the real app), Replace All (destructive-styled dialog, exactly 2 boards after, Edit ▸ Undo disabled), and the mode dialog **presented promptly** after the panel closed (the main-queue hop suffices; whether it is strictly necessary was not probed further — it stays, cheap and defensive). Findings: (1) *procedure, not product* — an `open`-launched `--uitest` instance lands **windowless on this host**, leaving every board-dependent menu item disabled ("clicking Export does nothing"); verified via System Events that with a window present both panels present correctly (AX sheets "export"/"open" — the stacked `.fileExporter`/`.fileImporter` coexist fine); any manual procedure must include a ⌘N step after launch. (2) *product, fixed same-day* (commit `f817f7d`): Export/Import menu items looked enabled while a text editor had focus but their clicks were silently swallowed by `guardedMutation` — both items now also gray out on `textInputFocused` (see §3), pinned by `ImportUITests.testImportExportGrayOutWhileTyping`.

**Manual (ship gate, recorded here post-implementation like B-06's outcome section):** ~60-second procedure — open the built app with a fixture store, File ▸ Import a real exported JSON through the actual `NSOpenPanel`, Add to Existing, then ⌘Z and ⇧⌘Z (no crash, correct restore — guards the headless-pass/app-crash divergence, the M7 precedent); repeat once with Replace All confirming the destructive dialog and that ⌘Z does nothing after.

**Step order:** (1) spike suite → decide undo mode; (2) `ImportError` + `decodeForImport` + `ImportDecodeTests`; (3) store methods + `BoardStoreImportTests`; (4) UI wiring (FocusedValues, AppCommands, RootView, EmptyStateView); (5) launch hooks + marker + `AppLaunchConfigTests`; (6) `ImportUITests`; (7) manual verification; (8) doc sync. `make gen` after each new file; `make unit`/`make ui` foreground with the pkill preamble.

## Out of scope

- Format v2 / entity UUIDs / dedupe-aware merge (future; the version gate is the hook).
- Trello import (roadmap; a Trello→`ExportEnvelope` mapper would feed this same pipeline).
- Lenient date parsing for third-party-generated files.
- Progress UI for huge files (synchronous import is fine at this app's scale).
- Retrofitting the throwing-save/error-alert pattern onto existing store methods.
