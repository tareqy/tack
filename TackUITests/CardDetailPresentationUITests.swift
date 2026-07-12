import XCTest

/// End-to-end coverage for the app-wide card-detail presentation preference. Existing
/// `CardDetailUITests` continue to pin the default sheet in depth; this suite exercises the
/// native side panel, its nonmodal transition rules, and every board surface routed through
/// RootView's single ID-based presenter.
final class CardDetailPresentationUITests: TackUITestCase {
    private let timeout: TimeInterval = 15

    func testFreshLaunchStillUsesSheetByDefault() {
        launch(fixture: "standard")

        openBoardCard("Call plumber")

        XCTAssertEqual(presentationValue(), "sheet")
        XCTAssertFalse(inspectorMarker.exists, "fresh installs must keep the established sheet default")
        XCTAssertTrue((450...480).contains(detailEditor.frame.width),
                      "default sheet geometry must remain unchanged")
    }

    func testSidePanelIsTrailingNonmodalAndPreferenceAndSavePersistAcrossRelaunch() {
        launch(fixture: "standard", cardDetailPresentation: "side-panel")

        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: timeout))
        openBoardCard("Call plumber")
        assertSidePanel()

        let panelFrame = detailEditor.frame
        XCTAssertTrue((330...530).contains(panelFrame.width),
                      "inspector width should stay inside its 340/380/520 contract, got \(panelFrame.width)")
        XCTAssertGreaterThan(panelFrame.midX, window.frame.midX,
                             "card details should occupy the window's trailing side")
        XCTAssertGreaterThanOrEqual(panelFrame.maxX, window.frame.maxX - 60,
                                    "inspector should be anchored to the trailing window edge")
        XCTAssertTrue(anyCard("Buy milk").isHittable,
                      "the board must remain visible and interactive beside the nonmodal inspector")

        let brief = element(AccessibilityID.cardDetailDescriptionField)
        brief.click()
        brief.typeText("Saved from the side panel")
        hittableButton("Save").click()
        XCTAssertTrue(poll(timeout: timeout) { !self.detailEditor.exists })

        openBoardCard("Call plumber")
        XCTAssertEqual(element(AccessibilityID.cardDetailDescriptionField).value as? String,
                       "Saved from the side panel")
        hittableButton("Cancel").click()

        relaunchPreservingStore()
        openBoardCard("Call plumber")
        assertSidePanel()
        XCTAssertEqual(element(AccessibilityID.cardDetailDescriptionField).value as? String,
                       "Saved from the side panel",
                       "both the preference and saved card edit should survive relaunch")
    }

    func testSidePanelCancelEscAndDeleteMatchSheetContracts() {
        launch(fixture: "standard", cardDetailPresentation: "side-panel")

        openBoardCard("Buy milk")
        replaceText(in: element(AccessibilityID.cardDetailTitleField), with: "Cancelled title")
        hittableButton("Cancel").click()
        XCTAssertTrue(poll(timeout: timeout) { !self.detailEditor.exists })
        XCTAssertTrue(anyCard("Buy milk").exists)
        XCTAssertFalse(anyCard("Cancelled title").exists)

        openBoardCard("Buy milk")
        replaceText(in: element(AccessibilityID.cardDetailTitleField), with: "Escaped title")
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(poll(timeout: timeout) { !self.detailEditor.exists })
        XCTAssertTrue(anyCard("Buy milk").exists)
        XCTAssertFalse(anyCard("Escaped title").exists)

        openBoardCard("Write report")
        hittableButton("Delete Card").click()
        XCTAssertTrue(poll(timeout: timeout) { !self.detailEditor.exists })
        XCTAssertTrue(poll(timeout: timeout) { !self.anyCard("Write report").exists })
        XCTAssertFalse(app.windows.buttons["Cancel"].exists,
                       "card delete remains immediate and confirmation-free")
    }

    func testDirtyCardTransitionKeepsDraftOrExplicitlyDiscardsIt() {
        launch(fixture: "standard", cardDetailPresentation: "side-panel")

        openBoardCard("Buy milk")
        let title = element(AccessibilityID.cardDetailTitleField)
        replaceText(in: title, with: "Draft survives")

        doubleClickBoardCardBody("Call plumber")
        let keep = hittableButton("Keep Editing")
        XCTAssertTrue(keep.waitForExistence(timeout: timeout),
                      "opening another card with a dirty draft must ask first")
        keep.click()
        XCTAssertEqual(title.value as? String, "Draft survives",
                       "Keep Editing must preserve the complete staged draft")
        XCTAssertEqual(presentationValue(), "side-panel")

        doubleClickBoardCardBody("Call plumber")
        let discard = hittableButton("Discard Changes")
        XCTAssertTrue(discard.waitForExistence(timeout: timeout))
        discard.click()
        XCTAssertTrue(poll(timeout: timeout) {
            self.element(AccessibilityID.cardDetailTitleField).value as? String == "Call plumber"
        }, "Discard Changes should perform the pending open with fresh card identity")
        XCTAssertTrue(anyCard("Buy milk").exists)
        XCTAssertFalse(anyCard("Draft survives").exists,
                       "discarded staged edits must never leak to the model")
    }

    func testDirtyViewModeTransitionKeepsEditingOrDiscardsAndSwitches() {
        launch(fixture: "standard", cardDetailPresentation: "side-panel")

        openBoardCard("Call plumber")
        let brief = element(AccessibilityID.cardDetailDescriptionField)
        brief.click()
        brief.typeText("Unsaved mode draft")

        clickViewMode("List", fallbackDx: 0.5)
        let keep = hittableButton("Keep Editing")
        XCTAssertTrue(keep.waitForExistence(timeout: timeout))
        keep.click()
        XCTAssertEqual(viewModeValue(), "board")
        XCTAssertEqual(brief.value as? String, "Unsaved mode draft")

        clickViewMode("List", fallbackDx: 0.5)
        hittableButton("Discard Changes").click()
        XCTAssertTrue(poll(timeout: timeout) { self.viewModeValue() == "list" })
        XCTAssertTrue(poll(timeout: timeout) { !self.detailEditor.exists })
    }

    func testDirtyBoardTransitionKeepsEditingOrDiscardsAndSwitches() {
        launch(fixture: "standard", cardDetailPresentation: "side-panel")

        openBoardCard("Call plumber")
        let title = element(AccessibilityID.cardDetailTitleField)
        replaceText(in: title, with: "Unsaved board draft")

        let work = element(AccessibilityID.board("Work"))
        XCTAssertTrue(work.waitForExistence(timeout: timeout))
        work.click()
        let keep = hittableButton("Keep Editing")
        XCTAssertTrue(keep.waitForExistence(timeout: timeout))
        keep.click()
        XCTAssertTrue(combinedText(boardDetail).contains("Groceries"),
                      "Keep Editing must cancel the pending board switch")
        XCTAssertEqual(title.value as? String, "Unsaved board draft")

        work.click()
        hittableButton("Discard Changes").click()
        XCTAssertTrue(poll(timeout: timeout) {
            self.combinedText(self.boardDetail).contains("Work")
        }, "Discard Changes should perform the pending board switch")
        XCTAssertTrue(poll(timeout: timeout) { !self.detailEditor.exists })
    }

    func testSidePanelOpensFromBoardListAndCalendarEntryPoints() {
        launch(fixture: "standard", cardDetailPresentation: "side-panel")

        let boardCard = anyCard("Call plumber")
        XCTAssertTrue(boardCard.waitForExistence(timeout: timeout))
        boardCard.rightClick()
        contextMenuItem("Open Card").click()
        assertSidePanel()
        hittableButton("Cancel").click()

        switchViewMode("List", expected: "list", fallbackDx: 0.5)
        let listRow = element(AccessibilityID.listRow("Call plumber"))
        XCTAssertTrue(listRow.waitForExistence(timeout: timeout))
        listRow.doubleClick()
        assertSidePanel()
        hittableButton("Cancel").click()

        switchViewMode("Calendar", expected: "calendar", fallbackDx: 0.85)
        let chip = element(AccessibilityID.calendarChip("Call plumber"))
        XCTAssertTrue(chip.waitForExistence(timeout: timeout))
        chip.doubleClick()
        assertSidePanel()
    }

    func testOpenCardCommandUsesConfiguredSidePanel() {
        launch(fixture: "standard", cardDetailPresentation: "side-panel")

        let card = anyCard("Call plumber")
        XCTAssertTrue(card.waitForExistence(timeout: timeout))
        card.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).click()

        openMenu("Card")
        let open = menuItem("Open Card")
        XCTAssertTrue(open.isEnabled, "Open Card command should enable for the selected card")
        open.click()
        assertSidePanel()
    }

    func testSettingsChoicePersistsAndCurrentEditorKeepsCapturedSurface() {
        launch(fixture: "standard")

        setPresentationInSettings("Side Panel")
        relaunchPreservingStore()
        openBoardCard("Call plumber")
        assertSidePanel()

        setPresentationInSettings("Sheet")
        XCTAssertEqual(presentationValue(), "side-panel",
                       "changing Settings must not move an editor that is already open")
        hittableButton("Cancel").click()

        openBoardCard("Call plumber")
        XCTAssertEqual(presentationValue(), "sheet",
                       "the changed preference should apply to the next open")
        XCTAssertFalse(inspectorMarker.exists)
        hittableButton("Cancel").click()

        relaunchPreservingStore()
        openBoardCard("Call plumber")
        XCTAssertEqual(presentationValue(), "sheet",
                       "a choice made through the real Settings UI should survive relaunch")
    }

    func testInspectorFocusGuardsCommandsDirtyImportAndBoardFocusedEsc() {
        launch(fixture: "standard", cardDetailPresentation: "side-panel")

        openBoardCard("Buy milk")
        let title = element(AccessibilityID.cardDetailTitleField)
        replaceText(in: title, with: "Guarded draft")
        let windowCount = app.windows.count

        app.typeKey("n", modifierFlags: .command)
        app.typeKey("n", modifierFlags: [.command, .option])
        XCTAssertEqual(app.windows.count, windowCount,
                       "guarded ⌘N must not fall through to New Window while typing")
        XCTAssertFalse(element(AccessibilityID.newCardField).exists)
        XCTAssertFalse(element(AccessibilityID.newListField).exists)
        XCTAssertTrue(detailEditor.exists)

        let dueDate = element(AccessibilityID.dueDatePickerField)
        XCTAssertTrue(dueDate.waitForExistence(timeout: timeout))
        dueDate.click()
        openMenu("Edit")
        XCTAssertFalse(menuItem("Delete Card").isEnabled,
                       "date-field focus must publish the same mutation guard as text fields")
        closeMenu()

        anyCard("Call plumber").click()
        openMenu("File")
        menuItem("Import Boards…").click()
        let keep = hittableButton("Keep Editing")
        XCTAssertTrue(keep.waitForExistence(timeout: timeout),
                      "a dirty inspector must be resolved before the import workflow begins")
        keep.click()
        XCTAssertEqual(title.value as? String, "Guarded draft")

        anyCard("Call plumber").click()
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(poll(timeout: timeout) { !self.detailEditor.exists },
                      "Esc should cancel the inspector after focus returns to the board")
        XCTAssertTrue(anyCard("Buy milk").exists)
        XCTAssertFalse(anyCard("Guarded draft").exists)
    }

    func testExternalCardEditReconcilesBeforeInspectorSave() {
        launch(fixture: "standard", cardDetailPresentation: "side-panel")

        openBoardCard("Call plumber")
        let card = anyCard("Call plumber")
        card.rightClick()
        contextMenuItem("Rename Card").click()

        let inlineTitle = element(AccessibilityID.cardTitle("Call plumber"))
        XCTAssertTrue(poll(timeout: timeout) { inlineTitle.elementType == .textField })
        replaceText(in: inlineTitle, with: "Call electrician")
        inlineTitle.typeKey(.enter, modifierFlags: [])

        XCTAssertTrue(poll(timeout: timeout) {
            self.element(AccessibilityID.cardDetailTitleField).value as? String == "Call electrician"
        }, "a clean staged title should adopt the external inline rename")
        hittableButton("Save").click()
        XCTAssertTrue(anyCard("Call electrician").waitForExistence(timeout: timeout))
        XCTAssertFalse(anyCard("Call plumber").exists,
                       "saving the inspector must not restore the stale pre-rename title")
    }

    func testListModeInspectorConsumesNewWindowShortcutWhileTyping() {
        launch(fixture: "standard", cardDetailPresentation: "side-panel")

        switchViewMode("List", expected: "list", fallbackDx: 0.5)
        let row = element(AccessibilityID.listRow("Call plumber"))
        XCTAssertTrue(row.waitForExistence(timeout: timeout))
        row.doubleClick()
        assertSidePanel()

        element(AccessibilityID.cardDetailTitleField).click()
        let windowCount = app.windows.count
        app.typeKey("n", modifierFlags: .command)
        XCTAssertEqual(app.windows.count, windowCount,
                       "List mode must consume ⌘N while an inspector editor has focus")
        XCTAssertTrue(detailEditor.exists)
    }

    // MARK: - Helpers

    private func assertSidePanel(file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(detailEditor.waitForExistence(timeout: timeout), file: file, line: line)
        XCTAssertTrue(inspectorMarker.waitForExistence(timeout: timeout), file: file, line: line)
        XCTAssertEqual(presentationValue(), "side-panel", file: file, line: line)
    }

    private func openBoardCard(_ title: String) {
        doubleClickBoardCardBody(title)
        XCTAssertTrue(detailEditor.waitForExistence(timeout: timeout),
                      "card detail should open for \(title)")
    }

    private func doubleClickBoardCardBody(_ title: String) {
        let card = anyCard(title)
        XCTAssertTrue(card.waitForExistence(timeout: timeout), "card-\(title) should exist")
        card.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).doubleClick()
    }

    private func replaceText(in field: XCUIElement, with value: String) {
        XCTAssertTrue(field.waitForExistence(timeout: timeout))
        field.click()
        field.typeKey("a", modifierFlags: .command)
        field.typeKey(.delete, modifierFlags: [])
        field.typeText(value)
    }

    private func switchViewMode(_ segment: String, expected: String, fallbackDx: CGFloat) {
        clickViewMode(segment, fallbackDx: fallbackDx)
        XCTAssertTrue(poll(timeout: timeout) { self.viewModeValue() == expected },
                      "view mode should become \(expected)")
    }

    private func clickViewMode(_ segment: String, fallbackDx: CGFloat) {
        let picker = element(AccessibilityID.viewModePicker)
        XCTAssertTrue(picker.waitForExistence(timeout: timeout))
        if picker.radioButtons[segment].exists {
            picker.radioButtons[segment].click()
        } else if picker.buttons[segment].exists {
            picker.buttons[segment].click()
        } else {
            picker.coordinate(withNormalizedOffset: CGVector(dx: fallbackDx, dy: 0.5)).click()
        }
    }

    private func setPresentationInSettings(_ option: String) {
        app.typeKey(",", modifierFlags: .command)
        let picker = element(AccessibilityID.cardDetailSettingsPicker)
        XCTAssertTrue(picker.waitForExistence(timeout: timeout),
                      "the card-detail Settings picker should open with ⌘,")

        let scopedOption = picker.radioButtons[option]
        let radio = scopedOption.exists ? scopedOption : app.radioButtons[option]
        XCTAssertTrue(radio.waitForExistence(timeout: timeout),
                      "Settings should offer the \(option) presentation")
        radio.click()

        app.typeKey("w", modifierFlags: .command)
        XCTAssertTrue(poll(timeout: timeout) { !picker.exists },
                      "closing Settings should return to the board window")
        app.activate()
    }

    private func presentationValue() -> String {
        combinedText(element(AccessibilityID.cardDetailPresentationValue))
    }

    private func viewModeValue() -> String {
        combinedText(element(AccessibilityID.viewModeValue))
    }

    private var detailEditor: XCUIElement {
        element(AccessibilityID.cardDetailSheet)
    }

    private var inspectorMarker: XCUIElement {
        element(AccessibilityID.cardDetailInspector)
    }

    private var boardDetail: XCUIElement {
        element(AccessibilityID.boardDetail)
    }

    private func anyCard(_ title: String) -> XCUIElement {
        element(AccessibilityID.card(title))
    }

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }
}
