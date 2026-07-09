import XCTest

/// M-F Areas e2e — all MOUSE-driven (context menus + clicks; the proven submenu pattern from
/// CardCRUDUITests.testMoveViaContextMenu), so none of it is exposed to the environmental
/// keyboard/menu failure mode. Section order is asserted by frame minY (rows/headers never
/// overlap — the SidebarReorderUITests convention). Within-section drag reorder is deliberately
/// NOT e2e-tested (B-06: native List .onMove cannot be driven by synthetic input; unit-covered
/// by Reordering/BoardStore, human-verified per the PRD §9.8 manual procedure).
final class AreaUITests: TackUITestCase {

    private let timeout: TimeInterval = 15

    private func boardRow(_ name: String) -> XCUIElement {
        app.descendants(matching: .any)[AccessibilityID.board(name)]
    }
    private func areaHeader(_ name: String) -> XCUIElement {
        app.descendants(matching: .any)[AccessibilityID.area(name)]
    }
    private func isAbove(_ a: XCUIElement, _ b: XCUIElement) -> Bool {
        a.exists && b.exists && a.frame.minY < b.frame.minY
    }
    private func clearAndType(_ field: XCUIElement, _ text: String) {
        field.click()
        field.typeKey("a", modifierFlags: .command)
        field.typeKey(.delete, modifierFlags: [])
        field.typeText(text)
    }

    func testStandardFixtureGroupsWorkUnderOffice() {
        launch(fixture: "standard")

        let office = areaHeader("Office")
        XCTAssertTrue(office.waitForExistence(timeout: timeout), "the fixture seeds area Office")
        XCTAssertTrue(boardRow("Work").waitForExistence(timeout: timeout), "Office is expanded at seed")
        XCTAssertTrue(isAbove(boardRow("Groceries"), office),
                      "ungrouped boards render FIRST, headerless — the pre-M-F look above the sections")
        XCTAssertTrue(isAbove(office, boardRow("Work")), "Work renders under its area header")
    }

    func testMoveBoardToAreaViaContextMenuPersists() {
        launch(fixture: "standard")

        let groceries = boardRow("Groceries")
        XCTAssertTrue(groceries.waitForExistence(timeout: timeout))
        groceries.rightClick()
        contextMenuItem("Move to Area").click() // open the submenu (the Move to List pattern)
        contextMenuItem("Office").click()

        XCTAssertTrue(poll(timeout: timeout) { self.isAbove(self.areaHeader("Office"), self.boardRow("Groceries")) },
                      "Groceries should now render under the Office header")

        relaunchPreservingStore()

        XCTAssertTrue(areaHeader("Office").waitForExistence(timeout: timeout))
        XCTAssertTrue(poll(timeout: timeout) { self.isAbove(self.areaHeader("Office"), self.boardRow("Groceries")) },
                      "membership persists across relaunch")
    }

    func testNewAreaViaContextMenuCreatesAndMoves() {
        launch(fixture: "standard")

        boardRow("Groceries").rightClick()
        contextMenuItem("Move to Area").click()
        contextMenuItem("New Area…").click()

        let field = app.descendants(matching: .any)[AccessibilityID.areaNameField]
        XCTAssertTrue(field.waitForExistence(timeout: timeout), "the New Area sheet should present")
        field.click()
        field.typeText("Home")
        app.descendants(matching: .any)[AccessibilityID.areaSheetConfirm].click()

        XCTAssertTrue(poll(timeout: timeout) { self.areaHeader("Home").exists },
                      "the new area's header should appear")
        XCTAssertTrue(poll(timeout: timeout) { self.isAbove(self.areaHeader("Home"), self.boardRow("Groceries")) },
                      "the board that spawned the area lands inside it — one gesture")
        XCTAssertTrue(areaHeader("Office").exists, "the fixture area is untouched")
    }

    func testNoAreaReleasesBoardViaContextMenu() {
        launch(fixture: "standard")

        boardRow("Work").rightClick()
        contextMenuItem("Move to Area").click()
        contextMenuItem("No Area").click()

        XCTAssertTrue(poll(timeout: timeout) { self.isAbove(self.boardRow("Work"), self.areaHeader("Office")) },
                      "released boards rejoin the headerless ungrouped run above the sections")
        XCTAssertTrue(areaHeader("Office").exists, "the emptied area survives — deletion is explicit")
    }

