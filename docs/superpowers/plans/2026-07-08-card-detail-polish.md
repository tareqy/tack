# Card Detail Polish (M-0) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Polish the card-detail sheet — retitle "Description" to "Brief", make long Brief text scroll inside the editor instead of scrolling the whole sheet, make the sheet user-resizable (min 460×560), and turn the label picker into color-circle-only chips — plus add fast test-iteration Makefile targets.

**Architecture:** All four product changes are view-layer only (`Tack/Views/CardDetail/`), no model/store/schema/export changes. The whole-sheet-scroll bug is structural: a `ScrollView` wraps the entire content column while the `TextEditor` has an unbounded height — the fix removes the outer `ScrollView` and makes the editor the flexible element (TextEditor scrolls its own content natively when its frame is bounded). Resizability = swapping the fixed `.frame(width:height:)` for a min/ideal/max frame (macOS sheets become resizable when content sizing is flexible). Circle chips = a new private swatch view inside `LabelPicker`; the shared `LabelChipLabel` stays untouched because `LabelFilterBar` keeps its current look.

**Tech Stack:** SwiftUI (macOS 14), XCUITest, xcodegen/Make.

## Global Constraints

- Every bare `xcodebuild` needs `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` (xcode-select points at CLT only).
- Before every xcodebuild run: `pkill -f xcodebuild; pkill -f Tack.app`. Run in the **foreground**, `tee` to a log under `.build/`, and judge the run **only by the log tail** (`** TEST SUCCEEDED **` / `** TEST FAILED **`) — `tee` masks the exit code.
- Every `TackUITests` invocation MUST carry `-parallel-testing-enabled NO`.
- **Never** add `.scrollContentBackground(.hidden)` to the macOS `TextEditor` (makes it AX-Disabled under XCUITest). Decorative overlays over the editor must keep `.allowsHitTesting(false)`. Both are pinned by `testEditDescriptionSavesAndPersists`.
- Accessibility identifiers must NOT change: `detail-description-field`, `label-chip-<color>`, `card-detail`, `detail-title-field`.
- `Card.details` (model) and the export JSON key `details` must NOT be renamed — "Brief" is a UI label only.
- `LabelFilterBar` and `LabelChipLabel` keep their current *behavior and look* (doc-comment update only).
- No new source files are created → **no `make gen` needed** anywhere in this plan.
- Commit messages: repo style (short imperative summary line, no conventional-commit prefix), ending with `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`.
- **Environmental caveat:** the latest result bundle shows the documented host failure mode — every `KeyboardShortcutUITests`/`LabelFilterUITests` test failing deterministically (CLAUDE.md "second environmental mode"). Those suites are NOT gates for this plan. If a full `make ui` is attempted and they fail, control-run one of them against committed code before debugging; a fresh login session is the recovery path.

---

### Task 0: Makefile fast-iteration targets (`build-tests` / `*-nobuild`)

**Files:**
- Modify: `Makefile`

**Interfaces:**
- Consumes: nothing.
- Produces: `make build-tests` (one-time compile of app + both test bundles), `make unit-nobuild`, `make ui-nobuild` (re-run tests against the already-built products). Later tasks may use these for repeat runs; single-test invocations keep using bare `xcodebuild`.

Rationale (from the measured investigation): a green UI run is ~20–25 min of which ~70–80 % is fixed app-launch overhead — not reducible per launch. The cheap, zero-risk win is removing the redundant build/dependency-analysis phase when re-running tests against an unchanged build (flake retries, environmental control runs, repeated single-test iteration).

- [ ] **Step 1: Add the targets**

Replace the `.PHONY` line and append the three targets, so the full `Makefile` reads:

