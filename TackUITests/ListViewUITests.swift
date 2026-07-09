import XCTest

/// M-C exit-gate tests for the List View. Fixture "standard" (board Groceries) buckets as:
/// Overdue = [Buy milk (−1d)], Today = [Call plumber], This Week = [Return library books (+1d),
/// Write report (+5d 14:00 timed)], No Date = [Book flights] — and Later is EMPTY, so its
/// section must be absent. All four tests are MOUSE-driven by design: mode switching goes
/// through the toolbar segment + the `view-mode-value` marker oracle, never the View menu.
///
/// DELIBERATELY NOT e2e'd here (host's degraded-keyboard environment — CLAUDE.md):
/// - View ▸ as Board / as List + ⌥⌘B/⌥⌘L (menu-enablement assertions fail deterministically in
///   the degraded state). Deferred to the fresh-session full run + the M-C human checklist.
/// - Bare-arrow row navigation (same failure class). The navigation math is unit-covered
///   (ListBucketSnapshotTests.selectionNavigationOverBuckets + SelectionNavigationTests).
final class ListViewUITests: TackUITestCase {

    private let timeout: TimeInterval = 15

    func testSwitchToListShowsBuckets() {
        launch(fixture: "standard")

        switchToList()

        XCTAssertTrue(section("overdue").waitForExistence(timeout: timeout), "Overdue section should exist")
        XCTAssertTrue(section("today").exists, "Today section should exist")
        XCTAssertTrue(section("this-week").exists, "This Week section should exist")
        XCTAssertTrue(section("no-date").exists, "No Date section should exist")
        XCTAssertFalse(section("later").exists, "empty buckets must be omitted, not rendered empty")

        XCTAssertTrue(row("Buy milk").exists)
        XCTAssertTrue(row("Call plumber").exists)
        XCTAssertTrue(row("Return library books").exists)
        XCTAssertTrue(row("Write report").exists)
        XCTAssertTrue(row("Book flights").exists)

        // Bucket MEMBERSHIP by geometry: a row sits below its own header and above the next one
        // (5 rows + 4 headers all fit in the 1440x850 window — no scrolling, frames are valid).
        XCTAssertTrue(row("Buy milk").frame.minY > section("overdue").frame.minY)
        XCTAssertTrue(row("Buy milk").frame.minY < section("today").frame.minY)
        XCTAssertTrue(row("Call plumber").frame.minY > section("today").frame.minY)
        XCTAssertTrue(row("Call plumber").frame.minY < section("this-week").frame.minY)
        XCTAssertTrue(row("Write report").frame.minY > section("this-week").frame.minY)
        XCTAssertTrue(row("Write report").frame.minY < section("no-date").frame.minY)
        XCTAssertTrue(row("Book flights").frame.minY > section("no-date").frame.minY)

        // The board canvas is genuinely gone (not just the marker flipped): no To Do column.
        XCTAssertFalse(element(AccessibilityID.list("To Do")).exists,
                       "the column canvas must not render in list mode")
    }

    func testModePersistsPerBoardAndRelaunch() {
        launch(fixture: "standard")

        switchToList() // Groceries → list

        // Work is untouched by Groceries' mode — per-board independence.
        let workRow = element(AccessibilityID.board("Work"))
        XCTAssertTrue(workRow.waitForExistence(timeout: timeout))
        workRow.click()
        XCTAssertTrue(poll(timeout: timeout) { self.viewModeValue() == "board" },
                      "Work should still be in board mode — modes are per-board")

        // Back to Groceries: list mode remembered within the session.
        element(AccessibilityID.board("Groceries")).click()
        XCTAssertTrue(poll(timeout: timeout) { self.viewModeValue() == "list" },
                      "Groceries should still be in list mode after switching away and back")

        relaunchPreservingStore()

        // Selection restore lands back on Groceries; its mode survived via the persisted map.
        XCTAssertTrue(section("overdue").waitForExistence(timeout: timeout),
                      "Groceries should come back in LIST mode after relaunch")
        XCTAssertEqual(viewModeValue(), "list")
    }

    func testOpenDetailFromRow() {
        launch(fixture: "standard")
        switchToList()

        // Unlike CardView (whose title's own double-click gesture means rename, forcing the
        // dx-0.9 body trick), rows have a PLAIN Text title — a centre double-click is fine.
        let target = row("Call plumber")
        XCTAssertTrue(target.waitForExistence(timeout: timeout))
        target.doubleClick()

        XCTAssertTrue(detailSheet.waitForExistence(timeout: timeout),
                      "double-clicking a list row should open the card-detail sheet")
        XCTAssertEqual(element(AccessibilityID.cardDetailTitleField).value as? String, "Call plumber",
                       "the sheet should show the double-clicked card")

        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(poll(timeout: timeout) { !self.detailSheet.exists }, "Esc should close the sheet")
    }

    func testDeleteFromRowContextMenu() {
        launch(fixture: "standard")
        switchToList()

        let target = row("Return library books")
        XCTAssertTrue(target.waitForExistence(timeout: timeout))
        target.rightClick()
        contextMenuItem("Delete Card").click()

        XCTAssertTrue(poll(timeout: timeout) { !self.row("Return library books").exists },
                      "the deleted card's row should disappear")
        XCTAssertTrue(section("this-week").exists,
                      "This Week survives — Write report is still in it")
    }

    // MARK: - Helpers

    /// Clicks the toolbar switcher's List segment, then WAITS on the `view-mode-value` marker —
    /// the deterministic oracle — rather than trusting the click. Segments carry accessibility
    /// LABELS only (see AccessibilityID.viewModePicker); macOS exposes segmented controls as
    /// radio buttons, with a plain-button and a coordinate fallback for AX-bridging drift.
    private func switchToList() {
        let picker = element(AccessibilityID.viewModePicker)
        XCTAssertTrue(picker.waitForExistence(timeout: timeout),
                      "the view-mode switcher should be in the toolbar")
        let radio = picker.radioButtons["List"]
        if radio.exists {
            radio.click()
        } else if picker.buttons["List"].exists {
            picker.buttons["List"].click()
        } else {
            // Last resort: List is the right half of a two-segment control.
            picker.coordinate(withNormalizedOffset: CGVector(dx: 0.75, dy: 0.5)).click()
        }
        XCTAssertTrue(poll(timeout: timeout) { self.viewModeValue() == "list" },
                      "view-mode-value should read 'list' after clicking the List segment")
    }

    private func viewModeValue() -> String {
        element(AccessibilityID.viewModeValue).value as? String ?? ""
    }

    private func section(_ slug: String) -> XCUIElement {
        element(AccessibilityID.listSection(slug))
    }

    private func row(_ title: String) -> XCUIElement {
        element(AccessibilityID.listRow(title))
    }

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

    private var detailSheet: XCUIElement {
        app.descendants(matching: .any)[AccessibilityID.cardDetailSheet]
    }
}
