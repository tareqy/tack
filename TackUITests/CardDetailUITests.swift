import XCTest

/// M6 exit-gate tests for the card detail sheet: open (double-click body / context menu), the
/// title-vs-body double-click distinction (M5 carried gap), staged edits (Save commits, Esc
/// discards), label chips reflected as card-face dots, due-date quick options + clear reflected
/// as the card-face badge, and delete-from-detail. Fixture "standard" (board Groceries: To Do =
/// [Buy milk, Call plumber, Return library books], In Progress = [Write report], Done =
/// [Book flights]).
final class CardDetailUITests: TackUITestCase {

    private let timeout: TimeInterval = 15

    // MARK: - Open / close

    func testOpenDetailViaDoubleClickBody() {
        launch(fixture: "standard")

        openDetailViaBodyDoubleClick("Call plumber")

        let titleField = element(AccessibilityID.cardDetailTitleField)
        XCTAssertTrue(titleField.waitForExistence(timeout: timeout), "detail title field should exist")
        XCTAssertEqual(titleField.value as? String, "Call plumber",
                       "title field should be pre-filled with the card's title")

        XCTAssertTrue(detailSheet.staticTexts["Brief"].exists,
                      "description section should be titled Brief")
        XCTAssertFalse(detailSheet.staticTexts["Description"].exists,
                       "the old Description section title must be gone")

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

        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(poll(timeout: timeout) { !self.detailSheet.exists }, "Esc should close the sheet")
    }

    func testOpenDetailViaContextMenu() {
        launch(fixture: "standard")

        let card = anyCard("Call plumber")
        XCTAssertTrue(card.waitForExistence(timeout: timeout))
        card.rightClick()
        contextMenuItem("Open Card").click()

        XCTAssertTrue(detailSheet.waitForExistence(timeout: timeout),
                      "card-detail sheet should open via the context menu")
    }

    /// M5 carried gap: double-click on the TITLE text renames inline; it must NOT open the sheet.
    /// Pins the title-vs-body double-click distinction from the other side of
    /// `testOpenDetailViaDoubleClickBody`.
    func testDoubleClickTitleRenamesNotOpens() {
        launch(fixture: "standard")

        let title = cardTitle("Buy milk")
        XCTAssertTrue(title.waitForExistence(timeout: timeout))
        title.doubleClick()

        // The title's InlineEditableText swaps to a TextField sharing the (old-title) identifier.
        XCTAssertTrue(poll(timeout: timeout) { title.elementType == .textField },
                      "double-clicking the title should start an inline rename")
        XCTAssertFalse(detailSheet.exists, "double-clicking the TITLE must not open the detail sheet")

        title.click()
        title.typeKey("a", modifierFlags: .command)
        title.typeKey(.delete, modifierFlags: [])
        title.typeText("Buy oat milk")
        title.typeKey(.enter, modifierFlags: [])

        XCTAssertTrue(poll(timeout: timeout) { self.anyCard("Buy oat milk").exists },
                      "card should be renamed to Buy oat milk")
        XCTAssertFalse(anyCard("Buy milk").exists, "old card-Buy milk should be gone")
        XCTAssertFalse(detailSheet.exists, "no sheet at any point in the rename flow")
    }

    // MARK: - Staged edits: Save commits

    func testEditDescriptionSavesAndPersists() {
        launch(fixture: "standard")

        openDetailViaBodyDoubleClick("Call plumber")
        let description = element(AccessibilityID.cardDetailDescriptionField)
        XCTAssertTrue(description.waitForExistence(timeout: timeout))
        description.click()
        description.typeText("Ask about the leak")

        // ⌘⏎ = Save & close (the ONLY keyboard commit: plain Return in the editor inserts newlines).
        app.typeKey(.return, modifierFlags: .command)
        XCTAssertTrue(poll(timeout: timeout) { !self.detailSheet.exists }, "⌘⏎ should save and close")

        openDetailViaBodyDoubleClick("Call plumber")
        XCTAssertEqual(element(AccessibilityID.cardDetailDescriptionField).value as? String,
                       "Ask about the leak",
                       "saved description should be shown on reopen")
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(poll(timeout: timeout) { !self.detailSheet.exists })

        relaunchPreservingStore()

        openDetailViaBodyDoubleClick("Call plumber")
        XCTAssertEqual(element(AccessibilityID.cardDetailDescriptionField).value as? String,
                       "Ask about the leak",
                       "description should persist across relaunch")
    }

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

