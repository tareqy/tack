import XCTest

final class SmokeUITests: KanbanUITestCase {
    func testRootViewAppearsOnLaunch() {
        let app = launchApp()
        XCTAssertTrue(app.descendants(matching: .any)[AccessibilityID.rootView].waitForExistence(timeout: 10))
    }
}
