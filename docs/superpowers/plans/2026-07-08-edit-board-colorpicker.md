# Edit Board Sheet + ColorPicker Well (M-A) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** One unified "Edit Board" sheet (name + emoji + description, create/edit parity), a new optional `Board.about` field carried through export/import with the codebase's first `formatVersion` bump (1 → 2) and a tolerant import gate, and a native ColorPicker well added to the ThemeButton popover.

**Architecture:** `Board.about: String?` is an additive optional — it ships inside `TackSchemaV1` (the `isCollapsed` precedent), no migration stage. The export format bumps to 2 per the maintainer's per-feature-bump policy; the import gate loosens from strict `== 1` to `1...current`, so v1 files still import (missing `about` decodes nil). `RenameBoardSheet` grows into `EditBoardSheet` (file rename → `make gen`); commits go through one new `BoardStore.editBoard` mutation = one undo group with per-field diffing (the `applyCardEdits` pattern). The ColorPicker cannot write hex directly — a new `NSColor→sRGB→HexColor` bridge (new file, unit-testable) feeds the existing `setTheme` path with a debounced commit; the hex field stays the XCUITest-drivable path and `board-theme-value` remains the outcome oracle.

**Tech Stack:** SwiftUI (macOS 14), SwiftData, XCUITest, Swift Testing, xcodegen.

## Global Constraints

- Every bare `xcodebuild` needs `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`; `pkill -f xcodebuild; pkill -f Tack.app` before every run; FOREGROUND runs; judge only by the log tail; every `TackUITests` invocation carries `-parallel-testing-enabled NO`.
- **After any file add/rename: `make gen`** (Tack.xcodeproj is generated).
- The new Board field is named **`about`** — NEVER `description` (NSObject collision on `@Model`; `Card.swift:8` precedent).
- `HexColor` in `BoardTheme.swift` stays **Foundation-only** — the Color/NSColor bridge lives in a separate file.
- Every new TextField/TextEditor must call `.reportsTextInputFocus()`.
- Every `BoardStore` mutation = exactly one `withUndoGroup`; `editBoard` must no-op (no undo group, no save) when nothing changed.
- Existing AX ids that survive: `board-name-field`, `board-emoji-field`, `create-board-confirm`, `theme-button`, `theme-swatch-<name>`, `theme-hex-field`, `board-theme-value`. Retired: `rename-board-field`, `rename-board-confirm` (replaced by `edit-board-*` ids — their UI test is reworked in the same task).
- ColorPicker: `supportsOpacity: false` is mandatory (storage is RRGGBB, no alpha).
- The environmental keyboard/menu UI-test failure mode is active on this host (control-confirmed on main). Keyboard/menu-gated suites are NOT gates for this plan; the gates are the unit suite + the mouse-driven suites this plan touches (BoardCRUD, Theme, Import/Export UI suites are mouse-driven).
- Commit style: short imperative summary, body optional, `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>` trailer.

---

### Task 0: `Board.about` + `createBoard(about:)` + `editBoard` mutation (unit TDD)

**Files:**
- Modify: `Tack/Models/Board.swift` (add stored property + init param)
- Modify: `Tack/Store/BoardStore.swift` (extend `createBoard`, add `editBoard`)
- Modify: `Tack/Store/FixtureSeeder.swift` (seed an `about` on Groceries)
- Test: `TackTests/BoardStoreBoardTests.swift`

**Interfaces:**
- Consumes: existing `withUndoGroup`, `TestContainer(withUndo:)` test helper (see how `BoardStoreBoardTests` constructs stores today — mirror it exactly).
- Produces: `Board.about: String?`; `createBoard(name:emoji:about: String? = nil)`; `func editBoard(_ board: Board, name: String, emoji: String?, about: String?)` — one "Edit Board" undo group, per-field diff, whole-call no-op when nothing changed. Task 2's sheet and Task 1's export both consume these exact signatures.

- [ ] **Step 1: Write the failing unit tests**