    func testToggleLabelsReflectOnCardFace() {
        launch(fixture: "standard")

        // "Call plumber" starts with no labels.
        openDetailViaBodyDoubleClick("Call plumber")
        labelChip("red").click()
        labelChip("yellow").click()
        hittableButton("Save").click()
        XCTAssertTrue(poll(timeout: timeout) { !self.detailSheet.exists }, "Save should close the sheet")

        let labelsOnFace = element(AccessibilityID.cardLabels("Call plumber"))
        XCTAssertTrue(poll(timeout: timeout) { labelsOnFace.exists },
                      "label dots should appear on the card face after Save")
        XCTAssertEqual(labelsOnFace.value as? String, "red,yellow",
                       "dots value should list the toggled colors in LabelColor order")

        // Reopen: both chips selected; drop red.
        openDetailViaBodyDoubleClick("Call plumber")
        XCTAssertTrue(poll(timeout: timeout) { self.labelChip("red").isSelected },
                      "red chip should show selected on reopen")
        XCTAssertTrue(labelChip("yellow").isSelected, "yellow chip should show selected on reopen")
        labelChip("red").click()
        hittableButton("Save").click()
        XCTAssertTrue(poll(timeout: timeout) { !self.detailSheet.exists })

        XCTAssertTrue(poll(timeout: timeout) { labelsOnFace.value as? String == "yellow" },
                      "after removing red, dots value should be yellow only")
    }

    /// M-0: picker chips are color circles only — no wide text capsule — but MUST keep
    /// their color name as the accessibility label (VoiceOver + this suite's queries).
    /// XCUITest cannot see INSIDE the button (one atomic AX element), so the oracle is
    /// geometry: the old text capsule filled a ~99pt grid column; a color circle is ~26pt.
    func testPickerChipsAreCircleOnlyWithAccessibleNames() {
        launch(fixture: "standard")

        openDetailViaBodyDoubleClick("Call plumber")
        let red = labelChip("red")
        XCTAssertTrue(red.waitForExistence(timeout: timeout))
        XCTAssertLessThanOrEqual(red.frame.size.width, 60,
                                 "picker chips must be compact color circles, not text capsules — got width \(red.frame.size.width)")
        XCTAssertEqual(red.label, "Red",
                       "chips must keep their color name as the accessibility label")

        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(poll(timeout: timeout) { !self.detailSheet.exists })
    }

