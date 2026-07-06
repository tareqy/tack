import XCTest

/// M9 exit-gate tests for list collapse/expand (L-04): a column collapses to a narrow vertical
/// pill (name + card count), the state persists across relaunch, and a collapsed pill is still a
/// valid drop target (cards append) that list-reorder drags route AROUND. Fixture "standard"
/// (board Groceries selected by default: lists To Do / In Progress / Done).
final class CollapseUITests: KanbanUITestCase {

    private let timeout: TimeInterval = 15

    // MARK: - Collapse / expand round trip

    func testCollapseExpandRoundTrip() {
        launch(fixture: "standard")

        let inProgress = list("In Progress")
        XCTAssertTrue(inProgress.waitForExistence(timeout: timeout), "In Progress column should exist")
        XCTAssertTrue(poll(timeout: timeout) { self.collapseState("In Progress") == "expanded" },
                      "a column starts expanded")

        let chevron = collapseButton("In Progress")
        XCTAssertTrue(chevron.waitForExistence(timeout: timeout), "collapse chevron should exist")
        chevron.click()

        XCTAssertTrue(poll(timeout: timeout) { self.collapseState("In Progress") == "collapsed" },
                      "state should read 'collapsed' after collapsing")
        XCTAssertLessThan(list("In Progress").frame.width, 100,
                          "a collapsed column should shrink to a narrow pill")

        // The chevron keeps the same identifier in the pill; clicking it expands again.
        let expandChevron = collapseButton("In Progress")
        XCTAssertTrue(expandChevron.waitForExistence(timeout: timeout), "expand chevron should exist on the pill")
        expandChevron.click()

        XCTAssertTrue(poll(timeout: timeout) { self.collapseState("In Progress") == "expanded" },
                      "state should read 'expanded' after expanding")
        XCTAssertGreaterThan(list("In Progress").frame.width, 100,
                             "an expanded column should return to full width")
    }

    // MARK: - Persistence

    func testCollapsePersistsAcrossRelaunch() {
        launch(fixture: "standard")

        let done = list("Done")
        XCTAssertTrue(done.waitForExistence(timeout: timeout), "Done column should exist")

        collapseButton("Done").click()
        XCTAssertTrue(poll(timeout: timeout) { self.collapseState("Done") == "collapsed" },
                      "Done should be collapsed before relaunch")

        relaunchPreservingStore()

        let doneAfter = list("Done")
        XCTAssertTrue(doneAfter.waitForExistence(timeout: timeout), "Done column should exist after relaunch")
        XCTAssertTrue(poll(timeout: timeout) { self.collapseState("Done") == "collapsed" },
                      "collapsed state should persist across relaunch")
    }

    // MARK: - Drop onto a collapsed pill appends

    func testDropOnCollapsedListAppends() {
        launch(fixture: "standard")

        let done = list("Done")
        XCTAssertTrue(done.waitForExistence(timeout: timeout), "Done column should exist")

        collapseButton("Done").click()
        XCTAssertTrue(poll(timeout: timeout) { self.collapseState("Done") == "collapsed" },
                      "Done should be collapsed before the drop")

        let buyMilk = anyCard("Buy milk")
        XCTAssertTrue(buyMilk.waitForExistence(timeout: timeout), "Buy milk should exist in To Do")

        // Drag Buy milk from To Do onto the collapsed Done pill: its dual-import destination appends.
        drag(buyMilk, to: list("Done"), targetNormalizedOffset: CGVector(dx: 0.5, dy: 0.5), until: {
            self.cardIdentifiersByPosition(under: self.list("To Do")) == self.expected("Call plumber", "Return library books")
        })

        // Expand Done and assert the append landed at the end: [Book flights, Buy milk].
        collapseButton("Done").click()
        XCTAssertTrue(poll(timeout: timeout) { self.collapseState("Done") == "expanded" },
                      "Done should be expanded to read its order")
        XCTAssertEqual(cardIdentifiersByPosition(under: list("Done")),
                       expected("Book flights", "Buy milk"),
                       "Buy milk should append after Book flights in Done")

        XCTAssertEqual(cardIdentifiersByPosition(under: list("To Do")),
                       expected("Call plumber", "Return library books"),
                       "To Do should renumber to Call plumber, Return library books after Buy milk leaves")
    }

    // MARK: - List reorder around a collapsed pill

    func testListReorderWithCollapsedPresent() {
        launch(fixture: "standard")

        let inProgress = list("In Progress")
        XCTAssertTrue(inProgress.waitForExistence(timeout: timeout), "In Progress column should exist")

        collapseButton("In Progress").click()
        XCTAssertTrue(poll(timeout: timeout) { self.collapseState("In Progress") == "collapsed" },
                      "In Progress should be collapsed before the reorder")

        let toDoHeader = listHeader("To Do")
        let doneColumn = list("Done")
        XCTAssertTrue(toDoHeader.waitForExistence(timeout: timeout), "To Do header should exist")
        XCTAssertTrue(doneColumn.waitForExistence(timeout: timeout), "Done column should exist")

        let expectedOrder = ["In Progress", "Done", "To Do"]
        drag(toDoHeader, to: doneColumn, targetNormalizedOffset: CGVector(dx: 0.9, dy: 0.5), until: {
            self.columnOrder() == expectedOrder
        })

        XCTAssertEqual(columnOrder(), expectedOrder,
                       "list-drag routing must work around the collapsed pill: In Progress(pill), Done, To Do")
    }

    // MARK: - Element lookups

    private func list(_ name: String) -> XCUIElement {
        app.descendants(matching: .any)[AccessibilityID.list(name)]
    }

    private func listHeader(_ name: String) -> XCUIElement {
        app.descendants(matching: .any)[AccessibilityID.listHeader(name)]
    }

    private func collapseButton(_ name: String) -> XCUIElement {
        app.descendants(matching: .any)[AccessibilityID.collapseListButton(name)]
    }

    /// The machine-readable collapse state ("collapsed"/"expanded") published by a column's detached
    /// representation marker — the reliable-under-XCUITest channel (a `.contain` container's own
    /// `.value` is empty on macOS).
    private func collapseState(_ name: String) -> String? {
        app.descendants(matching: .any)[AccessibilityID.listCollapseState(name)].value as? String
    }

    private func anyCard(_ title: String) -> XCUIElement {
        app.descendants(matching: .any)[AccessibilityID.card(title)]
    }

    private func expected(_ titles: String...) -> [String] {
        titles.map(AccessibilityID.card)
    }

    /// The 3 standard-fixture list names, ordered left to right by their container's on-screen X
    /// position — the canonical way to assert column order (mirrors DragAndDropUITests).
    private func columnOrder() -> [String] {
        ["To Do", "In Progress", "Done"]
            .map { (name: $0, element: list($0)) }
            .filter { $0.element.exists }
            .sorted { $0.element.frame.minX < $1.element.frame.minX }
            .map(\.name)
    }
}
