import XCTest

/// E-01 JSON export (PRD §4.6 / §9.6). Two angles:
///  1. the File ▸ "Export All Boards…" (⇧⌘E) menu item is present + correctly enabled/disabled;
///  2. the export actually produces a well-formed, decodable JSON file whose CONTENT matches the
///     seeded fixture (board names/order, list names, card titles).
///
/// The production export runs through a sandboxed, remote-hosted `NSSavePanel` that XCUITest can't
/// reliably drive, AND the UI-test runner is itself sandboxed (so it can't read the app's own
/// container file). So the content assertion uses the `--export-to` launch hook: the app encodes
/// the boards through the production `ExportDocument` path, WRITES the JSON to disk, READS it back,
/// DECODES it, and publishes the decoded content via an accessibility marker. The test asserts that
/// published summary against the fixture — a real write→disk→decode round trip, not existence-only.
final class ExportUITests: TackUITestCase {

    private let timeout: TimeInterval = 15

    // MARK: - Menu item discoverability + enablement

    func testExportMenuItemExistsAndEnabled() {
        launch(fixture: "standard")
        XCTAssertTrue(boardDetail.waitForExistence(timeout: timeout))

        openMenu("File")
        let export = menuItem("Export All Boards…")
        XCTAssertTrue(export.waitForExistence(timeout: timeout), "File ▸ Export All Boards… should exist")
        XCTAssertTrue(export.isEnabled, "Export should be enabled while boards exist")
        closeMenu()

        // No boards → the item is present but disabled.
        app.terminate()
        launch(fixture: "empty")
        XCTAssertTrue(rootView.waitForExistence(timeout: timeout))
        openMenu("File")
        XCTAssertTrue(menuItem("Export All Boards…").waitForExistence(timeout: timeout))
        XCTAssertFalse(menuItem("Export All Boards…").isEnabled, "Export should be disabled with no boards")
        closeMenu()
    }

    // MARK: - Real content written + decodable

    func testExportWritesDecodableJSON() {
        launch(fixture: "standard", exportTo: "export-e2e.json")
        XCTAssertTrue(boardDetail.waitForExistence(timeout: timeout))

        // The app wrote the export to disk, read it back, and decoded it; the marker carries the
        // decoded "<board names>|<To Do card titles>" summary. Assert it matches the fixture.
        let marker = app.descendants(matching: .any)[AccessibilityID.exportSelfCheck]
        XCTAssertTrue(poll(timeout: timeout) { marker.exists && (marker.value as? String)?.isEmpty == false },
                      "the export self-check marker should publish the decoded content")

        let summary = marker.value as? String
        XCTAssertEqual(summary, "Groceries,Work|Buy milk,Call plumber,Return library books",
                       "the written-then-decoded export should contain both boards in order and Groceries' To Do cards")
    }

    // MARK: - Helpers

    private var rootView: XCUIElement { app.descendants(matching: .any)[AccessibilityID.rootView] }
    private var boardDetail: XCUIElement { app.descendants(matching: .any)[AccessibilityID.boardDetail] }
}
