import XCTest

/// The M2 exit-gate tests: prove a real SwiftUI drag driven by XCUITest reorders and cross-moves
/// cards, and that the result survives a relaunch (real on-disk persistence).
final class DragAndDropUITests: TackUITestCase {

    private let timeout: TimeInterval = 15

    // MARK: - Cross-list drag

    func testSpikeCrossListDrag() {
        launch(fixture: "spike")

        let rightList = list("Right")
        XCTAssertTrue(rightList.waitForExistence(timeout: timeout), "Right list should exist")
        let a2 = anyCard("Spike A2")
        XCTAssertTrue(a2.waitForExistence(timeout: timeout), "Spike A2 should exist")

        // Drag A2 into the middle of the Right column (its footer append zone).
        drag(a2, to: rightList, targetNormalizedOffset: CGVector(dx: 0.5, dy: 0.5), until: {
            self.card("Spike A2", under: rightList).exists
        })

        XCTAssertTrue(card("Spike A2", under: rightList).waitForExistence(timeout: timeout),
                      "Spike A2 should be a descendant of the Right list after the drag")

        // Persistence: relaunch WITHOUT reset; A2 stays under Right and Left keeps A1, A3 in order.
        relaunchPreservingStore()

        let rightAfter = list("Right")
        XCTAssertTrue(rightAfter.waitForExistence(timeout: timeout), "Right list should exist after relaunch")
        XCTAssertTrue(card("Spike A2", under: rightAfter).waitForExistence(timeout: timeout),
                      "Spike A2 should still be under Right after relaunch")

        let leftAfter = list("Left")
        XCTAssertTrue(leftAfter.waitForExistence(timeout: timeout), "Left list should exist after relaunch")
        XCTAssertTrue(card("Spike A1", under: leftAfter).waitForExistence(timeout: timeout))
        XCTAssertEqual(cardIdentifiersByPosition(under: leftAfter),
                       expected("Spike A1", "Spike A3"),
                       "Left list should be A1, A3 after A2 moved out")
    }

    // MARK: - Reorder within a list

    func testSpikeReorderWithinList() {
        launch(fixture: "spike")

        let leftList = list("Left")
        XCTAssertTrue(leftList.waitForExistence(timeout: timeout), "Left list should exist")
        let a3 = anyCard("Spike A3")
        let a1 = anyCard("Spike A1")
        XCTAssertTrue(a3.waitForExistence(timeout: timeout), "Spike A3 should exist")
        XCTAssertTrue(a1.waitForExistence(timeout: timeout), "Spike A1 should exist")

        // Drop A3 onto the top third of A1 -> insert before A1 -> order becomes A3, A1, A2.
        let expectedOrder = expected("Spike A3", "Spike A1", "Spike A2")
        drag(a3, to: a1, targetNormalizedOffset: CGVector(dx: 0.5, dy: 0.15), until: {
            self.cardIdentifiersByPosition(under: leftList) == expectedOrder
        })

        XCTAssertEqual(cardIdentifiersByPosition(under: leftList), expectedOrder,
                       "Left list order should be A3, A1, A2 after reorder")

        // Persistence across relaunch.
        relaunchPreservingStore()

        let leftAfter = list("Left")
        XCTAssertTrue(leftAfter.waitForExistence(timeout: timeout), "Left list should exist after relaunch")
        XCTAssertTrue(anyCard("Spike A3").waitForExistence(timeout: timeout))
        XCTAssertEqual(cardIdentifiersByPosition(under: leftAfter), expectedOrder,
                       "Reordered order should persist across relaunch")
    }

    // MARK: - List reordering (M4, production BoardView — not the spike)

