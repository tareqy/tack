import XCTest

/// M8 exit-gate tests for board themes: preset selection + persistence, custom hex commit +
/// persistence, and invalid-hex rejection. Fixture "standard" (boards Groceries [position 0] and
/// Work [position 1], both created with the schema default theme "default").
final class ThemeUITests: KanbanUITestCase {

    private let timeout: TimeInterval = 15

    func testPresetThemePersists() {
        launch(fixture: "standard")

        let groceriesRow = boardRow("Groceries")
        XCTAssertTrue(groceriesRow.waitForExistence(timeout: timeout))
        groceriesRow.click()

        XCTAssertTrue(poll(timeout: timeout) { self.themeValue.exists && self.themeValue.value as? String == "default" },
                      "Groceries should start on the default theme")

        openThemePopover()
        themeSwatch("ocean").click()

        XCTAssertTrue(poll(timeout: timeout) { self.themeValue.value as? String == "ocean" },
                      "board-theme-value should read 'ocean' right after picking the swatch")

        app.typeKey(.escape, modifierFlags: []) // close the popover

        // Work board (position 1) must be unaffected — switching boards switches the value back.
        let workRow = boardRow("Work")
        XCTAssertTrue(workRow.waitForExistence(timeout: timeout))
        workRow.click()
        XCTAssertTrue(poll(timeout: timeout) { self.themeValue.value as? String == "default" },
                      "Work board should still be on the default theme")

        groceriesRow.click()
        XCTAssertTrue(poll(timeout: timeout) { self.themeValue.value as? String == "ocean" },
                      "Groceries should show ocean again after switching back")

        relaunchPreservingStore()

        groceriesRow.click()
        XCTAssertTrue(poll(timeout: timeout) { self.themeValue.value as? String == "ocean" },
                      "ocean theme should persist across relaunch")
    }

    func testCustomHexTheme() {
        launch(fixture: "standard")

        let groceriesRow = boardRow("Groceries")
        XCTAssertTrue(groceriesRow.waitForExistence(timeout: timeout))
        groceriesRow.click()

        openThemePopover()
        let hexField = element(AccessibilityID.themeHexField)
        XCTAssertTrue(hexField.waitForExistence(timeout: timeout))
        hexField.click()
        hexField.typeText("#3A5F8F")
        hexField.typeKey(.enter, modifierFlags: [])

        XCTAssertTrue(poll(timeout: timeout) { self.themeValue.value as? String == "custom:3A5F8F" },
                      "board-theme-value should read 'custom:3A5F8F' after committing the hex field")

        app.typeKey(.escape, modifierFlags: []) // close the popover
        relaunchPreservingStore()

        groceriesRow.click()
        XCTAssertTrue(poll(timeout: timeout) { self.themeValue.value as? String == "custom:3A5F8F" },
                      "custom hex theme should persist across relaunch")
    }

    func testInvalidHexRejected() {
        launch(fixture: "standard")

        let groceriesRow = boardRow("Groceries")
        XCTAssertTrue(groceriesRow.waitForExistence(timeout: timeout))
        groceriesRow.click()

        XCTAssertTrue(poll(timeout: timeout) { self.themeValue.value as? String == "default" })

        openThemePopover()
        let hexField = element(AccessibilityID.themeHexField)
        XCTAssertTrue(hexField.waitForExistence(timeout: timeout))
        hexField.click()
        hexField.typeText("zzz")
        hexField.typeKey(.enter, modifierFlags: [])

        // No crash, no commit: value stays "default".
        XCTAssertTrue(poll(timeout: timeout) { self.themeValue.value as? String == "default" },
                      "invalid hex must not change the theme value")
        XCTAssertTrue(app.exists, "app must not have crashed")
    }

    // MARK: - Helpers

    private func openThemePopover() {
        let button = element(AccessibilityID.themeButton)
        XCTAssertTrue(button.waitForExistence(timeout: timeout), "theme-button should exist once a board is selected")
        button.click()
        XCTAssertTrue(poll(timeout: timeout) { self.themeSwatch("ocean").exists },
                      "theme popover should be open (ocean swatch visible)")
    }

    private func themeSwatch(_ name: String) -> XCUIElement {
        element(AccessibilityID.themeSwatch(name))
    }

    private var themeValue: XCUIElement {
        element(AccessibilityID.boardThemeValue)
    }

    private func boardRow(_ name: String) -> XCUIElement {
        app.descendants(matching: .any)[AccessibilityID.board(name)]
    }

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }
}
