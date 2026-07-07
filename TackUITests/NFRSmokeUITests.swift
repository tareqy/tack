import XCTest

/// N-04/N-05 responsiveness smoke on the "large" fixture (1 board, 3 lists, 500 cards): the app
/// launches, the board renders, a card selects on click, and the board scrolls. A FUNCTIONAL smoke
/// — it guards against a hang/crash/unresponsiveness at scale, deliberately with NO timing
/// assertions (no latency bound is asserted, only that these interactions complete).
final class NFRSmokeUITests: TackUITestCase {

    private let timeout: TimeInterval = 30

    func testLargeBoardLaunchesScrollsAndSelects() {
        launch(fixture: "large")

        let boardDetail = app.descendants(matching: .any)[AccessibilityID.boardDetail]
        XCTAssertTrue(boardDetail.waitForExistence(timeout: timeout), "the large board should render on launch")
        XCTAssertTrue(poll(timeout: timeout) { self.combinedText(boardDetail).contains("Large") },
                      "the Large board should be shown")

        // Selection responds at scale: a top-of-list card selects on click. ("Card 0001" is the
        // first card of the first list — see FixtureSeeder.seedLarge.)
        let firstCard = card("Card 0001")
        XCTAssertTrue(firstCard.waitForExistence(timeout: timeout), "Card 0001 should exist")
        firstCard.click()
        XCTAssertTrue(poll(timeout: timeout) { self.card("Card 0001").isSelected },
                      "clicking a card should select it")

        // The board scrolls without hanging (functional check only).
        let toDo = app.descendants(matching: .any)[AccessibilityID.list("To Do")]
        XCTAssertTrue(toDo.waitForExistence(timeout: timeout))
        toDo.swipeUp()

        // Still responsive after the scroll.
        XCTAssertEqual(app.state, .runningForeground, "app should remain responsive after scrolling a large board")
        XCTAssertTrue(boardDetail.exists, "the board should still be present after scrolling")
    }

    private func card(_ title: String) -> XCUIElement {
        app.descendants(matching: .any)[AccessibilityID.card(title)]
    }
}