    func testCollapseHidesRowsPersistsAndExpands() {
        launch(fixture: "standard")

        let office = areaHeader("Office")
        XCTAssertTrue(office.waitForExistence(timeout: timeout))
        office.rightClick()
        contextMenuItem("Collapse Area").click()

        XCTAssertTrue(poll(timeout: timeout) { !self.boardRow("Work").exists },
                      "a collapsed area's rows are gone from the tree, not just dimmed")
        XCTAssertTrue(boardRow("Groceries").exists, "ungrouped rows are unaffected")

        relaunchPreservingStore()

        XCTAssertTrue(areaHeader("Office").waitForExistence(timeout: timeout))
        XCTAssertFalse(boardRow("Work").exists, "collapse is MODEL state — it persists")

        app.descendants(matching: .any)[AccessibilityID.areaToggle("Office")].click()
        XCTAssertTrue(poll(timeout: timeout) { self.boardRow("Work").exists },
                      "the chevron expands (the second affordance beside the context menu)")
    }

    func testRestoreIntoCollapsedAreaAutoExpands() {
        launch(fixture: "standard")

        let work = boardRow("Work")
        XCTAssertTrue(work.waitForExistence(timeout: timeout))
        work.click() // select Work — persisted via the selection triad

        areaHeader("Office").rightClick()
        contextMenuItem("Collapse Area").click()
        XCTAssertTrue(poll(timeout: timeout) { !self.boardRow("Work").exists })

        relaunchPreservingStore()

        // Restore re-selects Work → RootView's auto-expand (design (c)) expands Office.
        XCTAssertTrue(poll(timeout: timeout) { self.boardRow("Work").exists },
                      "restoring a selection inside a collapsed area must auto-expand it")
    }

    func testDeleteAreaReleasesBoards() {
        launch(fixture: "standard")

        areaHeader("Office").rightClick()
        contextMenuItem("Delete Area…").click()

        let confirm = app.descendants(matching: .any)[AccessibilityID.deleteAreaConfirm]
        XCTAssertTrue(confirm.waitForExistence(timeout: timeout), "area delete is confirmation-gated")
        confirm.click()

        XCTAssertTrue(poll(timeout: timeout) { !self.areaHeader("Office").exists })
        XCTAssertTrue(boardRow("Work").waitForExistence(timeout: timeout),
                      "nullify: the board SURVIVES its area, released to the ungrouped run")

        relaunchPreservingStore()
        XCTAssertTrue(boardRow("Work").waitForExistence(timeout: timeout))
        XCTAssertFalse(areaHeader("Office").exists)
    }

    func testRenameAreaViaSheet() {
        launch(fixture: "standard")

        areaHeader("Office").rightClick()
        contextMenuItem("Rename Area…").click()

        let field = app.descendants(matching: .any)[AccessibilityID.areaNameField]
        XCTAssertTrue(field.waitForExistence(timeout: timeout))
        XCTAssertEqual(field.value as? String, "Office", "rename seeds the current name")
        clearAndType(field, "Studio")
        app.descendants(matching: .any)[AccessibilityID.areaSheetConfirm].click()

        XCTAssertTrue(poll(timeout: timeout) { self.areaHeader("Studio").exists })
        XCTAssertFalse(areaHeader("Office").exists)
        XCTAssertTrue(isAbove(areaHeader("Studio"), boardRow("Work")), "membership survives a rename")
    }

    func testFilterShowsFlatListIncludingCollapsedAreas() {
        launch(fixture: "standard")

        areaHeader("Office").rightClick()
        contextMenuItem("Collapse Area").click()
        XCTAssertTrue(poll(timeout: timeout) { !self.boardRow("Work").exists })

        let filterField = app.descendants(matching: .any)[AccessibilityID.sidebarFilterField]
        filterField.click()
        filterField.typeText("Work")

        XCTAssertTrue(poll(timeout: timeout) { self.boardRow("Work").exists },
                      "filtering is FLAT and searches ALL boards — collapse must not hide matches")
        XCTAssertFalse(areaHeader("Office").exists, "no headers while filtering (the flat branch)")

        // Clear the filter (select-all + delete — no Esc: the scene-wide Esc dispatch is
        // LabelFilterUITests' turf, not this test's).
        filterField.typeKey("a", modifierFlags: .command)
        filterField.typeKey(.delete, modifierFlags: [])

        XCTAssertTrue(poll(timeout: timeout) { self.areaHeader("Office").exists },
                      "clearing the filter restores the sectioned view")
        XCTAssertFalse(boardRow("Work").exists, "…with Office still collapsed — filtering never mutates state")
    }
}