    func testReorderLists() {
        launch(fixture: "standard")

        let toDoHeader = listHeader("To Do")
        let doneColumn = list("Done")
        XCTAssertTrue(toDoHeader.waitForExistence(timeout: timeout), "To Do header should exist")
        XCTAssertTrue(doneColumn.waitForExistence(timeout: timeout), "Done column should exist")

        let expectedOrder = ["In Progress", "Done", "To Do"]

        // Drop "To Do" near the right edge of "Done" -> inserts after Done.
        drag(toDoHeader, to: doneColumn, targetNormalizedOffset: CGVector(dx: 0.9, dy: 0.5), until: {
            self.columnOrder() == expectedOrder
        })

        XCTAssertEqual(columnOrder(), expectedOrder, "columns should read In Progress, Done, To Do left to right")

        // Persistence: relaunch WITHOUT reset; the new column order survives.
        relaunchPreservingStore()

        XCTAssertTrue(poll(timeout: timeout) { self.columnOrder() == expectedOrder },
                      "reordered column order should persist across relaunch")
    }

    // MARK: - Card drag on the production board (M5)

    /// Reorder within a list: drag "Buy milk" onto the bottom third of "Return library books"
    /// (insert after) → To Do becomes [Call plumber, Return library books, Buy milk]; persists.
    func testReorderWithinListOnBoard() {
        launch(fixture: "standard")

        let toDo = list("To Do")
        XCTAssertTrue(toDo.waitForExistence(timeout: timeout), "To Do should exist")
        let buyMilk = anyCard("Buy milk")
        let returnBooks = anyCard("Return library books")
        XCTAssertTrue(buyMilk.waitForExistence(timeout: timeout))
        XCTAssertTrue(returnBooks.waitForExistence(timeout: timeout))

        let expectedOrder = expected("Call plumber", "Return library books", "Buy milk")
        drag(buyMilk, to: returnBooks, targetNormalizedOffset: CGVector(dx: 0.5, dy: 0.8), until: {
            self.cardIdentifiersByPosition(under: toDo) == expectedOrder
        })

        XCTAssertEqual(cardIdentifiersByPosition(under: toDo), expectedOrder,
                       "To Do should read Call plumber, Return library books, Buy milk")

        relaunchPreservingStore()
        let toDoAfter = list("To Do")
        XCTAssertTrue(toDoAfter.waitForExistence(timeout: timeout))
        XCTAssertTrue(poll(timeout: timeout) { self.cardIdentifiersByPosition(under: toDoAfter) == expectedOrder },
                      "reordered order should persist across relaunch")
    }

    /// Cross-list move: drag "Write report" onto the "Done" footer append zone → Done becomes
    /// [Book flights, Write report], source "In Progress" empties; persists.
    func testMoveCardAcrossListsOnBoard() {
        launch(fixture: "standard")

        let inProgress = list("In Progress")
        let done = list("Done")
        XCTAssertTrue(inProgress.waitForExistence(timeout: timeout))
        XCTAssertTrue(done.waitForExistence(timeout: timeout))
        let writeReport = anyCard("Write report")
        XCTAssertTrue(writeReport.waitForExistence(timeout: timeout))

        drag(writeReport, to: done, targetNormalizedOffset: CGVector(dx: 0.5, dy: 0.6), until: {
            self.card("Write report", under: self.list("Done")).exists
        })

        XCTAssertTrue(card("Write report", under: list("Done")).waitForExistence(timeout: timeout),
                      "Write report should move under Done")
        XCTAssertEqual(cardIdentifiersByPosition(under: list("Done")),
                       expected("Book flights", "Write report"),
                       "Done should read Book flights, Write report by frame order")
        XCTAssertTrue(poll(timeout: timeout) { self.cardIdentifiersByPosition(under: self.list("In Progress")).isEmpty },
                      "In Progress should be empty after Write report leaves")

        relaunchPreservingStore()
        let doneAfter = list("Done")
        XCTAssertTrue(doneAfter.waitForExistence(timeout: timeout))
        XCTAssertTrue(poll(timeout: timeout) { self.card("Write report", under: doneAfter).exists },
                      "moved card should persist under Done across relaunch")
    }

