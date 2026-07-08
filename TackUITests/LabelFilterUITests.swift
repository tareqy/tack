import XCTest

/// M11 exit-gate tests for the label filter bar (LB-03): OR-semantics filtering board-wide, the
/// count badge's "visible/total" format, Clear vs Esc (Esc additionally hides the bar; Clear does
/// not), the ⌘F / View ▸ "Filter by Label" toggle, and per-board reset. Fixture "standard" (board
/// Groceries selected by default: To Do = [Buy milk, Call plumber, Return library books],
/// In Progress = [Write report], Done = [Book flights]; Buy milk carries [green, blue], Write
/// report carries [red], everything else is unlabeled).
final class LabelFilterUITests: TackUITestCase {

    private let timeout: TimeInterval = 15

    // MARK: - Filtering

    func testFilterByOneLabel() {
        launch(fixture: "standard")
        XCTAssertTrue(boardDetail.waitForExistence(timeout: timeout))

        openFilterBar()
        filterChip("red").click()

        XCTAssertTrue(poll(timeout: timeout) { self.anyCard("Write report").exists },
                      "Write report (red) should stay visible")
        XCTAssertFalse(anyCard("Buy milk").exists, "Buy milk (green,blue) should be hidden")
        XCTAssertFalse(anyCard("Call plumber").exists, "unlabeled Call plumber should be hidden")
        XCTAssertFalse(anyCard("Return library books").exists, "unlabeled Return library books should be hidden")
        XCTAssertFalse(anyCard("Book flights").exists, "unlabeled Book flights should be hidden")

        XCTAssertEqual(combinedText(cardCountBadge("To Do")), "0/3", "none of To Do's cards are red")
        XCTAssertEqual(combinedText(cardCountBadge("In Progress")), "1/1", "In Progress's one card is red")
    }

    func testFilterOrSemantics() {
        launch(fixture: "standard")
        XCTAssertTrue(boardDetail.waitForExistence(timeout: timeout))

        openFilterBar()
        filterChip("red").click()
        filterChip("green").click()

        XCTAssertTrue(poll(timeout: timeout) { self.anyCard("Buy milk").exists },
                      "Buy milk (green) should be visible under OR semantics")
        XCTAssertTrue(anyCard("Write report").exists, "Write report (red) should be visible")
        XCTAssertFalse(anyCard("Call plumber").exists, "unlabeled cards stay hidden")
        XCTAssertFalse(anyCard("Return library books").exists, "unlabeled cards stay hidden")
        XCTAssertFalse(anyCard("Book flights").exists, "unlabeled cards stay hidden")
    }

    // MARK: - Clear vs Esc

    func testClearRestores() {
        launch(fixture: "standard")
        XCTAssertTrue(boardDetail.waitForExistence(timeout: timeout))

        openFilterBar()
        filterChip("red").click()
        XCTAssertTrue(poll(timeout: timeout) { !self.anyCard("Buy milk").exists })

        let clear = element(AccessibilityID.filterClear)
        XCTAssertTrue(clear.waitForExistence(timeout: timeout), "Clear should appear once a filter is active")
        clear.click()

        XCTAssertTrue(poll(timeout: timeout) { self.anyCard("Buy milk").exists }, "Clear should restore all cards")
        XCTAssertEqual(combinedText(cardCountBadge("To Do")), "3", "counts should return to plain totals")
        XCTAssertTrue(filterChip("red").exists, "Clear must NOT hide the bar itself")

        // Esc: re-activate, then hide + clear via Esc this time.
        filterChip("red").click()
        XCTAssertTrue(poll(timeout: timeout) { !self.anyCard("Buy milk").exists })

        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(poll(timeout: timeout) { !self.filterChip("red").exists }, "Esc should hide the bar")
        XCTAssertTrue(poll(timeout: timeout) { self.anyCard("Buy milk").exists }, "Esc should also clear the filter")
    }

    // MARK: - Menu / ⌘F toggle

    func testFilterMenuItemTogglesBar() {
        launch(fixture: "standard")
        XCTAssertTrue(boardDetail.waitForExistence(timeout: timeout))

        openMenu("View")
        let toggle = menuItem("Filter by Label")
        XCTAssertTrue(toggle.waitForExistence(timeout: timeout), "View ▸ Filter by Label should exist")
        toggle.click()
        XCTAssertTrue(poll(timeout: timeout) { self.filterChip("red").exists },
                      "the menu item should show the bar")

        app.typeKey("f", modifierFlags: .command)
        XCTAssertTrue(poll(timeout: timeout) { !self.filterChip("red").exists },
                      "⌘F again should hide the bar")
    }

    // MARK: - Keyboard navigation over the filtered (visible) snapshot