```make
# xcode-select on this machine points at Command Line Tools; xcodebuild needs full Xcode
export DEVELOPER_DIR ?= /Applications/Xcode.app/Contents/Developer

ARCH := $(shell uname -m)
DEST := platform=macOS,arch=$(ARCH)

.PHONY: gen build unit ui test build-tests unit-nobuild ui-nobuild

gen:
	xcodegen generate

build:
	xcodebuild -project Tack.xcodeproj -scheme Tack -destination '$(DEST)' -derivedDataPath .build/DerivedData build

unit:
	xcodebuild -project Tack.xcodeproj -scheme Tack -destination '$(DEST)' -derivedDataPath .build/DerivedData -only-testing:TackTests test

ui:
	xcodebuild -project Tack.xcodeproj -scheme Tack -destination '$(DEST)' -derivedDataPath .build/DerivedData -only-testing:TackUITests -parallel-testing-enabled NO -resultBundlePath .build/results/ui-$$(date +%s).xcresult test

test: unit ui

# Compile app + both test bundles ONCE; then iterate with the *-nobuild targets below.
# After ANY source change (app or tests), run build-tests again — test-without-building
# runs whatever was last compiled.
build-tests:
	xcodebuild -project Tack.xcodeproj -scheme Tack -destination '$(DEST)' -derivedDataPath .build/DerivedData build-for-testing

unit-nobuild:
	xcodebuild -project Tack.xcodeproj -scheme Tack -destination '$(DEST)' -derivedDataPath .build/DerivedData -only-testing:TackTests test-without-building

ui-nobuild:
	xcodebuild -project Tack.xcodeproj -scheme Tack -destination '$(DEST)' -derivedDataPath .build/DerivedData -only-testing:TackUITests -parallel-testing-enabled NO -resultBundlePath .build/results/ui-$$(date +%s).xcresult test-without-building
```

- [ ] **Step 2: Verify build-tests compiles**

Run: `pkill -f xcodebuild; pkill -f Tack.app; make build-tests 2>&1 | tee .build/m0-task0-build.log`
Expected: log ends with `** TEST BUILD SUCCEEDED **`.

- [ ] **Step 3: Verify test-without-building runs**

Run: `pkill -f xcodebuild; pkill -f Tack.app; make unit-nobuild 2>&1 | tee .build/m0-task0-unit.log`
Expected: log ends with `** TEST SUCCEEDED **` and shows NO compile steps for app sources.

- [ ] **Step 4: Commit**

```bash
git add Makefile
git commit -m "Makefile: build-tests + *-nobuild targets for fast test re-runs

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 1: Retitle the Description section to "Brief"

**Files:**
- Modify: `Tack/Views/CardDetail/CardDetailView.swift` (line ~48, the `Text("Description")` literal — the ONLY user-facing "Description" in the app)
- Test: `TackUITests/CardDetailUITests.swift` (extend `testOpenDetailViaDoubleClickBody`)

**Interfaces:**
- Consumes: `detailSheet` helper (`CardDetailUITests.swift:255`).
- Produces: nothing consumed later — the a11y id `detail-description-field` and the model field `details` are unchanged by design.

- [ ] **Step 1: Write the failing assertion**

In `TackUITests/CardDetailUITests.swift`, inside `testOpenDetailViaDoubleClickBody`, after the `titleField` value assertion (line ~23) and before the `app.typeKey(.escape, ...)`, add:

```swift
        XCTAssertTrue(detailSheet.staticTexts["Brief"].exists,
                      "description section should be titled Brief")
        XCTAssertFalse(detailSheet.staticTexts["Description"].exists,
                      "the old Description section title must be gone")
```

- [ ] **Step 2: Run the test to verify it fails**

Run:
```bash
pkill -f xcodebuild; pkill -f Tack.app
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild -project Tack.xcodeproj -scheme Tack \
  -destination "platform=macOS,arch=$(uname -m)" -derivedDataPath .build/DerivedData \
  -only-testing:TackUITests/CardDetailUITests/testOpenDetailViaDoubleClickBody \
  -parallel-testing-enabled NO test 2>&1 | tee .build/m0-task1-red.log
```
Expected: `** TEST FAILED **` with the "should be titled Brief" assertion message.

- [ ] **Step 3: Rename the label**

In `Tack/Views/CardDetail/CardDetailView.swift`, change exactly one literal:

```swift
                        Text("Brief")
                            .font(.caption)
                            .foregroundStyle(.secondary)