Add to `TackTests/BoardStoreBoardTests.swift` (mirror the file's existing test/store-construction style exactly — read it first):

```swift
    @Test func createBoardStoresAbout() throws {
        let (store, _) = try makeStore()
        let board = store.createBoard(name: "A", emoji: nil, about: "Weekly list")
        #expect(board.about == "Weekly list")
        let plain = store.createBoard(name: "B", emoji: nil)
        #expect(plain.about == nil)
    }

    @Test func editBoardUpdatesAllFields() throws {
        let (store, _) = try makeStore()
        let board = store.createBoard(name: "Old", emoji: "🛒", about: nil)
        store.editBoard(board, name: "New", emoji: "💼", about: "Notes")
        #expect(board.name == "New")
        #expect(board.emoji == "💼")
        #expect(board.about == "Notes")
    }

    @Test func editBoardClearsEmojiAndAbout() throws {
        let (store, _) = try makeStore()
        let board = store.createBoard(name: "A", emoji: "🛒", about: "x")
        store.editBoard(board, name: "A", emoji: nil, about: nil)
        #expect(board.emoji == nil)
        #expect(board.about == nil)
    }

    @Test func editBoardIsOneUndoStep() throws {
        let (store, undo) = try makeStoreWithUndo()
        let board = store.createBoard(name: "Old", emoji: "🛒", about: nil)
        store.editBoard(board, name: "New", emoji: "💼", about: "Notes")
        undo.undo()
        #expect(board.name == "Old")
        #expect(board.emoji == "🛒")
        #expect(board.about == nil)
        undo.redo()
        #expect(board.name == "New")
        #expect(board.emoji == "💼")
        #expect(board.about == "Notes")
    }

    @Test func editBoardNoOpRegistersNoUndo() throws {
        let (store, undo) = try makeStoreWithUndo()
        let board = store.createBoard(name: "A", emoji: "🛒", about: "x")
        undo.removeAllActions()
        store.editBoard(board, name: "A", emoji: "🛒", about: "x")
        #expect(!undo.canUndo)
    }
```

NOTE for the implementer: `makeStore()`/`makeStoreWithUndo()` stand for however this file actually constructs its store and undo manager — read the existing tests first and use the file's real helpers/patterns verbatim (CLAUDE.md: unit tests need `TestContainer(withUndo: true)` for undo tests; `groupsByEvent` is already handled there). Do not invent new helpers if equivalents exist.

- [ ] **Step 2: Run to verify failure**

```bash
pkill -f xcodebuild; pkill -f Tack.app
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild -project Tack.xcodeproj -scheme Tack \
  -destination "platform=macOS,arch=$(uname -m)" -derivedDataPath .build/DerivedData \
  -only-testing:TackTests/BoardStoreBoardTests test 2>&1 | tee .build/ma-task0-red.log
```
Expected: compile FAILURE (no `about` on Board / no `editBoard`) — for unit TDD in Swift, a compile error on the new API is the red state.

- [ ] **Step 3: Implement**

`Tack/Models/Board.swift` — add below `emoji` (keep property order: id, name, emoji, about, position, ...):

```swift
    /// Optional free-text purpose note ("what this board is for"). Named `about`,
    /// NOT `description` — that collides with NSObject on @Model classes (Card.details precedent).
    var about: String?
```

and add `about: String? = nil` to the init parameter list (after `emoji`), assigning `self.about = about`. The default keeps FixtureSeeder's direct `Board(...)` constructions (spike/large) compiling unchanged.

`Tack/Store/BoardStore.swift`:
- `createBoard(name:emoji:)` → `createBoard(name: String, emoji: String?, about: String? = nil)`; pass `about: about` into `Board(...)`.
- Add after `renameBoard`:

```swift
    /// Commits the Edit Board sheet in one undo step ("Edit Board"), diffing each field —
    /// a whole-call no-op opens no undo group and does not save (mirrors applyCardEdits).
    func editBoard(_ board: Board, name: String, emoji: String?, about: String?) {
        guard board.name != name || board.emoji != emoji || board.about != about else { return }
        withUndoGroup("Edit Board") {
            if board.name != name { board.name = name }
            if board.emoji != emoji { board.emoji = emoji }
            if board.about != about { board.about = about }
            save()
        }
    }
```

`Tack/Store/FixtureSeeder.swift` — in `seedGroceries`, change the createBoard call to:
```swift
        let board = store.createBoard(name: "Groceries", emoji: "🛒", about: "Weekly shopping run")
```
(keep the variable name the function actually uses — read it first). Leave "Work" without an about (the nil-collapsing display case).

- [ ] **Step 4: Run to verify pass**

Same command, log `.build/ma-task0-green.log`. Expected: `** TEST SUCCEEDED **`, all BoardStoreBoardTests (11 existing + 5 new) pass.

- [ ] **Step 5: Run the full unit suite** (schema-additive change can ripple)

`pkill -f xcodebuild; pkill -f Tack.app; make unit 2>&1 | tee .build/ma-task0-unit.log` — expected `** TEST SUCCEEDED **`. If `ExportDocumentTests.roundTripPreservesStructureAndValues` fails here, STOP — the DTO should not know about `about` yet; you touched too much.

- [ ] **Step 6: Commit**

```bash
git add Tack/Models/Board.swift Tack/Store/BoardStore.swift Tack/Store/FixtureSeeder.swift TackTests/BoardStoreBoardTests.swift
git commit -m "Board.about field + editBoard mutation (one undo step, per-field diff)

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 1: Export `about` + formatVersion 2 + tolerant import gate (unit TDD)

**Files:**
- Modify: `Tack/Export/ExportDocument.swift` (DTO field, mapping, version constant, gate, error copy)
- Modify: `Tack/Store/BoardStore.swift` (`materialize` threads `about`)
- Test: `TackTests/ExportDocumentTests.swift`, `TackTests/ImportDecodeTests.swift`, `TackTests/BoardStoreImportTests.swift`

**Interfaces:**
- Consumes: `Board.about` from Task 0.
- Produces: `ExportBoard.about: String?`; `ExportDocument.formatVersion == 2`; `decodeForImport` accepts any version in `1...formatVersion` and throws `.unsupportedVersion` outside it. Task 2's UI tests rely on export round-tripping `about`.

- [ ] **Step 1: Update the version-pinning tests + add new ones (the red set)**

In `TackTests/ExportDocumentTests.swift`:
- `formatVersionIsOne`: rename to `formatVersionIsTwo`, expectations `== 2` (both the envelope property and the decode round-trip).
- `emptyStoreExportsZeroBoards`: `#expect(decoded.formatVersion == 2)`.
- In `roundTripPreservesStructureAndValues`: add an assertion that the decoded Groceries board carries `about == "Weekly shopping run"` (the fixture value from Task 0) — read the test to see how it builds its store; if it builds boards inline rather than via the fixture, set `about` on one board inline and assert it round-trips.

In `TackTests/ImportDecodeTests.swift`:
- `versionGate`: change the loop to `[3, 0]` (2 is now valid; 3 is the unsupported future, 0 still invalid) with the same `.unsupportedVersion(version)` expectation.
- Add:

```swift
    @Test func v1FileStillImports() throws {
        // A version-1 file (no `about` keys) must decode under the tolerant gate with about == nil.
        let data = json(formatVersion: 1, boards: [boardJSON(name: "Legacy")])
        let envelope = try ExportDocument.decodeForImport(data)
        #expect(envelope.formatVersion == 1)
        #expect(envelope.boards.first?.about == nil)
    }
```
(Adapt `json(...)`/`boardJSON(...)` to the helpers' real signatures — read them first; the file's helper already defaults `formatVersion: 1`.)

In `TackTests/BoardStoreImportTests.swift`:
- `sampleEnvelope` builds `ExportBoard(...)` — add `about: "Imported note"` to one board and extend whatever materialize-verification test checks board fields to assert the materialized `Board.about == "Imported note"`. Envelope literals stay `formatVersion: 1` where they exist (they now exercise the v1-compat path — that is a feature, note it in a comment at one site: `// deliberately v1: exercises the tolerant gate`); `byteEqualityRoundTrip` re-exports at the CURRENT version, so if it compares against a v1 fixture it must be updated to build its input via `ExportDocument.export` (read it first — if it already round-trips export→import→export of the same store, it needs no version change, only the about field flowing through).

- [ ] **Step 2: Run to verify failure**

```bash
pkill -f xcodebuild; pkill -f Tack.app
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild -project Tack.xcodeproj -scheme Tack \
  -destination "platform=macOS,arch=$(uname -m)" -derivedDataPath .build/DerivedData \
  -only-testing:TackTests/ExportDocumentTests -only-testing:TackTests/ImportDecodeTests -only-testing:TackTests/BoardStoreImportTests test 2>&1 | tee .build/ma-task1-red.log
```
Expected: compile failure on `ExportBoard.about` + assertion failures on `formatVersion == 2`.

- [ ] **Step 3: Implement in `Tack/Export/ExportDocument.swift`**

- `ExportBoard`: add `var about: String?` after `emoji`.
- `exportBoard(_:)`: add `about: board.about,` after the emoji line.
- `formatVersion`: `static let formatVersion = 2` — extend the doc comment: `/// v2 (M-A): + ExportBoard.about. The import gate accepts 1...formatVersion; older files decode missing fields as nil.`
- Gate in `decodeForImport`:

```swift
        guard (1...formatVersion).contains(envelope.formatVersion) else {
            throw ImportError.unsupportedVersion(envelope.formatVersion)
        }
```
- `ImportError.unsupportedVersion` message: `"This file uses export format version \(version). This version of Tack can import versions 1 through \(ExportDocument.formatVersion)."`

And in `Tack/Store/BoardStore.swift` `materialize`, thread the field into the Board construction: `about: exportBoard.about,` (after the emoji line).

- [ ] **Step 4: Run to verify pass** — same command, log `.build/ma-task1-green.log`. Expected `** TEST SUCCEEDED **`.

- [ ] **Step 5: Full unit suite** — `make unit`, log `.build/ma-task1-unit.log`, expected `** TEST SUCCEEDED **`.

- [ ] **Step 6: Commit**

```bash
git add Tack/Export/ExportDocument.swift Tack/Store/BoardStore.swift TackTests/ExportDocumentTests.swift TackTests/ImportDecodeTests.swift TackTests/BoardStoreImportTests.swift
git commit -m "Export formatVersion 2: Board.about in the envelope, tolerant 1...current import gate

First version bump. v1 files still import (about decodes nil); files from
newer versions are rejected with an updated error message.

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 2: EditBoardSheet + create/edit parity + header subtitle (UI TDD)

**Files:**
- Rename: `Tack/Views/Sidebar/RenameBoardSheet.swift` → `Tack/Views/Sidebar/EditBoardSheet.swift` (then `make gen`)
- Modify: `Tack/Views/Sidebar/CreateBoardSheet.swift`, `Tack/Views/Sidebar/SidebarView.swift`, `Tack/Views/Board/BoardView.swift`, `Tack/Support/AccessibilityID.swift`
- Test: `TackUITests/BoardCRUDUITests.swift`

**Interfaces:**
- Consumes: `store.editBoard(_:name:emoji:about:)` and `createBoard(name:emoji:about:)` from Task 0.
- Produces: AX ids `edit-board-name-field`, `edit-board-emoji-field`, `edit-board-about-field`, `edit-board-confirm`, `board-about-field` (create sheet), `board-about-subtitle` (header). Context-menu literal becomes `"Edit Board…"`.

- [ ] **Step 1: Rework/extend the UI tests (red set)**

In `TackUITests/BoardCRUDUITests.swift`:

1. Rework `testRenameBoard` → `testEditBoardRenames`: same flow, but `contextMenuItem("Edit Board…")`, field id `edit-board-name-field`, confirm id `edit-board-confirm` (update the file's element lookups — read them first; `renameBoardField`/`renameBoardConfirm` lookups are replaced, not duplicated).
2. Add:

```swift
    /// M-A: the edit sheet edits emoji and about; clearing the emoji falls back to 🗂️ in the row.
    func testEditBoardEmojiAndAbout() {
        launch(fixture: "standard")

        boardRow("Work").rightClick()
        contextMenuItem("Edit Board…").click()
        let emojiField = element(AccessibilityID.editBoardEmojiField)
        XCTAssertTrue(emojiField.waitForExistence(timeout: timeout))
        XCTAssertEqual(emojiField.value as? String, "💼", "edit sheet should seed the current emoji")

        emojiField.click()
        selectAllAndDelete(emojiField)
        let aboutField = element(AccessibilityID.editBoardAboutField)
        aboutField.click()
        aboutField.typeText("Client projects")
        element(AccessibilityID.editBoardConfirm).click()

        // Emoji cleared → 🗂️ fallback in the sidebar row's combined text.
        XCTAssertTrue(poll(timeout: timeout) { self.boardRow("Work").exists })
        // Reopen: fields reflect committed values.
        boardRow("Work").rightClick()
        contextMenuItem("Edit Board…").click()
        XCTAssertEqual(element(AccessibilityID.editBoardEmojiField).value as? String, "",
                       "cleared emoji should reopen empty")
        XCTAssertEqual(element(AccessibilityID.editBoardAboutField).value as? String, "Client projects")
        app.typeKey(.escape, modifierFlags: [])
    }

    /// M-A: about shows as a subtitle under the board header, nil-collapsing.
    func testAboutSubtitleShowsWhenSet() {
        launch(fixture: "standard")

        // Groceries has a fixture about; Work does not.
        board("Groceries").click()
        let subtitle = element(AccessibilityID.boardAboutSubtitle)
        XCTAssertTrue(subtitle.waitForExistence(timeout: timeout),
                      "Groceries should show its about subtitle")
        board("Work").click()
        XCTAssertTrue(poll(timeout: timeout) { !subtitle.exists },
                      "Work has no about — subtitle must fully collapse")
    }
```

3. In `testCreateBoard`, after typing the emoji, add: type into `element(AccessibilityID.boardAboutField)` the text `"Launch prep"`, and after confirm assert the subtitle exists (`AccessibilityID.boardAboutSubtitle`).

Adapt helper names (`boardRow`, `contextMenuItem`, `element`, `selectAllAndDelete`, `poll`, `timeout`) to what the file actually defines — read it first; if `selectAllAndDelete` takes no argument (acts on focused field), call it accordingly.

- [ ] **Step 2: Run the red set**

```bash
pkill -f xcodebuild; pkill -f Tack.app
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild -project Tack.xcodeproj -scheme Tack \
  -destination "platform=macOS,arch=$(uname -m)" -derivedDataPath .build/DerivedData \
  -only-testing:TackUITests/BoardCRUDUITests -parallel-testing-enabled NO test 2>&1 | tee .build/ma-task2-red.log
```
Expected: compile failure on the new AccessibilityID names — that is the red gate for this step (the ids don't exist yet).

- [ ] **Step 3: Implement**

`Tack/Support/AccessibilityID.swift` — in the M3 board section, replace the two rename ids and add (following the file's kebab-case convention and doc-comment style):

```swift
    static let editBoardNameField = "edit-board-name-field"
    static let editBoardEmojiField = "edit-board-emoji-field"
    static let editBoardAboutField = "edit-board-about-field"
    static let editBoardConfirm = "edit-board-confirm"
    static let boardAboutField = "board-about-field"
    static let boardAboutSubtitle = "board-about-subtitle"
```

`git mv Tack/Views/Sidebar/RenameBoardSheet.swift Tack/Views/Sidebar/EditBoardSheet.swift`, then rewrite it:

```swift
import SwiftUI

/// The unified board-edit sheet (M-A): name + emoji + about, opened from the sidebar row's
/// context menu. Grew out of RenameBoardSheet; commits everything through ONE
/// `store.editBoard` call = one "Edit Board" undo step.
struct EditBoardSheet: View {
    let board: Board
    let store: BoardStore

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var emoji: String
    @State private var about: String

    init(board: Board, store: BoardStore) {
        self.board = board
        self.store = store
        _name = State(initialValue: board.name)
        _emoji = State(initialValue: board.emoji ?? "")
        _about = State(initialValue: board.about ?? "")
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Edit Board")
                .font(.headline)

            TextField("Board name", text: $name)
                .textFieldStyle(.roundedBorder)
                .reportsTextInputFocus()
                .accessibilityIdentifier(AccessibilityID.editBoardNameField)

            TextField("Emoji (optional)", text: $emoji)
                .textFieldStyle(.roundedBorder)
                .reportsTextInputFocus()
                .accessibilityIdentifier(AccessibilityID.editBoardEmojiField)
                .onChange(of: emoji) { _, newValue in
                    // Keep the LAST grapheme: a picked/typed replacement wins over the old
                    // emoji (prefix(1) silently discarded palette insertions — M-A fix).
                    if newValue.count > 1 {
                        emoji = String(newValue.suffix(1))
                    }
                }

            TextField("About (optional)", text: $about)
                .textFieldStyle(.roundedBorder)
                .reportsTextInputFocus()
                .accessibilityIdentifier(AccessibilityID.editBoardAboutField)

            HStack {
                Spacer()
                // Esc must cancel any sheet (HIG) — same one-liner as CreateBoardSheet.
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    let trimmedAbout = about.trimmingCharacters(in: .whitespacesAndNewlines)
                    store.editBoard(board,
                                    name: trimmedName,
                                    emoji: emoji.isEmpty ? nil : emoji,
                                    about: trimmedAbout.isEmpty ? nil : trimmedAbout)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(trimmedName.isEmpty)
                .accessibilityIdentifier(AccessibilityID.editBoardConfirm)
            }
        }
        .padding(20)
        .frame(width: 320)
    }
}
```

`Tack/Views/Sidebar/SidebarView.swift`: context-menu literal `"Rename…"` → `"Edit Board…"`; rename the state var `renamingBoard` → `editingBoard` (both the declaration and the `.sheet(item:)`); the sheet body becomes `EditBoardSheet(board: board, store: store)`.

`Tack/Views/Sidebar/CreateBoardSheet.swift`: add an `about` `@State = ""` and, below the emoji field, an About field identical in shape to the edit sheet's (`.reportsTextInputFocus()`, id `AccessibilityID.boardAboutField`, placeholder `"About (optional)"`); change the emoji clamp from `prefix(1)` to `suffix(1)` with the same comment as the edit sheet; Create button passes `about: {trimmed-empty→nil}` using the same trimming expression as the edit sheet.

`Tack/Views/Board/BoardView.swift` header: inside the existing header layout, wrap the current emoji+name HStack plus a new conditional subtitle in a `VStack(alignment: .leading, spacing: 2)`, keeping the `.combine`/`boardDetail` structure intact on the SAME element it is on today (the subtitle joins the combined element — its text is additive, and existing tests assert `contains`, not equality). The subtitle:

```swift
                if let about = board.about, !about.isEmpty {
                    Text(about)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .accessibilityIdentifier(AccessibilityID.boardAboutSubtitle)
                }
