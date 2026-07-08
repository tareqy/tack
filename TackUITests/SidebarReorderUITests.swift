import XCTest

/// B-06 board sidebar drag-reorder e2e: the filter gate (rows are NOT draggable while the
/// sidebar filter is non-empty).
///
/// The drag-itself tests (`testDragReorderPersistsAcrossRelaunch`, `testUndoRestoresOrderAfterDrag`)
/// were deleted per the design spec's documented fallback (see
/// `docs/superpowers/specs/2026-07-07-board-sidebar-reorder-design.md`, "Testing" section,
/// "Outcome: the risk materialized"): XCUITest's synthesized `press(forDuration:thenDragTo:)`
/// gesture visibly reorders the row mid-drag (confirmed via `.xcresult` screen recording) but the
/// drop never commits — NSTableView's drag session doesn't call `performDragOperation`, and the
/// order snaps back on release. Tuning `pressDuration`/`holdDuration` (0.9s/1.0s) made no
/// difference. A hand-equivalent CGEvent-driven synthetic drag against a manually launched build
/// DID commit the reorder, confirming the feature itself works and isolating the failure to
/// XCUITest's gesture synthesis specifically for native `List` `.onMove` (as opposed to the
/// custom `Tack/DragDrop/` `Transferable`-based drags elsewhere in the app, which XCUITest drives
/// fine). B-06's drag-reorder is covered by `Reordering`/`BoardStore.moveBoards` unit tests
/// (including the one-undo-step behavior) plus this manual verification, not by e2e.
///
/// Order is asserted by comparing row frame `minY` — rows never overlap, so "a above b" is
/// unambiguous. (No `boardIdentifiersByPosition` helper on the base class: a BEGINSWITH
/// "board-" snapshot filter would also match "board-detail" / "board-name-field" /
/// "board-theme-value", and two known rows don't need one.)
final class SidebarReorderUITests: TackUITestCase {

    private let timeout: TimeInterval = 15

    /// While the filter is non-empty the `.onMove` handler is nil, so an attempted drag must
    /// not reorder. Filtering by "o" keeps BOTH rows visible (Groceries and Work each contain
    /// an 'o'), so the drag has a real target and the no-op is meaningful.
    func testFilterDisablesReorder() {
        launch(fixture: "standard")

        let groceries = boardRow("Groceries")
        let work = boardRow("Work")
        XCTAssertTrue(groceries.waitForExistence(timeout: timeout))
        XCTAssertTrue(work.waitForExistence(timeout: timeout))

        let filterField = app.descendants(matching: .any)[AccessibilityID.sidebarFilterField]
        XCTAssertTrue(filterField.waitForExistence(timeout: timeout))
        filterField.click()
        filterField.typeText("o")

        XCTAssertTrue(poll(timeout: timeout) { groceries.exists && work.exists },
                      "'o' matches both boards; both rows should stay visible")

        // No `until:` postcondition — the drag is EXPECTED to be a no-op, and a postcondition
        // that never turns true would trigger the helper's one retry for nothing.
        drag(work, to: groceries, targetNormalizedOffset: CGVector(dx: 0.5, dy: 0.1))

        // Give a would-be reorder time to land, then assert it never did.
        Thread.sleep(forTimeInterval: 1.0)
        XCTAssertTrue(isAbove(groceries, work),
                      "order must be unchanged — reorder is disabled while filtering")
    }

    // MARK: - Helpers

    private func boardRow(_ name: String) -> XCUIElement {
        app.descendants(matching: .any)[AccessibilityID.board(name)]
    }

    /// Both rows exist and `a`'s top edge is above `b`'s.
    private func isAbove(_ a: XCUIElement, _ b: XCUIElement) -> Bool {
        a.exists && b.exists && a.frame.minY < b.frame.minY
    }
}
