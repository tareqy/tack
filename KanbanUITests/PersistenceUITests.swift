import XCTest

/// Selection and board data must survive a relaunch against the same on-disk store.
final class PersistenceUITests: KanbanUITestCase {

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

    // MARK: - Element lookups

    private var boardDetail: XCUIElement {
        app.descendants(matching: .any)[AccessibilityID.boardDetail]
    }

    private func boardRow(_ name: String) -> XCUIElement {
        app.descendants(matching: .any)[AccessibilityID.board(name)]
    }
}