    /// Drop onto a completely empty list: on board "Work", create "Solo" in To Do then drag it onto
    /// the empty "Done" body → contained under Done, To Do empties.
    func testDragToEmptyList() {
        launch(fixture: "standard")

        let workRow = boardRow("Work")
        XCTAssertTrue(workRow.waitForExistence(timeout: timeout))
        workRow.click()

        let toDo = list("To Do")
        let done = list("Done")
        XCTAssertTrue(toDo.waitForExistence(timeout: timeout))
        XCTAssertTrue(done.waitForExistence(timeout: timeout))

        // Create "Solo" via the add-card row, then close the field so it can't shadow the drag.
        let addButton = addCardButton("To Do")
        XCTAssertTrue(addButton.waitForExistence(timeout: timeout))
        addButton.click()
        let field = newCardField
        XCTAssertTrue(field.waitForExistence(timeout: timeout))
        field.click()
        field.typeText("Solo")
        field.typeKey(.enter, modifierFlags: [])
        XCTAssertTrue(poll(timeout: timeout) { self.card("Solo", under: toDo).exists }, "Solo should be created")
        field.typeKey(.escape, modifierFlags: [])

        let solo = anyCard("Solo")
        XCTAssertTrue(solo.waitForExistence(timeout: timeout))
        drag(solo, to: done, targetNormalizedOffset: CGVector(dx: 0.5, dy: 0.5), until: {
            self.card("Solo", under: self.list("Done")).exists
        })

        XCTAssertTrue(card("Solo", under: list("Done")).waitForExistence(timeout: timeout),
                      "Solo should move into the empty Done list")
        XCTAssertTrue(poll(timeout: timeout) { self.cardIdentifiersByPosition(under: self.list("To Do")).isEmpty },
                      "To Do should be empty after Solo moves out")
    }

    /// COEXISTENCE REGRESSION: with card drop destinations present on every column, a list-header
    /// drag (ListTransfer) must STILL reorder columns. Drag "To Do" right of "Done" on Groceries.
    func testListDragStillWorksWithCardDestinations() {
        launch(fixture: "standard")

        let toDoHeader = listHeader("To Do")
        let doneColumn = list("Done")
        XCTAssertTrue(toDoHeader.waitForExistence(timeout: timeout))
        XCTAssertTrue(doneColumn.waitForExistence(timeout: timeout))

        let expectedOrder = ["In Progress", "Done", "To Do"]
        drag(toDoHeader, to: doneColumn, targetNormalizedOffset: CGVector(dx: 0.9, dy: 0.5), until: {
            self.columnOrder() == expectedOrder
        })

        XCTAssertEqual(columnOrder(), expectedOrder,
                       "ListTransfer drops must still fire with CardTransfer destinations present")
    }

    // MARK: - Element lookups

    private func list(_ name: String) -> XCUIElement {
        app.descendants(matching: .any)[AccessibilityID.list(name)]
    }

    private func boardRow(_ name: String) -> XCUIElement {
        app.descendants(matching: .any)[AccessibilityID.board(name)]
    }

    private func addCardButton(_ listName: String) -> XCUIElement {
        app.descendants(matching: .any)[AccessibilityID.addCardButton(list: listName)]
    }

    private var newCardField: XCUIElement {
        app.descendants(matching: .any)[AccessibilityID.newCardField]
    }

    private func listHeader(_ name: String) -> XCUIElement {
        app.descendants(matching: .any)[AccessibilityID.listHeader(name)]
    }

    /// The 3 standard-fixture list names ("To Do", "In Progress", "Done"), ordered left to right
    /// by their container's on-screen X position — the canonical way to assert column order.
    private func columnOrder() -> [String] {
        ["To Do", "In Progress", "Done"]
            .map { (name: $0, element: list($0)) }
            .filter { $0.element.exists }
            .sorted { $0.element.frame.minX < $1.element.frame.minX }
            .map(\.name)
    }

    private func anyCard(_ title: String) -> XCUIElement {
        app.descendants(matching: .any)[AccessibilityID.card(title)]
    }

    private func card(_ title: String, under container: XCUIElement) -> XCUIElement {
        container.descendants(matching: .any)[AccessibilityID.card(title)]
    }

    private func expected(_ titles: String...) -> [String] {
        titles.map(AccessibilityID.card)
    }
}
