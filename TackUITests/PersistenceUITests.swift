import XCTest

/// Selection and board data must survive a relaunch against the same on-disk store.
final class PersistenceUITests: TackUITestCase {

    private let timeout: TimeInterval = 15

    func testSelectedBoardRestoredAfterRelaunch() {
        launch(fixture: "standard")

        let workRow = boardRow("Work")
        XCTAssertTrue(workRow.waitForExistence(timeout: timeout))
        workRow.click()

        XCTAssertTrue(poll(timeout: timeout) { self.boardDetail.exists && self.combinedText(self.boardDetail).contains("Work") },
                      "board-detail should show Work right after selecting it")

        relaunchPreservingStore()

        XCTAssertTrue(poll(timeout: timeout) { self.boardDetail.exists && self.combinedText(self.boardDetail).contains("Work") },
                      "board-detail should still show Work after relaunch (selection persisted)")
    }

    func testCreatedBoardPersistsAcrossRelaunch() {
        launch(fixture: "standard")

        let newBoardButton = app.descendants(matching: .any)[AccessibilityID.newBoardButton]
        XCTAssertTrue(newBoardButton.waitForExistence(timeout: timeout))
        newBoardButton.click()

        let nameField = app.descendants(matching: .any)[AccessibilityID.boardNameField]
        XCTAssertTrue(nameField.waitForExistence(timeout: timeout))
        nameField.click()
        nameField.typeText("Alpha")

        let confirmButton = app.descendants(matching: .any)[AccessibilityID.createBoardConfirm]
        confirmButton.click()

        let alphaRow = boardRow("Alpha")
        XCTAssertTrue(poll(timeout: timeout) { alphaRow.exists }, "board-Alpha row should appear after create")

        relaunchPreservingStore()

        XCTAssertTrue(poll(timeout: timeout) { self.boardRow("Alpha").exists },
                      "board-Alpha row should still exist after relaunch")
    }

    /// The plan's comprehensive journey: build a board end-to-end entirely through the M7 command
    /// layer (⇧⌘N board, ⌥⌘N list, ⌘N card) plus the M6 detail sheet (label + due date), then
    /// relaunch and assert every piece — board, list, card, label dot, due badge, orders — survives.
    func testFullJourneyPersists() {
        launch(fixture: "empty")
        XCTAssertTrue(rootView.waitForExistence(timeout: timeout))

        // ⇧⌘N → new-board sheet → "Trip".
        app.typeKey("n", modifierFlags: [.command, .shift])
        let nameField = element(AccessibilityID.boardNameField)
        XCTAssertTrue(nameField.waitForExistence(timeout: timeout), "⇧⌘N should open the new-board sheet")
        nameField.click()
        nameField.typeText("Trip")
        // Scoped, hittable click — a bare identifier query can resolve to the simulated Touch Bar's
        // un-clickable duplicate of the sheet button (see TackUITestCase.hittableButton).
        hittableButton("Create").click()

        XCTAssertTrue(poll(timeout: timeout) { self.boardDetail.exists && self.combinedText(self.boardDetail).contains("Trip") },
                      "Trip board should be shown after creation")

        // ⌥⌘N → add-list editor → "Ideas".
        app.typeKey("n", modifierFlags: [.command, .option])
        let listField = element(AccessibilityID.newListField)
        XCTAssertTrue(listField.waitForExistence(timeout: timeout), "⌥⌘N should open the add-list editor")
        listField.click()
        listField.typeText("Ideas")
        listField.typeKey(.enter, modifierFlags: [])
        XCTAssertTrue(poll(timeout: timeout) { self.list("Ideas").exists }, "Ideas list should be created")

        // ⌘N → add-card editor on the first list (To Do) → "Visit Kyoto".
        app.typeKey("n", modifierFlags: .command)
        let cardField = element(AccessibilityID.newCardField)
        XCTAssertTrue(cardField.waitForExistence(timeout: timeout), "⌘N should open the add-card editor")
        cardField.click()
        cardField.typeText("Visit Kyoto")
        cardField.typeKey(.enter, modifierFlags: [])
        XCTAssertTrue(poll(timeout: timeout) { self.card("Visit Kyoto", under: self.list("To Do")).exists },
                      "Visit Kyoto should be created in To Do")
        app.typeKey(.escape, modifierFlags: []) // close the rapid-entry field

        // Detail: label green + due Tomorrow → Save.
        let card = anyCard("Visit Kyoto")
        XCTAssertTrue(card.waitForExistence(timeout: timeout))
        card.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).doubleClick()
        XCTAssertTrue(detailSheet.waitForExistence(timeout: timeout), "detail sheet should open")
        element(AccessibilityID.labelChip("green")).click()
        element(AccessibilityID.dueQuickTomorrow).click()
        hittableButton("Save").click()
        XCTAssertTrue(poll(timeout: timeout) { !self.detailSheet.exists }, "Save should close the sheet")

        // Everything visible before relaunch.
        let labels = element(AccessibilityID.cardLabels("Visit Kyoto"))
        let badge = element(AccessibilityID.dueDateBadge(card: "Visit Kyoto"))
        XCTAssertTrue(poll(timeout: timeout) { (labels.value as? String)?.contains("green") == true },
                      "green label dot should show on the card face")
        XCTAssertTrue(poll(timeout: timeout) { badge.exists }, "due badge should show on the card face")

        // Relaunch against the same store WITHOUT --reset: everything persists.
        relaunchPreservingStore()

        XCTAssertTrue(poll(timeout: timeout) { self.boardDetail.exists && self.combinedText(self.boardDetail).contains("Trip") },
                      "Trip should still be selected/shown after relaunch")
        XCTAssertTrue(poll(timeout: timeout) { self.list("Ideas").exists }, "Ideas list should persist")
        XCTAssertTrue(poll(timeout: timeout) { self.card("Visit Kyoto", under: self.list("To Do")).exists },
                      "Visit Kyoto should persist in To Do")
        XCTAssertEqual(cardIdentifiersByPosition(under: list("To Do")), [AccessibilityID.card("Visit Kyoto")],
                       "To Do order should be intact after relaunch")

        let labelsAfter = element(AccessibilityID.cardLabels("Visit Kyoto"))
        XCTAssertTrue(poll(timeout: timeout) { (labelsAfter.value as? String)?.contains("green") == true },
                      "green label dot should persist")
        XCTAssertTrue(element(AccessibilityID.dueDateBadge(card: "Visit Kyoto")).waitForExistence(timeout: timeout),
                      "due badge should persist")
    }

    // MARK: - Element lookups

    private var rootView: XCUIElement {
        app.descendants(matching: .any)[AccessibilityID.rootView]
    }

    private var boardDetail: XCUIElement {
        app.descendants(matching: .any)[AccessibilityID.boardDetail]
    }

    private var detailSheet: XCUIElement {
        app.descendants(matching: .any)[AccessibilityID.cardDetailSheet]
    }

    private func boardRow(_ name: String) -> XCUIElement {
        app.descendants(matching: .any)[AccessibilityID.board(name)]
    }

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

    private func list(_ name: String) -> XCUIElement {
        app.descendants(matching: .any)[AccessibilityID.list(name)]
    }

    private func anyCard(_ title: String) -> XCUIElement {
        app.descendants(matching: .any)[AccessibilityID.card(title)]
    }

    private func card(_ title: String, under container: XCUIElement) -> XCUIElement {
        container.descendants(matching: .any)[AccessibilityID.card(title)]
    }
}
