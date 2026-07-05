import XCTest

/// The M2 exit-gate tests: prove a real SwiftUI drag driven by XCUITest reorders and cross-moves
/// cards, and that the result survives a relaunch (real on-disk persistence).
final class DragAndDropUITests: KanbanUITestCase {

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

    private func expected(_ titles: String...) -> [String] {
        titles.map(AccessibilityID.card)
    }
}
