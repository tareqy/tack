import XCTest

/// Board sidebar CRUD: create (from the toolbar button and from the empty state), rename,
/// delete (with confirmation), and filter. Fixture "standard" unless a test states otherwise.
final class BoardCRUDUITests: TackUITestCase {

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

    // MARK: - Create then undo (SwiftData cascade-snapshot probe)

    /// M7 hardening probe (empirically resolved): ⇧⌘N → create "Probe" → ⌘Z. Board creation is a
    /// two-level cascade INSERT (board → 3 lists), so its undo is the inverse cascade delete — the
    /// same shape that crashes SwiftData's undo snapshotting when a user-initiated
    /// `context.delete(board)` runs it (see BoardStore.deleteBoard). This test ran the real app to
    /// settle whether undoing a create is in that crash family. EMPIRICAL RESULT: it is NOT — the
    /// undo cleanly removes the board (an undo of an INSERT replays the manager's recorded inverse
    /// rather than performing a fresh snapshotted cascade delete), the app stays fully responsive,
    /// and zero crash reports are produced. So board creation stays fully undoable (no createBoard
    /// mitigation is applied), and this test asserts full undo plus liveness.
    func testUndoAfterCreateBoardDoesNotCrash() {
        launch(fixture: "standard")
        XCTAssertTrue(boardDetail.waitForExistence(timeout: timeout))

        // ⇧⌘N opens the create sheet; make and confirm "Probe".
        app.typeKey("n", modifierFlags: [.command, .shift])
        XCTAssertTrue(boardNameField.waitForExistence(timeout: timeout), "⇧⌘N should open the new-board sheet")
        boardNameField.click()
        boardNameField.typeText("Probe")
        createBoardConfirmButton.click()

        let probeRow = boardRow("Probe")
        XCTAssertTrue(poll(timeout: timeout) { probeRow.exists }, "board-Probe should appear after create")
        XCTAssertTrue(poll(timeout: timeout) { self.combinedText(self.boardDetail).contains("Probe") },
                      "the new board should be selected/shown before the undo")

        // The critical step: undo the create. Must NOT crash the app.
        app.typeKey("z", modifierFlags: .command)

        // Responsiveness: the app is still running foreground, its window exists, and the sidebar is
        // reachable — a dead app (SwiftData assertion crash) fails all three.
        XCTAssertTrue(poll(timeout: timeout) { self.app.state == .runningForeground },
                      "app must still be running after undoing a create")
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: timeout),
                      "window must still exist after undoing a create")
        XCTAssertTrue(boardRow("Groceries").waitForExistence(timeout: timeout),
                      "sidebar must remain reachable after undoing a create")

        // Full undo: the created board is gone from the sidebar after ⌘Z (empirically safe).
        XCTAssertTrue(poll(timeout: timeout) { !probeRow.exists },
                      "⌘Z should fully undo the create — board-Probe should be gone from the sidebar")
    }

    // MARK: - Rename

    func testRenameBoard() {
        launch(fixture: "standard")

        let workRow = boardRow("Work")
        XCTAssertTrue(workRow.waitForExistence(timeout: timeout))
        workRow.rightClick()
        contextMenuItem("Rename…").click()

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

    /// Regression (realistic input): deleting a board that HAS cards, labels, and due dates —
    /// Groceries (5 cards) — must remove it and leave the app responsive, not trip the known
    /// SwiftData cascade-delete crash class (`BoardStore.deleteBoard` detaches the undo manager to
    /// avoid it). A dead app (assertion crash) fails the responsiveness poll below.
    func testDeleteCardBearingBoardStaysResponsive() {
        launch(fixture: "standard")

        let groceriesRow = boardRow("Groceries")
        XCTAssertTrue(groceriesRow.waitForExistence(timeout: timeout))
        XCTAssertTrue(anyCard("Buy milk").waitForExistence(timeout: timeout),
                      "Groceries' cards should be on screen before the delete")

        groceriesRow.rightClick()
        contextMenuItem("Delete").click()

        let confirmButton = app.descendants(matching: .any)[AccessibilityID.deleteBoardConfirm]
        XCTAssertTrue(confirmButton.waitForExistence(timeout: timeout), "confirmation dialog should appear")
        confirmButton.click()

        XCTAssertTrue(poll(timeout: timeout) { !self.boardRow("Groceries").exists },
                      "Groceries row should be gone after confirmed delete")
        // Responsiveness: still foreground, window present, sidebar reachable (Work survives).
        XCTAssertTrue(poll(timeout: timeout) { self.app.state == .runningForeground },
                      "app must stay running after a card-bearing board delete")
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: timeout),
                      "window must still exist after the delete")
        XCTAssertTrue(boardRow("Work").waitForExistence(timeout: timeout),
                      "sidebar must remain reachable — Work survives")
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

    private func anyCard(_ title: String) -> XCUIElement {
        app.descendants(matching: .any)[AccessibilityID.card(title)]
    }

    private func selectAllAndDelete(_ field: XCUIElement) {
        field.typeKey("a", modifierFlags: .command)
        field.typeKey(.delete, modifierFlags: [])
    }
}
