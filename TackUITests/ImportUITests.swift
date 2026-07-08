import XCTest

/// E-02 JSON import. The production open panel is a sandboxed, remote-hosted NSOpenPanel that
/// XCUITest cannot drive (same class as E-01's save panel), and the sandboxed runner cannot place
/// files inside the app container — so content e2es (Task 7) use the --import-from launch hook,
/// with the app exporting its own input first via --export-to. This file starts with the two
/// panel-free legs: menu discoverability/enablement and the empty-state affordance.
final class ImportUITests: TackUITestCase {

    private let timeout: TimeInterval = 15

    private var rootView: XCUIElement { app.descendants(matching: .any)[AccessibilityID.rootView] }
    private var boardDetail: XCUIElement { app.descendants(matching: .any)[AccessibilityID.boardDetail] }

    func testImportMenuItemExistsAndEnabledOnBothFixtures() {
        // Unlike Export (disabled at zero boards), Import is enabled EVERYWHERE — restore into an
        // empty app is its headline case.
        launch(fixture: "empty")
        XCTAssertTrue(rootView.waitForExistence(timeout: timeout))
        openMenu("File")
        let importItem = menuItem("Import Boards…")
        XCTAssertTrue(importItem.waitForExistence(timeout: timeout), "File ▸ Import Boards… should exist")
        XCTAssertTrue(importItem.isEnabled, "Import should be enabled with zero boards")
        closeMenu()

        app.terminate()
        launch(fixture: "standard")
        XCTAssertTrue(boardDetail.waitForExistence(timeout: timeout))
        openMenu("File")
        XCTAssertTrue(menuItem("Import Boards…").waitForExistence(timeout: timeout))
        XCTAssertTrue(menuItem("Import Boards…").isEnabled, "Import should be enabled with boards present")
        closeMenu()
    }

    func testEmptyStateShowsImportButton() {
        launch(fixture: "empty")
        let importButton = app.buttons[AccessibilityID.emptyStateImportButton]
        XCTAssertTrue(importButton.waitForExistence(timeout: timeout),
                      "the zero-board empty state should offer Import from Backup…")
        // Presence-only: clicking would open the un-drivable NSOpenPanel.
    }

    // MARK: - Content e2es (via --export-to → --import-from; the panel itself is un-drivable)

    private var importMarker: XCUIElement {
        app.descendants(matching: .any)[AccessibilityID.importSelfCheck]
    }
    private var exportMarker: XCUIElement {
        app.descendants(matching: .any)[AccessibilityID.exportSelfCheck]
    }

    private func markerValue(_ marker: XCUIElement) -> String? { marker.value as? String }

    /// Launches the standard fixture with --export-to and waits until the export JSON is written
    /// (the export marker publishing IS the write-complete signal), then terminates.
    private func exportStandardFixture(to filename: String) {
        launch(fixture: "standard", exportTo: filename)
        XCTAssertTrue(poll(timeout: timeout) { exportMarker.exists && markerValue(exportMarker)?.isEmpty == false },
                      "export self-check should publish before we relaunch to import")
        app.terminate()
    }

    func testImportRoundTripRestoresBackup() {
        exportStandardFixture(to: "import-roundtrip.json")

        // Same auto-derived store name; --reset wipes only the sqlite files — the JSON survives.
        launch(fixture: "empty", importFrom: "import-roundtrip.json")

        XCTAssertTrue(poll(timeout: timeout) { importMarker.exists }, "import marker should publish")
        XCTAssertEqual(markerValue(importMarker), "ok|Groceries,Work|Buy milk,Call plumber,Return library books",
                       "live post-import store state should match the exported fixture")
        XCTAssertTrue(app.descendants(matching: .any)[AccessibilityID.board("Groceries")].waitForExistence(timeout: timeout))
        XCTAssertTrue(app.descendants(matching: .any)[AccessibilityID.board("Work")].exists)
        // Post-import selection: the first imported board is shown in the detail pane.
        let detail = app.descendants(matching: .any)[AccessibilityID.boardDetail]
        XCTAssertTrue(poll(timeout: timeout) { detail.exists && combinedText(detail).contains("Groceries") },
                      "the first imported board should be selected after import")

        // Persistence leg: relaunchPreservingStore re-passes neither import flag (by design), and
        // FixtureSeeder skips non-empty stores — so the boards must come from the persisted store.
        relaunchPreservingStore()
        XCTAssertTrue(app.descendants(matching: .any)[AccessibilityID.board("Groceries")].waitForExistence(timeout: timeout),
                      "imported boards should survive a relaunch")
    }

