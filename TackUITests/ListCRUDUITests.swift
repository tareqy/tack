import XCTest

/// M4 exit-gate tests for the real board surface: list create, rename, delete (with
/// confirmation), and read-only card visibility. Fixture "standard" (board Groceries selected by
/// default: lists To Do / In Progress / Done) unless a test states otherwise.
final class ListCRUDUITests: TackUITestCase {

    private let timeout: TimeInterval = 15

    // MARK: - Create

    func testCreateList() {
        launch(fixture: "standard")

        let done = list("Done")
        XCTAssertTrue(done.waitForExistence(timeout: timeout))

        let addList = addListButton
        XCTAssertTrue(addList.waitForExistence(timeout: timeout))
        // The add-list ghost column overflows the horizontal ScrollView's viewport at the default
        // window size (3 fixture columns × 280pt already fill the detail pane), and clicks on
        // ScrollView-CLIPPED pixels are silently swallowed even though the element still reports
        // `isHittable == true` from its unclipped AX frame — empirically pinned down to the pixel:
        // at a 1562pt viewport edge, a click at x=1538 fired and a click at x=1562 did not.
        // Scroll the strip to its trailing end first so the ghost column (button AND the text
        // field that replaces it) is entirely inside the viewport.
        scrollColumnsToTrailingEnd(probe: done)
        XCTAssertTrue(addList.isHittable, "add-list should be scrolled into view before clicking")
        addList.click()

        XCTAssertTrue(newListField.waitForExistence(timeout: timeout))
        newListField.click()
        newListField.typeText("Blocked")
        newListField.typeKey(.enter, modifierFlags: [])

        let blocked = list("Blocked")
        XCTAssertTrue(poll(timeout: timeout) { blocked.exists }, "list-Blocked should appear after create")
        XCTAssertGreaterThan(blocked.frame.minX, done.frame.minX,
                              "the new list should be positioned after Done (further right)")

        let badge = cardCountBadge("Blocked")
        XCTAssertTrue(badge.waitForExistence(timeout: timeout))
        XCTAssertEqual(combinedText(badge), "0", "a freshly created list should show a 0 card count")
    }

    // MARK: - Rename

    func testRenameList() {
        launch(fixture: "standard")

        let header = listHeader("In Progress")
        XCTAssertTrue(header.waitForExistence(timeout: timeout))
        header.doubleClick()

        let field = listHeader("In Progress") // same a11y id; now resolves to the live TextField
        XCTAssertTrue(poll(timeout: timeout) { field.elementType == .textField },
                      "double-click should swap the header text for an editable field")
        field.click()
        selectAllAndDelete(field)
        field.typeText("Doing")
        field.typeKey(.enter, modifierFlags: [])

        XCTAssertTrue(poll(timeout: timeout) { self.list("Doing").exists }, "list-Doing should exist after rename")
        XCTAssertFalse(list("In Progress").exists, "old list-In Progress should be gone")
    }

    // MARK: - Delete

    func testDeleteListCancelThenConfirm() {
        launch(fixture: "standard")

        let doneHeader = listHeader("Done")
        XCTAssertTrue(doneHeader.waitForExistence(timeout: timeout))
        doneHeader.rightClick()
        contextMenuItem("Delete List").click()

        let cancelButton = hittableButton("Cancel")
        XCTAssertTrue(cancelButton.exists, "confirmation dialog should appear")
        cancelButton.click()

        XCTAssertTrue(poll(timeout: timeout) { self.list("Done").exists }, "cancel should leave list-Done in place")

        doneHeader.rightClick()
        contextMenuItem("Delete List").click()

        let confirmButton = app.descendants(matching: .any)[AccessibilityID.deleteListConfirm]
        XCTAssertTrue(confirmButton.waitForExistence(timeout: timeout), "confirmation dialog should appear")
        confirmButton.click()

        XCTAssertTrue(poll(timeout: timeout) { !self.list("Done").exists }, "list-Done should be gone after confirmed delete")
        XCTAssertTrue(list("To Do").exists, "other lists should remain intact")
        XCTAssertTrue(list("In Progress").exists, "other lists should remain intact")
    }

    // MARK: - Cards render read-only

    func testCardsVisibleReadOnly() {
        launch(fixture: "standard")

        let toDo = list("To Do")
        XCTAssertTrue(toDo.waitForExistence(timeout: timeout))
        let buyMilk = card("Buy milk", under: toDo)
        XCTAssertTrue(buyMilk.waitForExistence(timeout: timeout), "card-Buy milk should exist under list-To Do")
    }

    // MARK: - Element lookups

    private func list(_ name: String) -> XCUIElement {
        app.descendants(matching: .any)[AccessibilityID.list(name)]
    }

    private func listHeader(_ name: String) -> XCUIElement {
        app.descendants(matching: .any)[AccessibilityID.listHeader(name)]
    }

    private func cardCountBadge(_ name: String) -> XCUIElement {
        app.descendants(matching: .any)[AccessibilityID.listCardCount(name)]
    }

    private func card(_ title: String, under container: XCUIElement) -> XCUIElement {
        container.descendants(matching: .any)[AccessibilityID.card(title)]
    }

    private var addListButton: XCUIElement {
        app.descendants(matching: .any)[AccessibilityID.addListButton]
    }

    private var newListField: XCUIElement {
        app.descendants(matching: .any)[AccessibilityID.newListField]
    }

    private func selectAllAndDelete(_ field: XCUIElement) {
        field.typeKey("a", modifierFlags: .command)
        field.typeKey(.delete, modifierFlags: [])
    }

    /// Scroll-wheels the board's horizontal column strip all the way to its trailing (right) end.
    /// `probe` must be a column container that is on-screen initially (e.g. list-Done); its frame
    /// moving LEFT is the signal that a wheel burst actually scrolled the strip. Tries negative
    /// deltaX first (classic non-natural wheel convention: negative X reveals content further
    /// right), then positive as a fallback so the helper survives either convention; an extra
    /// burst after movement guarantees the strip is pinned at the end (deltas overshoot and
    /// clamp). Anchored over the middle of the detail pane (dx 0.6 clears the sidebar at the
    /// default window size).
    private func scrollColumnsToTrailingEnd(probe: XCUIElement) {
        let anchor = app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.5))
        for delta in [CGFloat(-1500), CGFloat(1500)] {
            let before = probe.frame.minX
            anchor.scroll(byDeltaX: delta, deltaY: 0)
            Thread.sleep(forTimeInterval: 0.3)
            if probe.frame.minX < before {
                anchor.scroll(byDeltaX: delta, deltaY: 0)
                Thread.sleep(forTimeInterval: 0.3)
                return
            }
        }
    }
}
