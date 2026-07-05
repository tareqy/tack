import XCTest

/// Board sidebar CRUD: create (from the toolbar button and from the empty state), rename,
/// delete (with confirmation), and filter. Fixture "standard" unless a test states otherwise.
final class BoardCRUDUITests: KanbanUITestCase {

    private let timeout: TimeInterval = 15

    // MARK: - Create

    func testCreateBoard() {
        launch(fixture: "standard")

        newBoardButton.click()
        XCTAssertTrue(boardNameField.waitForExistence(timeout: timeout))

        boardNameField.click()
        boardNameField.typeText("Alpha")
        boardEmojiField.click()
        boardEmojiField.typeText("🚀")
        createBoardConfirmButton.click()

        let row = boardRow("Alpha")
        XCTAssertTrue(poll(timeout: timeout) { row.exists }, "board-Alpha row should appear after create")
        // "Selected" is verified via board-detail content (row selection highlighting isn't a
        // reliable XCUITest signal for a SwiftUI List row's combined accessibility element).
        XCTAssertTrue(poll(timeout: timeout) { self.boardDetail.exists && self.combinedText(self.boardDetail).contains("Alpha") },
                      "board-detail should show the newly created board, proving it is selected")
    }

    func testCreateFromEmptyState() {
        launch(fixture: "empty")

        let createFromEmpty = app.descendants(matching: .any)[AccessibilityID.emptyStateCreateBoardButton]
        XCTAssertTrue(createFromEmpty.waitForExistence(timeout: timeout))
        createFromEmpty.click()

        XCTAssertTrue(boardNameField.waitForExistence(timeout: timeout))
        boardNameField.click()
        boardNameField.typeText("First")
        createBoardConfirmButton.click()

        let row = boardRow("First")
        XCTAssertTrue(poll(timeout: timeout) { row.exists }, "board-First row should appear after create")
        XCTAssertTrue(poll(timeout: timeout) { !createFromEmpty.exists }, "empty state should be gone")
    }

    // MARK: - Rename

    func testRenameBoard() {
        launch(fixture: "standard")

        let workRow = boardRow("Work")
        XCTAssertTrue(workRow.waitForExistence(timeout: timeout))
        workRow.rightClick()
        contextMenuItem("Rename").click()

        XCTAssertTrue(renameBoardField.waitForExistence(timeout: timeout))
        renameBoardField.click()
        // Clear the pre-filled "Work" text before typing the new name.
        selectAllAndDelete(renameBoardField)
        renameBoardField.typeText("Work II")
        renameBoardConfirmButton.click()

        XCTAssertTrue(poll(timeout: timeout) { self.boardRow("Work II").exists },
                      "board-Work II row should appear after rename")
        XCTAssertFalse(boardRow("Work").exists, "old board-Work row should be gone")
    }

    // MARK: - Delete

    func testDeleteRequiresConfirmationAndCancelLeavesItIntact() {
        launch(fixture: "standard")

        let workRow = boardRow("Work")
        XCTAssertTrue(workRow.waitForExistence(timeout: timeout))
        workRow.rightClick()
        contextMenuItem("Delete").click()

        // Not `app.dialogs.buttons[...]` (never matches — see `hittableButton`'s doc) and not a
        // bare `app.buttons["Cancel"]` either (matches more than one "Cancel"-titled button in the
        // window/menu structure); `hittableButton` disambiguates to the one on-screen right now.
        let cancelButton = hittableButton("Cancel")
        XCTAssertTrue(cancelButton.exists, "confirmation dialog should appear")
        cancelButton.click()

        XCTAssertTrue(poll(timeout: timeout) { self.boardRow("Work").exists },
                      "cancel should leave board-Work in place")
    }

    func testDeleteConfirmedRemovesTheRow() {
        launch(fixture: "standard")

        let workRow = boardRow("Work")
        XCTAssertTrue(workRow.waitForExistence(timeout: timeout))
        workRow.rightClick()
        contextMenuItem("Delete").click()

        let confirmButton = app.descendants(matching: .any)[AccessibilityID.deleteBoardConfirm]
        XCTAssertTrue(confirmButton.waitForExistence(timeout: timeout), "confirmation dialog should appear")
        confirmButton.click()

        XCTAssertTrue(poll(timeout: timeout) { !self.boardRow("Work").exists },
                      "board-Work row should be gone after confirmed delete")
    }

    // MARK: - Filter

    func testFilter() {
        launch(fixture: "standard")

        let groceriesRow = boardRow("Groceries")
        let workRow = boardRow("Work")
        XCTAssertTrue(groceriesRow.waitForExistence(timeout: timeout))
        XCTAssertTrue(workRow.waitForExistence(timeout: timeout))

        let filterField = app.descendants(matching: .any)[AccessibilityID.sidebarFilterField]
        XCTAssertTrue(filterField.waitForExistence(timeout: timeout))
        filterField.click()
        filterField.typeText("gro")

        XCTAssertTrue(poll(timeout: timeout) { groceriesRow.exists && !workRow.exists },
                      "only board-Groceries should be visible while filtering by 'gro'")

        selectAllAndDelete(filterField)

        XCTAssertTrue(poll(timeout: timeout) { groceriesRow.exists && workRow.exists },
                      "clearing the filter should show both boards again")
    }

    // MARK: - Element lookups

    private var newBoardButton: XCUIElement {
        app.descendants(matching: .any)[AccessibilityID.newBoardButton]
    }

    private var boardNameField: XCUIElement {
        app.descendants(matching: .any)[AccessibilityID.boardNameField]
    }

    private var boardEmojiField: XCUIElement {
        app.descendants(matching: .any)[AccessibilityID.boardEmojiField]
    }

    private var createBoardConfirmButton: XCUIElement {
        app.descendants(matching: .any)[AccessibilityID.createBoardConfirm]
    }

    private var renameBoardField: XCUIElement {
        app.descendants(matching: .any)[AccessibilityID.renameBoardField]
    }

    private var renameBoardConfirmButton: XCUIElement {
        app.descendants(matching: .any)[AccessibilityID.renameBoardConfirm]
    }

    private var boardDetail: XCUIElement {
        app.descendants(matching: .any)[AccessibilityID.boardDetail]
    }

    private func boardRow(_ name: String) -> XCUIElement {
        app.descendants(matching: .any)[AccessibilityID.board(name)]
    }

    private func selectAllAndDelete(_ field: XCUIElement) {
        field.typeKey("a", modifierFlags: .command)
        field.typeKey(.delete, modifierFlags: [])
    }
}
