import XCTest

/// M5 exit-gate tests for interactive cards on the real board surface: create (add-row + rapid
/// re-entry, and double-click-empty-body), rename (context menu), delete (no confirmation), move
/// (context-menu submenu), and single-click selection. Fixture "standard" (board Groceries
/// selected by default: To Do = [Buy milk, Call plumber, Return library books], In Progress =
/// [Write report], Done = [Book flights]) unless a test states otherwise.
final class CardCRUDUITests: TackUITestCase {

    private let timeout: TimeInterval = 15

    // MARK: - Create

    func testCreateCardViaAddRow() {
        launch(fixture: "standard")

        let toDo = list("To Do")
        XCTAssertTrue(toDo.waitForExistence(timeout: timeout))

        let addButton = addCardButton("To Do")
        XCTAssertTrue(addButton.waitForExistence(timeout: timeout))
        addButton.click()

        let field = newCardField
        XCTAssertTrue(field.waitForExistence(timeout: timeout), "add-card field should open")
        field.click()
        field.typeText("New Task")
        field.typeKey(.enter, modifierFlags: [])

        XCTAssertTrue(poll(timeout: timeout) { self.card("New Task", under: toDo).exists },
                      "card-New Task should appear under To Do")
        XCTAssertEqual(cardIdentifiersByPosition(under: toDo).last, AccessibilityID.card("New Task"),
                       "New Task should be the LAST (bottom) card in To Do")

        // Rapid entry: the field stays open — a second card can be typed immediately.
        XCTAssertTrue(field.waitForExistence(timeout: timeout), "add-card field should stay open after Enter")
        field.click()
        field.typeText("Second")
        field.typeKey(.enter, modifierFlags: [])
        XCTAssertTrue(poll(timeout: timeout) { self.card("Second", under: toDo).exists },
                      "card-Second should appear too")

        // Esc closes the field.
        field.click()
        field.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(poll(timeout: timeout) { !self.newCardField.exists },
                      "Esc should close the add-card field")
    }

    func testCreateCardViaDoubleClickEmptyBody() {
        launch(fixture: "standard")

        // Switch to the empty "Work" board (default lists, no cards).
        let workRow = boardRow("Work")
        XCTAssertTrue(workRow.waitForExistence(timeout: timeout))
        workRow.click()

        let toDo = list("To Do")
        XCTAssertTrue(toDo.waitForExistence(timeout: timeout))
        XCTAssertTrue(poll(timeout: timeout) { self.cardIdentifiersByPosition(under: toDo).isEmpty },
                      "Work's To Do should start empty")

        toDo.doubleClick()

        let field = newCardField
        XCTAssertTrue(field.waitForExistence(timeout: timeout),
                      "double-clicking the empty list body should open the add-card field")
        field.click()
        field.typeText("First")
        field.typeKey(.enter, modifierFlags: [])

        XCTAssertTrue(poll(timeout: timeout) { self.card("First", under: self.list("To Do")).exists },
                      "card-First should be created under To Do")
    }

    // MARK: - Rename

    func testRenameCard() {
        launch(fixture: "standard")

        let callPlumber = anyCard("Call plumber")
        XCTAssertTrue(callPlumber.waitForExistence(timeout: timeout))
        callPlumber.rightClick()
        contextMenuItem("Rename Card").click()

        // The title's InlineEditableText swaps to a TextField sharing the (old-title) identifier.
        let field = cardTitleField("Call plumber")
        XCTAssertTrue(poll(timeout: timeout) { field.elementType == .textField },
                      "Rename Card should swap the title for an editable field")
        field.click()
        selectAllAndDelete(field)
        field.typeText("Call electrician")
        field.typeKey(.enter, modifierFlags: [])

        XCTAssertTrue(poll(timeout: timeout) { self.anyCard("Call electrician").exists },
                      "card-Call electrician should exist after rename")
        XCTAssertFalse(anyCard("Call plumber").exists, "old card-Call plumber should be gone")
    }

    // MARK: - Delete (no confirmation)