```

CAUTION (pitfall): the header must stay a `.combine` accessibility LEAF — attach the subtitle id INSIDE the combined block only if XCUITest can still resolve it; if the `.combine` swallows the child id (likely — combine collapses children), instead place the subtitle OUTSIDE the combined emoji+name element, as a sibling row in the header VStack, with its own id. Verify with the red/green cycle; the sibling arrangement is the safe default — use it.

Then `make gen` (file rename) and build once: `make build 2>&1 | tee .build/ma-task2-build.log` (expected `** BUILD SUCCEEDED **`).

- [ ] **Step 4: Run the green set** — same command as Step 2, log `.build/ma-task2-green.log`. Expected `** TEST SUCCEEDED **` for the full BoardCRUDUITests suite EXCEPT `testUndoAfterCreateBoardDoesNotCrash`, which is keyboard-gated (⌘Z) and environmentally red on this host — if it is the ONLY failure, treat the run as green for this task and note it.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "Edit Board sheet: name + emoji + about, create/edit parity, header subtitle

RenameBoardSheet grows into EditBoardSheet (one editBoard undo step,
last-grapheme emoji clamp both sheets). Board header shows a
nil-collapsing about subtitle. Rename-era AX ids retired.

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 3: Color→hex bridge + ColorPicker well in ThemeButton

**Files:**
- Create: `Tack/Views/Components/ColorHexBridge.swift` (then `make gen`)
- Modify: `Tack/Views/Board/ThemeButton.swift`, `Tack/Support/AccessibilityID.swift`
- Test: `TackTests/ColorHexBridgeTests.swift` (new; then `make gen`), `TackUITests/ThemeUITests.swift`

**Interfaces:**
- Consumes: `HexColor.parse/format` (Foundation-only — stays untouched), `store.setTheme(_:themeName:customHex:)`, `ThemeResolution.resolve`.
- Produces: `ColorHexBridge.hexString(from: Color) -> String?`; AX id `theme-color-well`.

- [ ] **Step 1: Write the failing bridge unit tests**

Create `TackTests/ColorHexBridgeTests.swift`:

```swift
import Testing
import SwiftUI
@testable import Tack