```

(was `Text("Description")`). Touch nothing else — not the a11y identifier, not the `$details` binding, not the pitfall comments.

- [ ] **Step 4: Run the test to verify it passes**

Same command as Step 2, log to `.build/m0-task1-green.log`.
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add Tack/Views/CardDetail/CardDetailView.swift TackUITests/CardDetailUITests.swift
git commit -m "Card detail: retitle Description section to Brief (UI label only)

Model field stays Card.details and the export key stays \"details\" —
renaming either would be a breaking change for no user-visible gain.

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 2: Long Brief text scrolls inside the editor, not the sheet

**Files:**
- Modify: `Tack/Views/CardDetail/CardDetailView.swift` (the `body` skeleton: remove the outer `ScrollView`, bound the `TextEditor`)
- Test: `TackUITests/CardDetailUITests.swift` (new test)

**Interfaces:**
- Consumes: `AccessibilityID.cardDetailDescriptionField` (`"detail-description-field"`), `AccessibilityID.dueQuickToday` (the Today quick button — a stable element *below* the editor, used as the visibility oracle).
- Produces: the no-outer-ScrollView layout that Task 3's flexible frame relies on (the editor absorbs extra height when the sheet grows).

Current structure (the bug): `ScrollView` wraps the whole content column (Title + Brief + Labels + DueDate) and the `TextEditor` has `.frame(minHeight: 120)` with no upper bound — long text grows the editor unboundedly and the *sheet content* scrolls, pushing Labels/Due Date off-screen.

- [ ] **Step 1: Write the failing test**

Add to `TackUITests/CardDetailUITests.swift` (after `testEditDescriptionSavesAndPersists`):

```swift
    /// M-0: long Brief text must scroll INSIDE the editor. Oracle: the due-date quick buttons
    /// sit below the editor in the sheet — if the sheet-wide scroll bug regresses, the growing
    /// editor pushes them off-screen and `isHittable` goes false.
    func testLongBriefScrollsInsideEditorNotSheet() {
        launch(fixture: "standard")

        openDetailViaBodyDoubleClick("Call plumber")
        let brief = element(AccessibilityID.cardDetailDescriptionField)
        XCTAssertTrue(brief.waitForExistence(timeout: timeout))
        brief.click()
        let longText = Array(repeating: "brief line", count: 40).joined(separator: "\n")
        brief.typeText(longText)

        let today = element(AccessibilityID.dueQuickToday)
        XCTAssertTrue(today.exists, "due-date quick buttons should exist below the editor")
        XCTAssertTrue(today.isHittable,
                      "long Brief text must scroll inside the editor, not push the due-date section off-screen")

        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(poll(timeout: timeout) { !self.detailSheet.exists })
    }
```

- [ ] **Step 2: Run the test to verify it fails**

Run:
```bash
pkill -f xcodebuild; pkill -f Tack.app
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild -project Tack.xcodeproj -scheme Tack \
  -destination "platform=macOS,arch=$(uname -m)" -derivedDataPath .build/DerivedData \
  -only-testing:TackUITests/CardDetailUITests/testLongBriefScrollsInsideEditorNotSheet \
  -parallel-testing-enabled NO test 2>&1 | tee .build/m0-task2-red.log