    /// Final review (visibility seam): arrow navigation traverses only the VISIBLE cards. With a
    /// red|green filter active, only Buy milk (green) and Write report (red) are on screen; arrows
    /// step between them, skipping the hidden To Do cards entirely.
    func testArrowNavigationTraversesOnlyVisibleCards() {
        launch(fixture: "standard")
        XCTAssertTrue(boardDetail.waitForExistence(timeout: timeout))

        openFilterBar()
        filterChip("red").click()
        filterChip("green").click()

        XCTAssertTrue(poll(timeout: timeout) { self.anyCard("Buy milk").exists }, "Buy milk (green) visible")
        XCTAssertTrue(anyCard("Write report").exists, "Write report (red) visible")
        XCTAssertFalse(anyCard("Call plumber").exists, "unlabeled To Do cards are hidden")
        XCTAssertFalse(anyCard("Return library books").exists, "unlabeled To Do cards are hidden")

        // ↓ with no selection enters at the first VISIBLE card (Buy milk, To Do).
        app.typeKey(.downArrow, modifierFlags: [])
        XCTAssertTrue(poll(timeout: timeout) { self.anyCard("Buy milk").isSelected },
                      "↓ should enter at the first visible card")

        // ↓ again crosses to the next VISIBLE card (Write report), skipping the hidden To Do cards.
        app.typeKey(.downArrow, modifierFlags: [])
        XCTAssertTrue(poll(timeout: timeout) { self.anyCard("Write report").isSelected },
                      "↓ should skip hidden cards and land on the next visible card (Write report)")
    }

    // MARK: - Esc dismisses a confirmationDialog without collapsing the filter bar (regression)

    /// Regression: Esc pressed to dismiss a delete-list confirmation must be consumed by the
    /// dialog only — it must NOT also fire `BoardView.onExitCommand` and hide/clear the filter bar
    /// (the two Esc-cancel mechanisms are on different responders and must stay independent).
    func testEscInDeleteListConfirmKeepsFilterBar() {
        launch(fixture: "standard")
        XCTAssertTrue(boardDetail.waitForExistence(timeout: timeout))

        openFilterBar()
        filterChip("red").click()
        XCTAssertTrue(poll(timeout: timeout) { !self.anyCard("Buy milk").exists }, "red filter hides Buy milk")

        // Open the delete-list confirmation for To Do.
        let toDoHeader = element(AccessibilityID.listHeader("To Do"))
        XCTAssertTrue(toDoHeader.waitForExistence(timeout: timeout), "To Do header should exist")
        toDoHeader.rightClick()
        contextMenuItem("Delete List").click()

        let confirm = element(AccessibilityID.deleteListConfirm)
        XCTAssertTrue(confirm.waitForExistence(timeout: timeout), "delete-list confirmation should appear")

        // Esc dismisses the dialog...
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(poll(timeout: timeout) { !confirm.exists }, "Esc should dismiss the confirmation dialog")

        // ...but the filter bar stays visible AND the filter stays active AND To Do is intact.
        XCTAssertTrue(filterChip("red").exists, "the filter bar must remain visible after the dialog's Esc")
        XCTAssertFalse(anyCard("Buy milk").exists, "the filter must remain active (Buy milk still hidden)")
        XCTAssertTrue(element(AccessibilityID.list("To Do")).exists, "To Do must not be deleted")
    }

    // MARK: - Reset on board switch

    func testFilterResetsOnBoardSwitch() {
        launch(fixture: "standard")
        XCTAssertTrue(poll(timeout: timeout) { self.combinedText(self.boardDetail).contains("Groceries") })

        openFilterBar()
        filterChip("red").click()
        XCTAssertTrue(poll(timeout: timeout) { !self.anyCard("Buy milk").exists })

        app.typeKey("2", modifierFlags: .command)
        XCTAssertTrue(poll(timeout: timeout) { self.combinedText(self.boardDetail).contains("Work") },
                      "⌘2 should switch to the Work board")

        app.typeKey("1", modifierFlags: .command)
        XCTAssertTrue(poll(timeout: timeout) { self.combinedText(self.boardDetail).contains("Groceries") },
                      "⌘1 should switch back to Groceries")

        XCTAssertTrue(poll(timeout: timeout) { self.anyCard("Buy milk").exists },
                      "the filter should be inactive again after switching back")
        XCTAssertEqual(combinedText(cardCountBadge("To Do")), "3", "counts should be plain totals again")
    }

    // MARK: - Helpers

    private func openFilterBar() {
        app.typeKey("f", modifierFlags: .command)
        XCTAssertTrue(poll(timeout: timeout) { self.filterChip("red").exists }, "⌘F should open the filter bar")
    }

    private var boardDetail: XCUIElement { app.descendants(matching: .any)[AccessibilityID.boardDetail] }

    private func anyCard(_ title: String) -> XCUIElement {
        app.descendants(matching: .any)[AccessibilityID.card(title)]
    }

    private func cardCountBadge(_ name: String) -> XCUIElement {
        app.descendants(matching: .any)[AccessibilityID.listCardCount(name)]
    }

    private func filterChip(_ color: String) -> XCUIElement {
        app.descendants(matching: .any)[AccessibilityID.filterChip(color)]
    }

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

}