/// The Color→sRGB→RRGGBB bridge feeding the ThemeButton ColorPicker well (M-A).
/// HexColor itself stays Foundation-only; this bridge owns the AppKit conversion.
struct ColorHexBridgeTests {
    @Test func convertsSRGBPrimaries() {
        #expect(ColorHexBridge.hexString(from: Color(red: 1, green: 0, blue: 0)) == "FF0000")
        #expect(ColorHexBridge.hexString(from: Color(red: 0, green: 1, blue: 0)) == "00FF00")
        #expect(ColorHexBridge.hexString(from: Color(red: 0, green: 0, blue: 1)) == "0000FF")
        #expect(ColorHexBridge.hexString(from: Color(red: 0, green: 0, blue: 0)) == "000000")
        #expect(ColorHexBridge.hexString(from: Color(red: 1, green: 1, blue: 1)) == "FFFFFF")
    }

    @Test func roundTripsThroughHexColor() {
        let hex = "3A5F8F"
        let parsed = HexColor.parse(hex)!
        let color = Color(red: parsed.r, green: parsed.g, blue: parsed.b)
        #expect(ColorHexBridge.hexString(from: color) == hex)
    }

    @Test func alphaIsIgnored() {
        // supportsOpacity(false) is belt; this is suspenders — alpha never reaches storage.
        let color = Color(red: 1, green: 0, blue: 0, opacity: 0.4)
        #expect(ColorHexBridge.hexString(from: color) == "FF0000")
    }