```
Expected: `** TEST FAILED **` on the `isHittable` assertion (the due-date section is scrolled out). If it unexpectedly PASSES, stop and investigate the layout assumption before touching the view — do not skip to Step 3.

- [ ] **Step 3: Restructure the body**

In `Tack/Views/CardDetail/CardDetailView.swift`, replace the `body` content skeleton: **delete the `ScrollView { ... }` wrapper** (keep its inner `VStack` and `.padding(20)`), and give the `TextEditor` a bounded, flexible frame. The result (comments preserved verbatim from the current file):

```swift
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 20) {
                TextField("Title", text: $title)
                    .textFieldStyle(.plain)
                    .font(.title2)
                    .reportsTextInputFocus()
                    .accessibilityIdentifier(AccessibilityID.cardDetailTitleField)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Brief")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    // Native editable-text-area dressing (an NSTextView look: text background
                    // + separator hairline) — the old secondary wash read as a disabled
                    // control, especially in dark mode. NO `.scrollContentBackground(.hidden)`:
                    // SwiftUI's macOS TextEditor is already transparent (the old wash showed
                    // through without it), and adding it made the whole editor report
                    // AX-Disabled under XCUITest, killing keyboard-focus synthesis (caught by
                    // testEditDescriptionSavesAndPersists).
                    // The editor is the ONE flexible element in the sheet: bounded frame +
                    // layoutPriority means long text scrolls INSIDE the editor (NSTextView's
                    // own scrolling) while Labels/Due Date stay pinned below — there is
                    // deliberately no outer ScrollView (caught by
                    // testLongBriefScrollsInsideEditorNotSheet).
                    TextEditor(text: $details)
                        .font(.body)
                        .reportsTextInputFocus()
                        .frame(minHeight: 120, maxHeight: .infinity)
                        .layoutPriority(1)
                        .padding(4)
                        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                        // Hairline must NOT hit-test: a SwiftUI overlay above an AppKit-backed
                        // editor intercepts the click that gives the NSTextView keyboard focus
                        // (caught by testEditDescriptionSavesAndPersists).
                        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color(nsColor: .separatorColor)).allowsHitTesting(false))
                        .accessibilityIdentifier(AccessibilityID.cardDetailDescriptionField)
                }

                LabelPicker(selected: $labels)
                DueDatePicker(dueDate: $dueDate)
            }
            .padding(20)

            Divider()

            footer
                .padding(20)
        }
        .frame(width: 460, height: 560)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AccessibilityID.cardDetailSheet)
        // Belt-and-suspenders with Cancel's own `.cancelAction` shortcut below: this fires Esc
        // regardless of which staged-edit control (title field / description editor / label chip)
        // currently holds focus.
        .onExitCommand { dismiss() }
    }
```

(The `.frame(width: 460, height: 560)` stays fixed in this task; Task 3 relaxes it.)

- [ ] **Step 4: Run the new test to verify it passes**

Same command as Step 2, log to `.build/m0-task2-green.log`.
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 5: Run the editor-focus regression gate**

Run (same shape, different test):
```bash
pkill -f xcodebuild; pkill -f Tack.app
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild -project Tack.xcodeproj -scheme Tack \
  -destination "platform=macOS,arch=$(uname -m)" -derivedDataPath .build/DerivedData \
  -only-testing:TackUITests/CardDetailUITests/testEditDescriptionSavesAndPersists \
  -parallel-testing-enabled NO test 2>&1 | tee .build/m0-task2-regression.log
```
Expected: `** TEST SUCCEEDED **` (editor still clickable/focusable, value round-trips, id unchanged).

- [ ] **Step 6: Commit**

```bash
git add Tack/Views/CardDetail/CardDetailView.swift TackUITests/CardDetailUITests.swift
git commit -m "Card detail: Brief scrolls inside its editor, not the whole sheet

Removes the outer ScrollView (it scrolled the entire content column,
pushing Labels/Due Date off-screen under long text) and makes the
TextEditor the one flexible, bounded element so NSTextView's own
scrolling takes over.

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 3: User-resizable sheet (min 460×560)

**Files:**
- Modify: `Tack/Views/CardDetail/CardDetailView.swift` (the single `.frame(width: 460, height: 560)` line)
- Test: `TackUITests/CardDetailUITests.swift` (opening-size pin in `testOpenDetailViaDoubleClickBody`)

**Interfaces:**
- Consumes: Task 2's layout (flexible editor absorbs extra height when the sheet grows).
- Produces: nothing later tasks rely on.

Honesty note on TDD: XCUITest cannot reliably synthesize a sheet-edge resize drag (same class of limitation as the B-06 sidebar reorder — repo precedent is unit/automated-adjacent coverage + a documented human verification step). So this task pins the *opening size* automatically and verifies *resizability* manually.