    func testReplaceModeReplacesExistingBoards() {
        exportStandardFixture(to: "import-replace.json")

        // Import the standard fixture's own export INTO the standard fixture, replace mode.
        launch(fixture: "standard", importFrom: "import-replace.json", importMode: "replace")

        XCTAssertTrue(poll(timeout: timeout) { importMarker.exists })
        XCTAssertEqual(markerValue(importMarker), "ok|Groceries,Work|Buy milk,Call plumber,Return library books",
                       "exactly the two imported boards — replace, not append (append would list four)")
        // Duplicate-count oracle: after replace exactly ONE row per name (append would show two).
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: AccessibilityID.board("Groceries")).count, 1)
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: AccessibilityID.board("Work")).count, 1)
        // Replace is never undoable and clears the stack.
        openMenu("Edit")
        let undoItem = app.menuBars.menuItems.matching(NSPredicate(format: "title BEGINSWITH 'Undo'")).firstMatch
        XCTAssertTrue(undoItem.waitForExistence(timeout: timeout))
        XCTAssertFalse(undoItem.isEnabled, "Edit ▸ Undo should be disabled after a replace import")
        closeMenu()
    }

    func testImportMissingFilePublishesErrorAndChangesNothing() {
        launch(fixture: "standard", importFrom: "does-not-exist.json")

        XCTAssertTrue(poll(timeout: timeout) { importMarker.exists })
        XCTAssertEqual(markerValue(importMarker), "error|unreadable",
                       "stable token, never localized alert copy")
        // The production error alert also presented — dismiss it, then confirm nothing changed.
        let ok = hittableButton("OK")
        XCTAssertTrue(ok.waitForExistence(timeout: timeout), "the Import Failed alert should present")
        ok.click()
        XCTAssertTrue(app.descendants(matching: .any)[AccessibilityID.board("Groceries")].waitForExistence(timeout: timeout))
        XCTAssertTrue(app.descendants(matching: .any)[AccessibilityID.board("Work")].exists)
    }

    func testImportDialogCancelDoesNothing() {
        exportStandardFixture(to: "import-cancel.json")

        // ask-mode presents the REAL mode dialog; drive its Cancel with the harness helper built
        // for confirmationDialog buttons.
        launch(fixture: "standard", importFrom: "import-cancel.json", importMode: "ask")

        let cancel = hittableButton("Cancel")
        XCTAssertTrue(cancel.waitForExistence(timeout: timeout), "the mode dialog should present under ask")
        cancel.click()

        XCTAssertTrue(poll(timeout: timeout) { markerValue(importMarker) == "cancelled" })
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: AccessibilityID.board("Groceries")).count, 1,
                       "cancel imports nothing — no duplicate rows")
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: AccessibilityID.board("Work")).count, 1)
    }

    // MARK: - Text-input guard (mouse path)

    /// Ship-gate regression: Export/Import route their actions through `guardedMutation`, which
    /// silently no-ops while a tagged text input has focus (the M7 guard) — but until now neither
    /// item's `.disabled(...)` included that check, so a click while e.g. the sidebar filter was
    /// focused looked enabled and did nothing. Mirrors the Delete Card / Open Card / Move Card /
    /// Filter by Label items, which already pair the guard with `isTextInputActive`.
    func testImportExportGrayOutWhileTyping() {
        launch(fixture: "standard")
        XCTAssertTrue(boardDetail.waitForExistence(timeout: timeout))

        // Focus the sidebar filter — a reportsTextInputFocus()-tagged field.
        let filter = app.textFields[AccessibilityID.sidebarFilterField]
        XCTAssertTrue(filter.waitForExistence(timeout: timeout))
        filter.click()

        openMenu("File")
        XCTAssertFalse(menuItem("Import Boards…").isEnabled, "Import should gray out while typing")
        XCTAssertFalse(menuItem("Export All Boards…").isEnabled, "Export should gray out while typing")
        closeMenu()

        // Move focus out of the field. Clicking `board-detail` (a plain Text header, no AppKit
        // control underneath) does NOT resign the field editor — verified on this host, the menu
        // items stayed disabled afterward. A sidebar board row IS backed by an AppKit NSTableView
        // (List selection), whose click handling reliably calls makeFirstResponder(tableView),
        // which does resign the TextField. Same row-click pattern CardCRUDUITests/
        // DragAndDropUITests/PersistenceUITests/ThemeUITests use to interact with these boards.
        let workRow = app.descendants(matching: .any)[AccessibilityID.board("Work")]
        XCTAssertTrue(workRow.waitForExistence(timeout: timeout))
        workRow.click()

        openMenu("File")
        XCTAssertTrue(menuItem("Import Boards…").waitForExistence(timeout: timeout))
        XCTAssertTrue(menuItem("Import Boards…").isEnabled, "Import should re-enable once typing ends")
        XCTAssertTrue(menuItem("Export All Boards…").isEnabled, "Export should re-enable once typing ends")
        closeMenu()
    }
}
