import XCTest

class KanbanUITestCase: XCTestCase {
    func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--uitest"]
        app.launch()
        return app
    }
}
