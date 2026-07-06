import XCTest

/// M10 exit-gate tests for due-date urgency colors (D-03): the fixture's four dated cards expose
/// the right `|status` suffix on their `DueDateBadge` accessibility value (extended this milestone
/// from a bare ISO date to `"<iso>|<status>"` — see `DueDateBadge.body`), the fifth (no due date)
/// shows no badge at all (D-02), and the app stays fully functional — badges still compute
/// correctly, card creation still works — under a forced dark appearance (`--appearance dark`,
/// plumbed through `AppLaunchConfig`/`KanbanApp` since `defaults write -app` doesn't reach a
/// sandboxed UI-test process). Visual color/contrast quality is verified separately by screenshot
/// inspection (see the task-12 report's audit table), NOT by pixel assertions here.
///
/// Fixture "standard" (board Groceries): To Do = [Buy milk (yesterday/overdue), Call plumber
/// (today), Return library books (tomorrow)], In Progress = [Write report (+5d/upcoming)], Done =
/// [Book flights (no due date)].
final class BadgeUITests: KanbanUITestCase {

    private let timeout: TimeInterval = 15

    func testUrgencyBadgeValues() {
        launch(fixture: "standard")

        assertBadgeSuffix("Buy milk", suffix: "overdue")
        assertBadgeSuffix("Call plumber", suffix: "today")
        assertBadgeSuffix("Return library books", suffix: "tomorrow")
        assertBadgeSuffix("Write report", suffix: "upcoming")

        XCTAssertFalse(element(AccessibilityID.dueDateBadge(card: "Book flights")).exists,
                       "a card with no due date must show no badge at all (PRD D-02)")
    }

    /// Proves the `--appearance dark` plumbing works and nothing crashes under it: badge urgency
    /// (a pure function of the date, independent of appearance) is still correct, and a basic
    /// mutation (card creation) still succeeds. Visual dark-mode quality itself is covered by the
    /// screenshot inspection in the task-12 report, not by assertions here.
    func testDarkModeSmoke() {
        launch(fixture: "standard", appearance: "dark")

        assertBadgeSuffix("Buy milk", suffix: "overdue")
        assertBadgeSuffix("Call plumber", suffix: "today")
        assertBadgeSuffix("Return library books", suffix: "tomorrow")
        assertBadgeSuffix("Write report", suffix: "upcoming")
        XCTAssertFalse(element(AccessibilityID.dueDateBadge(card: "Book flights")).exists,
                       "no-due-date card still shows no badge under a forced dark appearance")

        let toDo = element(AccessibilityID.list("To Do"))
        XCTAssertTrue(toDo.waitForExistence(timeout: timeout))
        let addButton = element(AccessibilityID.addCardButton(list: "To Do"))
        XCTAssertTrue(addButton.waitForExistence(timeout: timeout))
        addButton.click()

        let field = element(AccessibilityID.newCardField)
        XCTAssertTrue(field.waitForExistence(timeout: timeout), "add-card field should open")
        field.click()
        field.typeText("Dark mode card")
        field.typeKey(.enter, modifierFlags: [])

        XCTAssertTrue(poll(timeout: timeout) { self.anyCard("Dark mode card").exists },
                      "card creation should still work under a forced dark appearance")
    }

    // MARK: - Helpers

    private func assertBadgeSuffix(_ cardTitle: String, suffix: String) {
        let badge = element(AccessibilityID.dueDateBadge(card: cardTitle))
        XCTAssertTrue(badge.waitForExistence(timeout: timeout), "due-date badge for \(cardTitle) should exist")
        let value = badge.value as? String ?? ""
        XCTAssertTrue(value.hasSuffix("|\(suffix)"),
                      "expected \(cardTitle)'s badge value '\(value)' to end with |\(suffix)")
    }

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

    private func anyCard(_ title: String) -> XCUIElement {
        app.descendants(matching: .any)[AccessibilityID.card(title)]
    }
}
