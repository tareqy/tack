import XCTest

/// M9 exit-gate tests for list collapse/expand (L-04): a column collapses to a narrow vertical
/// pill (name + card count), the state persists across relaunch, and a collapsed pill is still a
/// valid drop target — cards append, list-reorder drags route AROUND it, and a list-reorder drag
/// dropped directly ONTO the pill itself resolves via the pill's own (narrower) midline math.
/// Fixture "standard" (board Groceries selected by default: lists To Do / In Progress / Done).
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

    // MARK: - List drag dropped directly onto a collapsed pill

    /// Unlike `testListReorderWithCollapsedPresent` (which routes a drag AROUND a collapsed pill
    /// by dropping on a full-width neighbor), this drops directly ONTO the pill itself, exercising
    /// `ListColumnView`'s pill-side `handleDrop` call, which resolves before/after at
    /// `collapsedWidth` (44pt) rather than the full `columnWidth` (280pt).
    ///
    /// Trace (siblings before the drop: To Do=0, In Progress=1, Done=2 — In Progress collapsed):
    /// dropping on the pill's center (normalized offset 0.5, 0.5) puts `location.x` at
    /// `collapsedWidth / 2` — exactly the midline. `DropMath`'s midline test is
    /// `location < extent / 2 ? .before : .after`, i.e. a point ON the midline is NOT `<` it, so it
    /// resolves to `.after` (documented at `DropMath.edge` as "midline inclusive of .after").
    /// `rowIndex` (In Progress's index — the pill receiving the drop) = 1; `fromIndex` (To Do's
    /// index) = 0; since `rowIndex > fromIndex`, `destinationIndex`'s `base = rowIndex - 1 = 0`;
    /// `.after` → target index = `base + 1 = 1`. `moveList(toDo, to: 1)` removes To Do from
    /// [To Do, In Progress, Done] (leaving [In Progress, Done]) and reinserts it at index 1 →
    /// [In Progress, To Do, Done]. So To Do lands immediately to the RIGHT of the still-collapsed
    /// In Progress pill: In Progress, To Do, Done.
    func testListDragOntoPillReorders() {
        launch(fixture: "standard")

        collapseButton("In Progress").click()
        XCTAssertTrue(poll(timeout: timeout) { self.collapseState("In Progress") == "collapsed" },
                      "In Progress should be collapsed before the drop")

        let toDoHeader = listHeader("To Do")
        let inProgressPill = list("In Progress")
        XCTAssertTrue(toDoHeader.waitForExistence(timeout: timeout), "To Do header should exist")
        XCTAssertTrue(inProgressPill.waitForExistence(timeout: timeout), "In Progress pill should exist")

        let expectedOrder = ["In Progress", "To Do", "Done"]

        // Drop To Do directly on the collapsed pill's center.
        drag(toDoHeader, to: inProgressPill, targetNormalizedOffset: CGVector(dx: 0.5, dy: 0.5), until: {
            self.columnOrder() == expectedOrder
        })

        XCTAssertEqual(columnOrder(), expectedOrder,
                       "dropping To Do onto the collapsed In Progress pill's center should land it just after the pill")
        XCTAssertEqual(collapseState("In Progress"), "collapsed",
                       "In Progress should remain collapsed after being the drop target of a list reorder")

        // Persistence: relaunch WITHOUT reset; the new column order survives.
        relaunchPreservingStore()

        XCTAssertTrue(poll(timeout: timeout) { self.columnOrder() == expectedOrder },
                      "the reordered column order should persist across relaunch")
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