    @Test func wideGamutClampsIntoSRGB() {
        // A P3 red outside sRGB must clamp to a valid RRGGBB, not fail.
        let p3 = Color(.displayP3, red: 1, green: 0, blue: 0, opacity: 1)
        let hex = ColorHexBridge.hexString(from: p3)
        #expect(hex != nil)
        #expect(HexColor.parse(hex!) != nil)
    }
}
```

- [ ] **Step 2: Run to verify failure** — `-only-testing:TackTests/ColorHexBridgeTests` (compile failure: no ColorHexBridge). NOTE: creating the test file requires `make gen` FIRST or the target won't see it — run `make gen`, then the test command; log `.build/ma-task3-red.log`.

- [ ] **Step 3: Implement the bridge**

Create `Tack/Views/Components/ColorHexBridge.swift`:

```swift
import SwiftUI
import AppKit

/// SwiftUI `Color` → canonical "RRGGBB" (sRGB, alpha dropped). Deliberately separate from
/// `HexColor` (Foundation-only for unit-testability): this side owns the AppKit conversion.
/// Returns nil when the color has no sRGB representation (some catalog/dynamic colors).
/// Out-of-gamut components clamp into 0...1 — a P3 pick lands on the nearest sRGB value,
/// so reopening the picker can show a slightly different color than was picked.
enum ColorHexBridge {
    static func hexString(from color: Color) -> String? {
        guard let srgb = NSColor(color).usingColorSpace(.sRGB) else { return nil }
        let r = min(max(srgb.redComponent, 0), 1)
        let g = min(max(srgb.greenComponent, 0), 1)
        let b = min(max(srgb.blueComponent, 0), 1)
        return HexColor.format(r: r, g: g, b: b)
    }
}
```

Run `make gen`, then the bridge tests: expected `** TEST SUCCEEDED **`, log `.build/ma-task3-bridge-green.log`.

- [ ] **Step 4: Add the well to ThemeButton (staged, debounced commit)**

`Tack/Support/AccessibilityID.swift` — add to the M8 theme section: `static let themeColorWell = "theme-color-well"`.

`Tack/Views/Board/ThemeButton.swift`:
- Update the doc comment at the top: replace the "deliberately skipped" ColorPicker sentence with: `/// M-A added the native ColorPicker well. The hex field remains the XCUITest-drivable path (NSColorPanel cannot be driven synthetically); the well's commits are verified through the board-theme-value marker + unit-tested ColorHexBridge.`
- Add state: `@State private var pickerColor: Color = .white` and `@State private var pendingPickerCommit: Task<Void, Never>?`.
- Seed on popover open (where `hexDraft` is seeded): set `pickerColor` from the board's resolved background — if `ThemeResolution.resolve(themeName: board.themeName, customHex: board.customThemeHex)` yields `.custom(let c)` use `c`; for `.preset` use the preset's `swatchColor`.
- In `customHexSection`, add ABOVE the hex TextField:

```swift
            ColorPicker("Custom color", selection: $pickerColor, supportsOpacity: false)
                .accessibilityIdentifier(AccessibilityID.themeColorWell)
                .onChange(of: pickerColor) { _, newColor in
                    guard let hex = ColorHexBridge.hexString(from: newColor) else { return }
                    guard hex != board.customThemeHex else { return }
                    hexDraft = hex
                    showsHexError = false
                    // NSColorPanel has no "done" event and its wheel fires continuously;
                    // debounce so a drag settles into ONE setTheme = one undo step.
                    pendingPickerCommit?.cancel()
                    pendingPickerCommit = Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(400))
                        guard !Task.isCancelled else { return }
                        store.setTheme(board, themeName: board.themeName, customHex: hex)
                    }
                }
```
(If `board` is not in scope in that section, pass it through the same way `customHexSection(for:)` already receives it — read the file first and follow its existing parameterization.)

- [ ] **Step 5: Extend ThemeUITests + run the theme gates**

In `TackUITests/ThemeUITests.swift`, inside `testCustomHexTheme` right after the popover opens, add:

```swift
        XCTAssertTrue(element(AccessibilityID.themeColorWell).exists,
                      "the native color well should sit in the Custom section")
```
(Adapt to the file's element-lookup helper — read it first.)

Run:
```bash
pkill -f xcodebuild; pkill -f Tack.app
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild -project Tack.xcodeproj -scheme Tack \
  -destination "platform=macOS,arch=$(uname -m)" -derivedDataPath .build/DerivedData \
  -only-testing:TackUITests/ThemeUITests -only-testing:TackTests/ColorHexBridgeTests -only-testing:TackTests/BoardThemeTests \
  -parallel-testing-enabled NO test 2>&1 | tee .build/ma-task3-green.log
```
Expected: `** TEST SUCCEEDED **` (3 UI + bridge + theme unit suites).

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "ThemeButton: native ColorPicker well via new ColorHexBridge

sRGB-clamped, alpha-locked (supportsOpacity false + bridge drop), debounced
into single setTheme commits. Hex field stays the automated test path;
panel interaction is human-verified (B-06 precedent).

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 4: Milestone gate

**Files:** none (verification only).

- [ ] **Step 1:** `make unit` → `** TEST SUCCEEDED **` (log `.build/ma-gate-unit.log`).
- [ ] **Step 2:** Mouse-driven UI suites this milestone touched:

```bash
pkill -f xcodebuild; pkill -f Tack.app
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild -project Tack.xcodeproj -scheme Tack \
  -destination "platform=macOS,arch=$(uname -m)" -derivedDataPath .build/DerivedData \
  -only-testing:TackUITests/BoardCRUDUITests -only-testing:TackUITests/ThemeUITests \
  -only-testing:TackUITests/ImportUITests -only-testing:TackUITests/ExportUITests \
  -only-testing:TackUITests/PersistenceUITests \
  -parallel-testing-enabled NO test 2>&1 | tee .build/ma-gate-ui.log
```
Expected: green EXCEPT the documented environmentally-failing keyboard/menu-gated tests (`testUndoAfterCreateBoardDoesNotCrash`, `testExportMenuItemExistsAndEnabled`, `testImportMenuItemExistsAndEnabledOnBothFixtures`, and PersistenceUITests' keyboard-gated one if present). Each failure must be one of the environmentally-failing set from `.build/m0-gate-ui.log`; any NEW failing test = real regression, fix before proceeding.

- [ ] **Step 3: Human checklist (hand to Ty, accumulate with M-0's)**
1. Edit Board…: open from a board's context menu — name/emoji/about seed correctly, clearing emoji falls back to 🗂️, Esc cancels, one ⌘Z reverts the whole edit.
2. ColorPicker well: open theme popover → click the well (popover will close — expected, NSColorPanel takes key); drag around the wheel; confirm the board wash updates once settled, the hex field shows the picked hex on reopen, and ONE ⌘Z reverts it. Pick near-white and near-black — confirm the wash is (expectedly) subtle and nothing looks broken.
3. Confirm typing in the NSColorPanel's own hex field does NOT trigger Tack menu shortcuts (the panel is neither a Tack text field nor a sheet — this is the unverified focus-gating question from the review).
