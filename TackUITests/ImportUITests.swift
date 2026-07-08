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
}