- [ ] **Step 1: Add the opening-size pin (regression guard, passes before and after)**

> **Amended after empirical measurement (2026-07-08):** exact-equality pins are wrong in
> AX-space. The UITest window clamps the sheet's visible height — a hard
> `.frame(height: 560)` measures **520** through XCUITest — and the flexible frame opens
> 10 pt wider than `idealWidth` (470). The pin is therefore a **band**: it still catches
> the two real regressions a flexible frame can introduce (ballooning to window size /
> collapsing), without pinning environment-dependent values.

In `testOpenDetailViaDoubleClickBody`, after the "Brief" assertions from Task 1, add:

```swift
        // Opening size pin (band, not equality): AX-space sheet metrics are
        // environment-dependent — the UITest window clamps the sheet's visible height
        // (a hard 560pt frame reads 520 here) and the flexible frame opens ~10pt wider
        // than idealWidth. The band catches the real regressions (ballooning to window
        // size or collapsing) without pinning environment-dependent exact values.
        let sheetSize = detailSheet.frame.size
        XCTAssertTrue((450...480).contains(sheetSize.width),
                      "sheet should open near its 460pt ideal width, got \(sheetSize.width)")
        XCTAssertTrue((500...580).contains(sheetSize.height),
                      "sheet should open near its 560pt ideal height (AX reads it clamped ~520 under XCUITest), got \(sheetSize.height)")
```

- [ ] **Step 2: Make the frame flexible**

In `Tack/Views/CardDetail/CardDetailView.swift`, replace:

```swift
        .frame(width: 460, height: 560)
```

with:

```swift
        // Resizable sheet: flexible max + pinned ideal makes the macOS sheet user-resizable
        // while opening at (and never shrinking below) the classic 460×560.
        .frame(minWidth: 460, idealWidth: 460, maxWidth: .infinity,
               minHeight: 560, idealHeight: 560, maxHeight: .infinity)
```

- [ ] **Step 3: Run the pinned tests**

Run:
```bash
pkill -f xcodebuild; pkill -f Tack.app
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild -project Tack.xcodeproj -scheme Tack \
  -destination "platform=macOS,arch=$(uname -m)" -derivedDataPath .build/DerivedData \
  -only-testing:TackUITests/CardDetailUITests/testOpenDetailViaDoubleClickBody \
  -only-testing:TackUITests/CardDetailUITests/testLongBriefScrollsInsideEditorNotSheet \
  -parallel-testing-enabled NO test 2>&1 | tee .build/m0-task3-green.log
```
Expected: `** TEST SUCCEEDED **` (sheet still opens at 460×560; internal scrolling unaffected).

- [ ] **Step 4: Record the manual verification step (human-run, end of milestone)**

Add to the milestone's manual checklist (do not attempt to automate):

```bash
pkill -f Tack.app
make build
open .build/DerivedData/Build/Products/Debug/Tack.app --args --uitest --fixture standard --store-name scratch --reset
```
Then: **⌘N first** (windowless-launch pitfall), open any card's detail sheet, drag the sheet's bottom-right corner. Expect: the sheet grows and the Brief editor absorbs the extra height; the sheet cannot be shrunk below 460×560.

- [ ] **Step 5: Commit**

