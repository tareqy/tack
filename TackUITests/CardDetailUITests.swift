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