    /// M10 (D-03): extended in place — per the task-12 brief — to the new "<iso>|<status>" a11y
    /// value format (was a bare ISO date), keeping the SAME assertion strength (still one exact
    /// `XCTAssertEqual` against a fully-computed expected string, just a longer one). This also
    /// covers the brief's "badge updates when due date changes" scenario end to end (set Tomorrow →
    /// Save → badge shows `|tomorrow`; Clear → Save → badge gone), so a separate duplicate test was
    /// not added.
    func testDueDateQuickOptionAndClear() {
        launch(fixture: "standard")

        // "Book flights" (Done) has no due date, hence no badge (PRD v1.1).
        let badge = element(AccessibilityID.dueDateBadge(card: "Book flights"))
        XCTAssertFalse(badge.exists, "no badge before a due date is set")

        openDetailViaBodyDoubleClick("Book flights")
        element(AccessibilityID.dueQuickTomorrow).click()
        hittableButton("Save").click()
        XCTAssertTrue(poll(timeout: timeout) { !self.detailSheet.exists })

        // Badge value is a LOCAL full-date ISO string of tomorrow, plus the "|tomorrow" urgency
        // suffix M10 adds (see DueDateBadge's formatter + `DueDateBadgeStyle`/`wireValue`).
        let calendar = Calendar.current
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: Date()))!
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        formatter.timeZone = .current
        let expectedValue = "\(formatter.string(from: tomorrow))|tomorrow"

        XCTAssertTrue(poll(timeout: timeout) { badge.exists }, "badge should appear after Save")
        XCTAssertEqual(badge.value as? String, expectedValue,
                       "badge value should be tomorrow's ISO date plus the |tomorrow urgency suffix")

        // Reopen → Clear → Save → badge gone.
        openDetailViaBodyDoubleClick("Book flights")
        element(AccessibilityID.dueClear).click()
        hittableButton("Save").click()
        XCTAssertTrue(poll(timeout: timeout) { !self.detailSheet.exists })
        XCTAssertTrue(poll(timeout: timeout) { !badge.exists }, "badge should disappear after Clear + Save")
    }

    /// M-B: the Time toggle stages a 9:00 AM slot on a date-only pick (deterministic — the staged
    /// quick-button date is bare midnight), Save persists it, the badge exposes the timed a11y
    /// value ("<iso>T09:00|tomorrow" — status stays the LAST segment), and reopening shows the
    /// toggle on. The duration menu's interaction is human-verified (menu-style Picker popups
    /// under synthetic input are the B-06 class of problem); this test pins its presence only.
    func testTimedDueDateTogglePersists() {
        launch(fixture: "standard")

        // "Book flights" (Done) starts with no due date at all.
        openDetailViaBodyDoubleClick("Book flights")
        element(AccessibilityID.dueQuickTomorrow).click()
        let toggle = element(AccessibilityID.dueTimeToggle)
        XCTAssertTrue(toggle.waitForExistence(timeout: timeout),
                      "Time toggle should appear once a date is staged")
        toggle.click()

        XCTAssertTrue(element(AccessibilityID.dueTimeField).waitForExistence(timeout: timeout),
                      "hour-and-minute field should appear when the toggle is on")
        XCTAssertTrue(element(AccessibilityID.dueDurationField).exists,
                      "duration menu should appear when the toggle is on")

        hittableButton("Save").click()
        XCTAssertTrue(poll(timeout: timeout) { !self.detailSheet.exists })

        let badge = element(AccessibilityID.dueDateBadge(card: "Book flights"))
        XCTAssertTrue(poll(timeout: timeout) { badge.exists }, "badge should appear after Save")
        let value = badge.value as? String ?? ""
        XCTAssertTrue(value.contains("T09:00"),
                      "timed badge value should carry the deterministic 9:00 AM default slot, got '\(value)'")
        XCTAssertTrue(value.hasSuffix("|tomorrow"),
                      "status must stay the LAST a11y segment, got '\(value)'")

        // Reopen: staged state seeds from the card — the toggle reads on.
        openDetailViaBodyDoubleClick("Book flights")
        XCTAssertTrue(poll(timeout: timeout) { toggle.exists })
        // AX bridges a checkbox value as String or NSNumber depending on macOS build — coerce.
        let toggleValue = (toggle.value as? String) ?? (toggle.value as? Int).map(String.init) ?? ""
        XCTAssertEqual(toggleValue, "1", "Time toggle should read ON for a timed card")
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(poll(timeout: timeout) { !self.detailSheet.exists })
    }

    /// TRACKED HAZARD (Task 1 review): clicking a quick option on an ALREADY-TIMED card must reset
    /// the staged time state, not just the date — otherwise the quick button would silently commit
    /// a midnight "timed" card (`includesTime` true, `dueDate` at start-of-day). "Write report" is
    /// the fixture's timed card (14:00 +5d, 60min); staging Today must show the toggle OFF before
    /// Save is even clicked, proving the reset happens at stage time, not just on persist.
    func testQuickOptionOnTimedCardResetsTimeState() {
        launch(fixture: "standard")

        openDetailViaBodyDoubleClick("Write report")
        let toggle = element(AccessibilityID.dueTimeToggle)
        XCTAssertTrue(poll(timeout: timeout) { toggle.exists },
                      "Write report is timed — the toggle should already be visible")
        let initialToggleValue = (toggle.value as? String) ?? (toggle.value as? Int).map(String.init) ?? ""
        XCTAssertEqual(initialToggleValue, "1", "Write report should stage with its Time toggle ON")

        element(AccessibilityID.dueQuickToday).click()

        XCTAssertTrue(poll(timeout: timeout) {
            let current = (toggle.value as? String) ?? (toggle.value as? Int).map(String.init) ?? ""
            return current == "0"
        }, "a quick-pick on an already-timed card must reset the staged Time toggle to OFF")
        XCTAssertFalse(element(AccessibilityID.dueTimeField).exists,
                       "the hour-and-minute field must not remain staged after a quick-pick reset")

        hittableButton("Save").click()
        XCTAssertTrue(poll(timeout: timeout) { !self.detailSheet.exists })

        let badge = element(AccessibilityID.dueDateBadge(card: "Write report"))
        XCTAssertTrue(poll(timeout: timeout) { badge.exists })
        let value = badge.value as? String ?? ""
        XCTAssertFalse(value.contains("T"),
                       "a quick-picked date must persist date-only (no T<HH:mm> segment), got '\(value)'")
    }

    // MARK: - Staged edits: Esc discards

    func testEscDiscardsStagedEdits() {
        launch(fixture: "standard")

        // "Buy milk" starts with labels green,blue (fixture).
        let labelsOnFace = element(AccessibilityID.cardLabels("Buy milk"))
        XCTAssertTrue(labelsOnFace.waitForExistence(timeout: timeout))
        XCTAssertEqual(labelsOnFace.value as? String, "green,blue")

        openDetailViaBodyDoubleClick("Buy milk")
        let titleField = element(AccessibilityID.cardDetailTitleField)
        XCTAssertTrue(titleField.waitForExistence(timeout: timeout))
        titleField.click()
        titleField.typeKey("a", modifierFlags: .command)
        titleField.typeKey(.delete, modifierFlags: [])
        titleField.typeText("Changed title")
        labelChip("red").click()

        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(poll(timeout: timeout) { !self.detailSheet.exists }, "Esc should close the sheet")

        // Card face is unchanged: same title, same labels.
        XCTAssertTrue(anyCard("Buy milk").exists, "title must still be Buy milk after Esc")
        XCTAssertFalse(anyCard("Changed title").exists, "staged title must not be committed")
        XCTAssertEqual(labelsOnFace.value as? String, "green,blue",
                       "staged label toggle must not be committed")
    }

    /// Regression: staged (uncommitted) edits from one card's sheet must NOT leak into the next
    /// card's sheet. Edit + toggle a label on Buy milk, Cancel (discard), then open Call plumber
    /// and assert its fields show ITS real values.
    func testStagedEditsDoNotLeakAcrossCards() {
        launch(fixture: "standard")

        // Buy milk (labels green,blue): stage a title change + a label toggle, then Cancel.
        openDetailViaBodyDoubleClick("Buy milk")
        let titleField = element(AccessibilityID.cardDetailTitleField)
        XCTAssertTrue(titleField.waitForExistence(timeout: timeout))
        titleField.click()
        titleField.typeKey("a", modifierFlags: .command)
        titleField.typeKey(.delete, modifierFlags: [])
        titleField.typeText("Buy oat milk")
        labelChip("red").click() // toggle a label ON (staged)
        hittableButton("Cancel").click()
        XCTAssertTrue(poll(timeout: timeout) { !self.detailSheet.exists }, "Cancel should close the sheet")

        // Buy milk itself is unchanged (staged edits discarded).
        XCTAssertTrue(anyCard("Buy milk").exists, "Buy milk title must be unchanged after Cancel")
        XCTAssertFalse(anyCard("Buy oat milk").exists, "the staged title must not be committed")

        // Call plumber (unlabeled) must show its OWN values, not Buy milk's staged edits.
        openDetailViaBodyDoubleClick("Call plumber")
        XCTAssertEqual(element(AccessibilityID.cardDetailTitleField).value as? String, "Call plumber",
                       "the second sheet must show Call plumber's title, not the first card's staged edit")
        XCTAssertFalse(labelChip("red").isSelected, "Call plumber has no labels — no staged label may leak in")
        XCTAssertFalse(labelChip("green").isSelected, "no label from Buy milk may leak in")
        XCTAssertFalse(labelChip("blue").isSelected, "no label from Buy milk may leak in")
    }

    // MARK: - Delete from detail

    func testDeleteFromDetail() {
        launch(fixture: "standard")

        openDetailViaBodyDoubleClick("Write report")
        hittableButton("Delete Card").click()

        XCTAssertTrue(poll(timeout: timeout) { !self.detailSheet.exists }, "sheet should close on delete")
        XCTAssertTrue(poll(timeout: timeout) { !self.anyCard("Write report").exists },
                      "card should be gone immediately after Delete Card")
        XCTAssertFalse(app.windows.buttons["Cancel"].exists, "delete must not present a confirmation dialog")
    }

    // MARK: - M-E: Action Items

    /// Add two items on the checklist-free "Book flights" (it has NO meta line at all — labels
    /// none, due date none — so this also proves the fraction ALONE creates the meta line),
    /// toggle one done, Save, assert the face fraction, reopen (drafts seed from the card),
    /// and persist across relaunch.
    func testActionItemsAddToggleSavePersists() {
        launch(fixture: "standard")

        openDetailViaBodyDoubleClick("Book flights")
        XCTAssertTrue(detailSheet.staticTexts["Action Items"].exists,
                      "section header should read Action Items, below Brief")

        element(AccessibilityID.checkItemAdd).click()
        let firstField = element(AccessibilityID.checkItemText(0))
        XCTAssertTrue(firstField.waitForExistence(timeout: timeout))
        firstField.click()
        firstField.typeText("Pack bags")

        element(AccessibilityID.checkItemAdd).click()
        let secondField = element(AccessibilityID.checkItemText(1))
        XCTAssertTrue(secondField.waitForExistence(timeout: timeout))
        secondField.click()
        secondField.typeText("Check passport")

        element(AccessibilityID.checkItemToggle(0)).click()

        hittableButton("Save").click()
        XCTAssertTrue(poll(timeout: timeout) { !self.detailSheet.exists })

        let fraction = element(AccessibilityID.cardChecklist("Book flights"))
        XCTAssertTrue(poll(timeout: timeout) { fraction.exists },
                      "the fraction should appear after Save — it alone creates the meta line")
        XCTAssertEqual(fraction.value as? String, "1/2")

        openDetailViaBodyDoubleClick("Book flights")
        XCTAssertEqual(element(AccessibilityID.checkItemText(0)).value as? String, "Pack bags",
                       "drafts must seed from the persisted rows on reopen")
        XCTAssertEqual(element(AccessibilityID.checkItemText(1)).value as? String, "Check passport")
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(poll(timeout: timeout) { !self.detailSheet.exists })

        relaunchPreservingStore()

        let fractionAfter = element(AccessibilityID.cardChecklist("Book flights"))
        XCTAssertTrue(fractionAfter.waitForExistence(timeout: timeout),
                      "checklist should persist across relaunch")
        XCTAssertEqual(fractionAfter.value as? String, "1/2")
    }

    /// The seeded fixture card's face fraction (asserted here because NO other test opens Return
    /// library books' sheet — that's exactly why it carries the fixture checklist), plus the
    /// Cancel contract: staged toggle + delete + add must all be discarded.
    func testActionItemsCancelDiscardsAndFixtureFraction() {
        launch(fixture: "standard")

        let fraction = element(AccessibilityID.cardChecklist("Return library books"))
        XCTAssertTrue(fraction.waitForExistence(timeout: timeout),
                      "the fixture seeds 3 items (2 done) on Return library books")
        XCTAssertEqual(fraction.value as? String, "2/3")

        openDetailViaBodyDoubleClick("Return library books")
        XCTAssertEqual(element(AccessibilityID.checkItemText(0)).value as? String, "Renew library card",
                       "drafts seed in position order")
        element(AccessibilityID.checkItemToggle(2)).click()   // stage: done the not-done row
        element(AccessibilityID.checkItemDelete(0)).click()   // stage: delete the first row
        element(AccessibilityID.checkItemAdd).click()         // stage: add a row (now index 2)
        let newField = element(AccessibilityID.checkItemText(2))
        XCTAssertTrue(newField.waitForExistence(timeout: timeout))
        newField.click()
        newField.typeText("Staged only")

        hittableButton("Cancel").click()
        XCTAssertTrue(poll(timeout: timeout) { !self.detailSheet.exists })

        XCTAssertEqual(fraction.value as? String, "2/3",
                       "Cancel must discard every staged checklist change")
    }

    /// M-0 oracle, extended (the plan's sheet-layout resolution): 5 staged rows must NOT push
    /// the due-date controls off the fixed-ideal-height sheet — the rows live in a bounded,
    /// content-sized scroller, never in the flexible-layout negotiation.
    func testLongChecklistKeepsDueDateHittable() {
        launch(fixture: "standard")

        openDetailViaBodyDoubleClick("Call plumber")
        for _ in 0..<5 {
            element(AccessibilityID.checkItemAdd).click()
        }
        XCTAssertTrue(element(AccessibilityID.checkItemText(4)).waitForExistence(timeout: timeout),
                      "five staged rows should render")

        let today = element(AccessibilityID.dueQuickToday)
        XCTAssertTrue(today.exists, "due-date quick buttons should exist below the checklist")
        XCTAssertTrue(today.isHittable,
                      "a long checklist must stay bounded — never push the due-date section off-screen")

        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(poll(timeout: timeout) { !self.detailSheet.exists })
        // Belt-and-suspenders: even if these empty rows HAD been saved, whitespace-only drafts
        // drop at the store; either way the face must show no fraction.
        XCTAssertFalse(element(AccessibilityID.cardChecklist("Call plumber")).exists)
    }

    // MARK: - Open helper

    /// Opens the detail sheet by double-clicking the card BODY at dx 0.9 — far right of the row,
    /// away from the leading title text, whose own double-click gesture means rename (see
    /// `testDoubleClickTitleRenamesNotOpens` for the other side of that distinction).
    private func openDetailViaBodyDoubleClick(_ title: String) {
        let card = anyCard(title)
        XCTAssertTrue(card.waitForExistence(timeout: timeout), "card-\(title) should exist")
        card.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).doubleClick()
        XCTAssertTrue(detailSheet.waitForExistence(timeout: timeout),
                      "card-detail sheet should open on body double-click")
    }

    // MARK: - Element lookups

    private var detailSheet: XCUIElement {
        app.descendants(matching: .any)[AccessibilityID.cardDetailSheet]
    }

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

    private func anyCard(_ title: String) -> XCUIElement {
        app.descendants(matching: .any)[AccessibilityID.card(title)]
    }

    private func cardTitle(_ title: String) -> XCUIElement {
        app.descendants(matching: .any)[AccessibilityID.cardTitle(title)]
    }

    private func labelChip(_ color: String) -> XCUIElement {
        app.descendants(matching: .any)[AccessibilityID.labelChip(color)]
    }
}