```bash
git add Tack/Views/CardDetail/CardDetailView.swift TackUITests/CardDetailUITests.swift
git commit -m "Card detail: make the sheet user-resizable (min 460x560)

Sheet resize itself is synthetic-input-untestable (B-06 precedent);
opening size is pinned by test, resize behavior human-verified.

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 4: Label picker becomes color circles only

**Files:**
- Modify: `Tack/Views/CardDetail/LabelPicker.swift` (chip rendering: circle swatches replace `LabelChipLabel` capsules)
- Modify: `Tack/Views/Components/DesignSystem.swift` (doc comment above `LabelChipLabel` only — code untouched)
- Test: `TackUITests/CardDetailUITests.swift` (new test)

**Interfaces:**
- Consumes: `LabelColor.allCases` (8 cases, canonical order), `color.swatchColor` (`LabelColor+Swatch.swift`), `AccessibilityID.labelChip(_:)`.
- Produces: the picker keeps its contract with existing tests — id `label-chip-<color>`, `.isSelected` trait on selected chips. NEW contract: chips carry `.accessibilityLabel(<Capitalized color>)` and `.help(<Capitalized color>)`, and render no visible text.

Critical constraint: `LabelChipLabel` is shared with `LabelFilterBar` (which keeps its current text-capsule look), and the chips' accessible names currently come from the visible `Text` — removing the text WITHOUT adding an explicit `.accessibilityLabel` would silently strip the chips' accessible names. Do not modify `LabelChipLabel`'s code.

- [ ] **Step 1: Write the failing test**

Add to `TackUITests/CardDetailUITests.swift` (after `testToggleLabelsReflectOnCardFace`):

```swift
    /// M-0: picker chips are color circles only — no visible color-name text — but MUST keep
    /// their color name as the accessibility label (VoiceOver + this suite's queries).
    func testPickerChipsAreCircleOnlyWithAccessibleNames() {
        launch(fixture: "standard")

        openDetailViaBodyDoubleClick("Call plumber")
        let red = labelChip("red")
        XCTAssertTrue(red.waitForExistence(timeout: timeout))
        XCTAssertEqual(red.staticTexts.count, 0,
                       "picker chips must render as color circles with no visible text")
        XCTAssertEqual(red.label, "Red",
                       "chips must keep their color name as the accessibility label")

        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(poll(timeout: timeout) { !self.detailSheet.exists })
    }
```

- [ ] **Step 2: Run the test to verify it fails**

Run:
```bash
pkill -f xcodebuild; pkill -f Tack.app
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild -project Tack.xcodeproj -scheme Tack \
  -destination "platform=macOS,arch=$(uname -m)" -derivedDataPath .build/DerivedData \
  -only-testing:TackUITests/CardDetailUITests/testPickerChipsAreCircleOnlyWithAccessibleNames \
  -parallel-testing-enabled NO test 2>&1 | tee .build/m0-task4-red.log
```
Expected: `** TEST FAILED **` on the `staticTexts.count` assertion (chips currently render `Text("Red")` etc. inside `LabelChipLabel`).

- [ ] **Step 3: Rewrite the picker chips as circles**

Replace the full contents of `Tack/Views/CardDetail/LabelPicker.swift` with:

```swift
import SwiftUI

/// The card-detail label toggles: one filled color circle per `LabelColor`, selection shown as
/// a checkmark + primary ring. Deliberately diverged (M-0 polish) from the shared
/// `LabelChipLabel` capsule that `LabelFilterBar` still uses — color-name text is dropped here,
/// so the color name MUST be re-attached as `.accessibilityLabel` (the visible `Text` used to
/// BE the accessible name) and is echoed as a `.help` tooltip for sighted hover.
struct LabelPicker: View {
    @Binding var selected: Set<LabelColor>

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Labels")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 10) {
                ForEach(LabelColor.allCases, id: \.self) { color in
                    chip(for: color)
                }
            }
        }
    }

    private func chip(for color: LabelColor) -> some View {
        let isSelected = selected.contains(color)
        let name = color.rawValue.capitalized
        return Button {
            toggle(color)
        } label: {
            ZStack {
                Circle()
                    .fill(color.swatchColor)
                    .frame(width: 26, height: 26)
                if isSelected {
                    // Black checkmark on the filled swatch — matches LabelChipLabel's
                    // audited selected-state treatment (black on all 8 swatch colors).
                    Image(systemName: "checkmark")
                        .font(.caption2.bold())
                        .foregroundStyle(Color.black)
                }
            }
            .overlay(Circle().strokeBorder(Color.primary.opacity(isSelected ? 0.6 : 0), lineWidth: 2))
        }
        .buttonStyle(.plain)
        .help(name)
        .accessibilityLabel(name)
        .accessibilityIdentifier(AccessibilityID.labelChip(color.rawValue))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func toggle(_ color: LabelColor) {
        if selected.contains(color) {
            selected.remove(color)
        } else {
            selected.insert(color)
        }
    }
}
```

- [ ] **Step 4: Update the LabelChipLabel doc comment (code untouched)**

In `Tack/Views/Components/DesignSystem.swift`, replace the doc comment immediately above `struct LabelChipLabel` with:

```swift
/// The label-chip look for the board's `LabelFilterBar` (text capsule + checkmark). The
/// card-detail `LabelPicker` deliberately diverged in the M-0 polish to color-circle-only
/// swatches — if a third chip consumer ever appears, pick which of the two looks it shares
/// instead of minting a fourth.
```

- [ ] **Step 5: Run the new test + every chip-dependent regression**

Run:
```bash
pkill -f xcodebuild; pkill -f Tack.app
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild -project Tack.xcodeproj -scheme Tack \
  -destination "platform=macOS,arch=$(uname -m)" -derivedDataPath .build/DerivedData \
  -only-testing:TackUITests/CardDetailUITests/testPickerChipsAreCircleOnlyWithAccessibleNames \
  -only-testing:TackUITests/CardDetailUITests/testToggleLabelsReflectOnCardFace \
  -only-testing:TackUITests/CardDetailUITests/testEscDiscardsStagedEdits \
  -only-testing:TackUITests/CardDetailUITests/testStagedEditsDoNotLeakAcrossCards \
  -parallel-testing-enabled NO test 2>&1 | tee .build/m0-task4-green.log