    func testDeleteCardNoDialog() {
        launch(fixture: "standard")

        let bookFlights = anyCard("Book flights")
        XCTAssertTrue(bookFlights.waitForExistence(timeout: timeout))
        bookFlights.rightClick()
        contextMenuItem("Delete Card").click()

        // The card vanishes with NO confirmation step — if a dialog had blocked, it would still exist.
        XCTAssertTrue(poll(timeout: timeout) { !self.anyCard("Book flights").exists },
                      "card-Book flights should be gone immediately after Delete Card")
        XCTAssertFalse(app.sheets.firstMatch.exists, "delete must not present a sheet")
        XCTAssertFalse(app.windows.buttons["Cancel"].exists, "delete must not present a confirmation dialog")
    }

    // MARK: - Move via context menu

    func testMoveViaContextMenu() {
        launch(fixture: "standard")

        let toDo = list("To Do")
        let done = list("Done")
        XCTAssertTrue(toDo.waitForExistence(timeout: timeout))
        XCTAssertTrue(done.waitForExistence(timeout: timeout))

        let buyMilk = anyCard("Buy milk")
        XCTAssertTrue(buyMilk.waitForExistence(timeout: timeout))
        buyMilk.rightClick()
        contextMenuItem("Move to List").click() // open the submenu
        contextMenuItem("Done").click()         // pick the Done list

        XCTAssertTrue(poll(timeout: timeout) { self.card("Buy milk", under: self.list("Done")).exists },
                      "Buy milk should move under Done")
        XCTAssertEqual(cardIdentifiersByPosition(under: list("Done")).last, AccessibilityID.card("Buy milk"),
                       "Buy milk should land at the BOTTOM of Done")
        XCTAssertEqual(cardIdentifiersByPosition(under: list("To Do")),
                       expected("Call plumber", "Return library books"),
                       "To Do should renumber to Call plumber, Return library books")
    }

    // MARK: - Selection

    func testSelectionRing() {
        launch(fixture: "standard")

        let buyMilk = anyCard("Buy milk")
        let callPlumber = anyCard("Call plumber")
        XCTAssertTrue(buyMilk.waitForExistence(timeout: timeout))
        XCTAssertTrue(callPlumber.waitForExistence(timeout: timeout))

        buyMilk.click()
        XCTAssertTrue(poll(timeout: timeout) { self.anyCard("Buy milk").isSelected },
                      "clicking Buy milk should select it")

        callPlumber.click()
        XCTAssertTrue(poll(timeout: timeout) { self.anyCard("Call plumber").isSelected },
                      "clicking Call plumber should move selection to it")
        XCTAssertFalse(anyCard("Buy milk").isSelected, "only one card selected at a time")
    }

    // MARK: - Element lookups

    private func list(_ name: String) -> XCUIElement {
        app.descendants(matching: .any)[AccessibilityID.list(name)]
    }

    private func anyCard(_ title: String) -> XCUIElement {
        app.descendants(matching: .any)[AccessibilityID.card(title)]
    }

    private func card(_ title: String, under container: XCUIElement) -> XCUIElement {
        container.descendants(matching: .any)[AccessibilityID.card(title)]
    }

    private func cardTitleField(_ title: String) -> XCUIElement {
        app.descendants(matching: .any)[AccessibilityID.cardTitle(title)]
    }

    private func addCardButton(_ listName: String) -> XCUIElement {
        app.descendants(matching: .any)[AccessibilityID.addCardButton(list: listName)]
    }

    private var newCardField: XCUIElement {
        app.descendants(matching: .any)[AccessibilityID.newCardField]
    }

    private func boardRow(_ name: String) -> XCUIElement {
        app.descendants(matching: .any)[AccessibilityID.board(name)]
    }

    private func expected(_ titles: String...) -> [String] {
        titles.map(AccessibilityID.card)
    }

    private func selectAllAndDelete(_ field: XCUIElement) {
        field.typeKey("a", modifierFlags: .command)
        field.typeKey(.delete, modifierFlags: [])
    }
}