```
Expected: `** TEST SUCCEEDED **` — new test green; `.isSelected` round-trips and staged-edit semantics unchanged.

- [ ] **Step 6: Commit**

```bash
git add Tack/Views/CardDetail/LabelPicker.swift Tack/Views/Components/DesignSystem.swift TackUITests/CardDetailUITests.swift
git commit -m "Card detail: label picker becomes color circles only

Color names move from visible chip text to accessibilityLabel + .help
tooltip (the visible Text WAS the accessible name — dropping it without
re-attaching would strip VoiceOver names). LabelFilterBar keeps the
shared LabelChipLabel capsule look.

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 5: Milestone gate

**Files:** none modified (verification only).

- [ ] **Step 1: Full unit suite**

Run: `pkill -f xcodebuild; pkill -f Tack.app; make unit 2>&1 | tee .build/m0-gate-unit.log`
Expected: `** TEST SUCCEEDED **`.

- [ ] **Step 2: Full CardDetailUITests suite (now 11 tests)**

Run:
```bash
pkill -f xcodebuild; pkill -f Tack.app
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild -project Tack.xcodeproj -scheme Tack \
  -destination "platform=macOS,arch=$(uname -m)" -derivedDataPath .build/DerivedData \
  -only-testing:TackUITests/CardDetailUITests \
  -parallel-testing-enabled NO test 2>&1 | tee .build/m0-gate-carddetail.log
```
Expected: `** TEST SUCCEEDED **`, 11 tests.

- [ ] **Step 3: Full `make ui` — with the environmental triage rule**

Run: `pkill -f xcodebuild; pkill -f Tack.app; make ui 2>&1 | tee .build/m0-gate-ui.log` (~20–25 min; read the log to completion).
Expected: all suites green EXCEPT possibly `KeyboardShortcutUITests`/`LabelFilterUITests`, which are currently failing *environmentally* on this host (documented mode; latest pre-existing bundle shows 21 such failures). If they fail: control-run one against committed code (`git stash` not needed — these files are untouched by this plan); if the control also fails, it is the environment — the milestone gates on Steps 1–2 plus the untouched-suite diff, and the full-suite confirmation moves to after a fresh login session.

- [ ] **Step 4: Human checklist (hand to Ty)**

1. Task 3 Step 4's resize procedure (sheet grows, editor absorbs, min enforced).
2. Hover a label circle → tooltip shows the color name.
3. Visual pass in light AND dark mode: circle ring contrast, Brief editor hairline, sheet at min and enlarged sizes.
