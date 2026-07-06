import XCTest

/// M7 exit-gate tests for the menu-bar command layer: menu-item discoverability + enablement, and
/// every P0 keyboard shortcut driven through the real menus (⌘N/⌥⌘N/⇧⌘N, ⌘⌫ + undo/redo, ⌘-arrow
/// card moves, bare-arrow selection navigation, ⌘1/⌘2 board switching, sidebar toggle).
///
/// Fixture "standard" (Groceries selected by default: To Do = [Buy milk, Call plumber, Return
/// library books], In Progress = [Write report], Done = [Book flights]; plus an empty "Work"
/// board) unless a test states otherwise.
final class KeyboardShortcutUITests: KanbanUITestCase {

    private let timeout: TimeInterval = 15

    // MARK: - Menu discoverability + enablement

    func testMenuItemsExistAndEnabledStates() {
        launch(fixture: "standard")
        XCTAssertTrue(boardDetail.waitForExistence(timeout: timeout))

        // File: New Card / New List / New Board present and enabled (a board is shown).
        openMenu("File")
        XCTAssertTrue(menuItem("New Card").waitForExistence(timeout: timeout), "File ▸ New Card should exist")
        XCTAssertTrue(menuItem("New Card").isEnabled, "New Card enabled with a board shown")
        XCTAssertTrue(menuItem("New List").isEnabled, "New List enabled with a board shown")
        XCTAssertTrue(menuItem("New Board").isEnabled, "New Board always enabled")
        closeMenu()

        // Edit: system Undo present; Delete Card present + disabled (no selection yet).
        openMenu("Edit")
        XCTAssertTrue(anyMenuItem(beginningWith: "Undo").waitForExistence(timeout: timeout),
                      "Edit ▸ Undo (system) should exist")
        XCTAssertTrue(menuItem("Delete Card").waitForExistence(timeout: timeout), "Edit ▸ Delete Card should exist")
        XCTAssertFalse(menuItem("Delete Card").isEnabled, "Delete Card disabled with no selection")
        closeMenu()

        // Card: move items disabled with no selection.
        openMenu("Card")
        XCTAssertTrue(menuItem("Move Card Up").waitForExistence(timeout: timeout), "Card ▸ Move Card Up should exist")
        XCTAssertFalse(menuItem("Move Card Up").isEnabled, "Move Card Up disabled with no selection")
        closeMenu()

        // Select a card → Card + Delete become enabled.
        anyCard("Buy milk").click()
        XCTAssertTrue(poll(timeout: timeout) { self.anyCard("Buy milk").isSelected })

        openMenu("Card")
        XCTAssertTrue(menuItem("Move Card Up").isEnabled, "Move Card Up enabled after selecting a card")
        closeMenu()
        openMenu("Edit")
        XCTAssertTrue(menuItem("Delete Card").isEnabled, "Delete Card enabled after selecting a card")
        closeMenu()

        // M11 carried cleanup: edge-list enablement. Buy milk sits in the LEFTMOST list (To Do —
        // no `canMoveSelectedCard(.left)` destination), so Move Card Left must be disabled while
        // Move Card Right (into In Progress) stays enabled.
        openMenu("Card")
        XCTAssertFalse(menuItem("Move Card Left").isEnabled, "Move Card Left disabled at the leftmost list")
        XCTAssertTrue(menuItem("Move Card Right").isEnabled, "Move Card Right enabled toward an adjacent list")
        closeMenu()

        // Mirror at the other edge: Book flights sits in the RIGHTMOST list (Done) — Move Card
        // Right must be disabled there, with Move Card Left enabled.
        anyCard("Book flights").click()
        XCTAssertTrue(poll(timeout: timeout) { self.anyCard("Book flights").isSelected })
        openMenu("Card")
        XCTAssertFalse(menuItem("Move Card Right").isEnabled, "Move Card Right disabled at the rightmost list")
        XCTAssertTrue(menuItem("Move Card Left").isEnabled, "Move Card Left enabled toward an adjacent list")
        closeMenu()

        // Disabled case (second launch, empty fixture): New Card / New List disabled with no board.
        app.terminate()
        launch(fixture: "empty")
        XCTAssertTrue(rootView.waitForExistence(timeout: timeout))
        openMenu("File")
        XCTAssertTrue(menuItem("New Card").waitForExistence(timeout: timeout))
        XCTAssertFalse(menuItem("New Card").isEnabled, "New Card disabled with no board")
        XCTAssertFalse(menuItem("New List").isEnabled, "New List disabled with no board")
        XCTAssertTrue(menuItem("New Board").isEnabled, "New Board still enabled with no board")
        closeMenu()
    }

    /// Pre-ship fix: File ▸ New Card must be DISABLED once every list on the active board is
    /// collapsed — there is no visible list left for the inline editor to open on.
    /// `NewCardTarget.resolve` already returned nil for this case (see its own tests); this wires
    /// that nil through to the menu item's actual enablement via `BoardActions.canCreateCard`
    /// (see `AppCommands`'s New Card `.disabled(...)`), which previously left ⌘N enabled-and-no-op
    /// on an all-collapsed board.
    func testNewCardDisabledWhenAllListsCollapsed() {
        launch(fixture: "standard")
        XCTAssertTrue(boardDetail.waitForExistence(timeout: timeout))

        // Work (⌘2) is the standard fixture's second, otherwise-empty board — still seeded with
        // the default 3 lists (To Do / In Progress / Done) by `BoardStore.createBoard`.
        app.typeKey("2", modifierFlags: .command)
        XCTAssertTrue(poll(timeout: timeout) { self.combinedText(self.boardDetail).contains("Work") },
                      "⌘2 should switch to the Work board")

        for name in ["To Do", "In Progress", "Done"] {
            let chevron = collapseButton(name)
            XCTAssertTrue(chevron.waitForExistence(timeout: timeout), "\(name) collapse chevron should exist")
            chevron.click()
            XCTAssertTrue(poll(timeout: timeout) { self.collapseState(name) == "collapsed" },
                          "\(name) should collapse")
        }

        openMenu("File")
        XCTAssertTrue(menuItem("New Card").waitForExistence(timeout: timeout))
        XCTAssertFalse(menuItem("New Card").isEnabled,
                       "New Card should be disabled once every list on the board is collapsed")
        closeMenu()
    }

    func testSidebarToggleMenuItemExists() {
        launch(fixture: "standard")
        XCTAssertTrue(boardDetail.waitForExistence(timeout: timeout))
        openMenu("View")
        XCTAssertTrue(menuItem("Toggle Sidebar").waitForExistence(timeout: timeout),
                      "View menu should contain a sidebar-toggle item")
        closeMenu()
    }

    // MARK: - New Card / List / Board

    /// Two independently-launched halves, deliberately: an OPEN inline add-card editor makes
    /// follow-up synthesized events unreliable under XCUITest (an immediate Esc intermittently
    /// fails to close it, and a card click while it holds focus intermittently fails to select —
    /// both traced in the M7 run logs), so neither half ever needs to close the editor or click
    /// past it.
    func testCmdNOpensAddCardOnFocusedOrFirstList() {
        // Half 1 — no selection: ⌘N opens the editor on the FIRST list (To Do), and it is the
        // REAL inline editor (typing + Enter creates the card there).
        launch(fixture: "standard")
        XCTAssertTrue(boardDetail.waitForExistence(timeout: timeout))

        app.typeKey("n", modifierFlags: .command)
        let toDoField = newCardField(under: list("To Do"))
        XCTAssertTrue(poll(timeout: timeout) { toDoField.exists },
                      "⌘N with no selection should open the add-card editor on To Do")
        toDoField.click()
        toDoField.typeText("Via Shortcut")
        toDoField.typeKey(.enter, modifierFlags: [])
        XCTAssertTrue(poll(timeout: timeout) { self.card("Via Shortcut", under: self.list("To Do")).exists },
                      "the ⌘N editor should be the real add-card flow (Enter creates in To Do)")

        // Half 2 — fresh launch, select FIRST (no editor open), then ⌘N targets the selected
        // card's list.
        app.terminate()
        launch(fixture: "standard")
        let writeReport = anyCard("Write report")
        XCTAssertTrue(writeReport.waitForExistence(timeout: timeout))
        writeReport.click()
        XCTAssertTrue(poll(timeout: timeout) { self.anyCard("Write report").isSelected })
        app.typeKey("n", modifierFlags: .command)
        XCTAssertTrue(poll(timeout: timeout) { self.newCardField(under: self.list("In Progress")).exists },
                      "⌘N with a card selected in In Progress should open the editor there")
    }

    func testOptCmdNNewListEditor() {
        launch(fixture: "standard")
        XCTAssertTrue(boardDetail.waitForExistence(timeout: timeout))

        app.typeKey("n", modifierFlags: [.command, .option])
        let field = app.descendants(matching: .any)[AccessibilityID.newListField]
        XCTAssertTrue(field.waitForExistence(timeout: timeout), "⌥⌘N should open the add-list editor")
    }

    func testShiftCmdNNewBoardSheet() {
        launch(fixture: "standard")
        XCTAssertTrue(boardDetail.waitForExistence(timeout: timeout))

        app.typeKey("n", modifierFlags: [.command, .shift])
        let nameField = app.descendants(matching: .any)[AccessibilityID.boardNameField]
        XCTAssertTrue(nameField.waitForExistence(timeout: timeout), "⇧⌘N should open the new-board sheet")
    }

    // MARK: - Delete + Undo / Redo

    func testCmdDeleteThenUndoRedo() {
        launch(fixture: "standard")

        let book = anyCard("Book flights")
        XCTAssertTrue(book.waitForExistence(timeout: timeout))
        book.click()
        XCTAssertTrue(poll(timeout: timeout) { self.anyCard("Book flights").isSelected })

        app.typeKey(.delete, modifierFlags: .command)
        XCTAssertTrue(poll(timeout: timeout) { !self.anyCard("Book flights").exists },
                      "⌘⌫ should delete the selected card")
        XCTAssertFalse(app.sheets.firstMatch.exists, "delete must not present a sheet")
        XCTAssertFalse(app.windows.buttons["Cancel"].exists, "delete must not present a confirmation dialog")

        // Edit ▸ Undo is enabled after the delete (SwiftUI's built-in Undo item is titled plain
        // "Undo" — it surfaces canUndo, not the NSUndoManager action name; the wiring itself is
        // verified by the ⌘Z restore below).
        openMenu("Edit")
        let undo = menuItem("Undo")
        XCTAssertTrue(undo.waitForExistence(timeout: timeout), "Edit ▸ Undo should exist")
        XCTAssertTrue(undo.isEnabled, "Undo should be enabled after a delete")
        closeMenu()

        app.typeKey("z", modifierFlags: .command)
        XCTAssertTrue(poll(timeout: timeout) { self.anyCard("Book flights").exists },
                      "⌘Z should restore the deleted card")
        XCTAssertEqual(cardIdentifiersByPosition(under: list("Done")), [AccessibilityID.card("Book flights")],
                       "restored card should be back at its original position in Done")

        app.typeKey("z", modifierFlags: [.command, .shift])
        XCTAssertTrue(poll(timeout: timeout) { !self.anyCard("Book flights").exists },
                      "⇧⌘Z should redo the delete")
    }

    /// M7 hardening: a mutating card command (⌘⌫) must NOT fire while an inline editor holds
    /// keyboard focus — otherwise it deletes the selected card behind the editor's back (macOS
    /// matches menu key-equivalents before the key window's responder chain). Guarded via the
    /// `textInputFocused` focused value on both the command's enablement AND its action (see
    /// AppCommands — the classic `firstResponder is NSTextView` check is unusable here, since
    /// SwiftUI's text backend keeps a private `KeyViewProxy` as first responder in ALL states).
    func testCmdDeleteGuardedWhileAddCardEditorOpen() {
        launch(fixture: "standard")

        // Select Buy milk (To Do), then open the add-card editor on To Do via ⌘N (its own list).
        let buyMilk = anyCard("Buy milk")
        XCTAssertTrue(buyMilk.waitForExistence(timeout: timeout))
        buyMilk.click()
        XCTAssertTrue(poll(timeout: timeout) { self.anyCard("Buy milk").isSelected })

        app.typeKey("n", modifierFlags: .command)
        let toDoField = newCardField(under: list("To Do"))
        XCTAssertTrue(poll(timeout: timeout) { toDoField.exists },
                      "⌘N should open the add-card editor on To Do (Buy milk's list)")
        // Deterministic focus: synthesized ⌘N focus hand-off can be flaky under XCUITest (M7 §6),
        // so click the field — the guarded property under test is "field focused ⇒ no mutation".
        toDoField.click()
        toDoField.typeText("draft")

        // ⌘⌫ while the editor is focused must be a no-op on the model — the card survives and the
        // editor stays open (the key went to the field/menu no-op, not the Delete Card command).
        app.typeKey(.delete, modifierFlags: .command)
        Thread.sleep(forTimeInterval: 0.6)
        XCTAssertTrue(anyCard("Buy milk").exists,
                      "⌘⌫ with an inline editor open must NOT delete the selected card")
        XCTAssertTrue(toDoField.exists, "the add-card editor should still be open after the guarded ⌘⌫")

        // The guard is scoped, not permanent: once the editor closes, ⌘⌫ deletes normally again.
        // (Esc can be flaky against an open inline field under XCUITest — retry until it closes.)
        XCTAssertTrue(poll(timeout: timeout) {
            if toDoField.exists { toDoField.typeKey(.escape, modifierFlags: []) }
            return !toDoField.exists
        }, "Esc should close the add-card editor")

        XCTAssertTrue(poll(timeout: timeout) { self.anyCard("Buy milk").isSelected },
                      "Buy milk should still be the selection after the editor closes")
        app.typeKey(.delete, modifierFlags: .command)
        XCTAssertTrue(poll(timeout: timeout) { !self.anyCard("Buy milk").exists },
                      "with no editor open, ⌘⌫ should delete the selected card again")
    }

    func testUndoCardMove() {
        launch(fixture: "standard")

        let buyMilk = anyCard("Buy milk")
        XCTAssertTrue(buyMilk.waitForExistence(timeout: timeout))
        buyMilk.click()
        XCTAssertTrue(poll(timeout: timeout) { self.anyCard("Buy milk").isSelected })

        app.typeKey(.rightArrow, modifierFlags: .command)
        XCTAssertTrue(poll(timeout: timeout) { self.card("Buy milk", under: self.list("In Progress")).exists },
                      "⌘→ should move Buy milk into In Progress")

        app.typeKey("z", modifierFlags: .command)
        XCTAssertTrue(poll(timeout: timeout) { self.card("Buy milk", under: self.list("To Do")).exists },
                      "⌘Z should return Buy milk to To Do")
        XCTAssertEqual(cardIdentifiersByPosition(under: list("To Do")),
                       expected("Buy milk", "Call plumber", "Return library books"),
                       "Buy milk should be restored at its original To Do position")
    }

    // MARK: - Arrow selection navigation (bare arrows)

    func testArrowSelectionNavigation() {
        launch(fixture: "standard")

        let buyMilk = anyCard("Buy milk")
        XCTAssertTrue(buyMilk.waitForExistence(timeout: timeout))
        buyMilk.click()
        XCTAssertTrue(poll(timeout: timeout) { self.anyCard("Buy milk").isSelected })

        // ↓ within To Do.
        app.typeKey(.downArrow, modifierFlags: [])
        XCTAssertTrue(poll(timeout: timeout) { self.anyCard("Call plumber").isSelected },
                      "↓ should move selection to Call plumber")

        // ↓↓ crosses the end of To Do into In Progress (Write report).
        app.typeKey(.downArrow, modifierFlags: [])
        XCTAssertTrue(poll(timeout: timeout) { self.anyCard("Return library books").isSelected },
                      "↓ should move to Return library books")
        app.typeKey(.downArrow, modifierFlags: [])
        XCTAssertTrue(poll(timeout: timeout) { self.anyCard("Write report").isSelected },
                      "↓ from the last To Do card should cross into In Progress (Write report)")

        // ↑ crosses back to the last card of To Do.
        app.typeKey(.upArrow, modifierFlags: [])
        XCTAssertTrue(poll(timeout: timeout) { self.anyCard("Return library books").isSelected },
                      "↑ from the first In Progress card should cross back to the last To Do card")
    }

    /// Final review: bare ↓ with NO selection is the keyboard ENTRY point. Select Next Card is now
    /// enabled whenever a board is shown (not only when a card is already selected), so this
    /// nil-selection branch — first card of the first non-empty list — is reachable (it was
    /// stranded while the item was disabled with no selection). Purely keyboard-driven (no click)
    /// so there's no delayed tap-gesture arbitration to race.
    func testArrowSelectionEntersFromNoSelection() {
        launch(fixture: "standard")
        XCTAssertTrue(anyCard("Buy milk").waitForExistence(timeout: timeout))

        // No card selected yet: ↓ selects the first card of the first non-empty list (To Do → Buy milk).
        app.typeKey(.downArrow, modifierFlags: [])
        XCTAssertTrue(poll(timeout: timeout) { self.anyCard("Buy milk").isSelected },
                      "↓ with no selection should select the first card of the first non-empty list")

        // And navigation continues normally from there.
        app.typeKey(.downArrow, modifierFlags: [])
        XCTAssertTrue(poll(timeout: timeout) { self.anyCard("Call plumber").isSelected },
                      "↓ should then advance to the next card")
    }

    // MARK: - ⌘-arrow card moves (comprehensive, undo stepwise)

    func testCmdArrowMovesCard() {
        launch(fixture: "standard")

        let callPlumber = anyCard("Call plumber")
        XCTAssertTrue(callPlumber.waitForExistence(timeout: timeout))
        callPlumber.click()
        XCTAssertTrue(poll(timeout: timeout) { self.anyCard("Call plumber").isSelected })

        // ⌘↓ within To Do: [Buy milk, Return library books, Call plumber].
        app.typeKey(.downArrow, modifierFlags: .command)
        XCTAssertTrue(poll(timeout: timeout) {
            self.cardIdentifiersByPosition(under: self.list("To Do"))
                == self.expected("Buy milk", "Return library books", "Call plumber")
        }, "⌘↓ should move Call plumber down within To Do")

        // ⌘→ into In Progress, clamped to the end: In Progress = [Write report, Call plumber].
        app.typeKey(.rightArrow, modifierFlags: .command)
        XCTAssertTrue(poll(timeout: timeout) {
            self.cardIdentifiersByPosition(under: self.list("In Progress"))
                == self.expected("Write report", "Call plumber")
        }, "⌘→ should move Call plumber into In Progress (clamped to the end)")
        XCTAssertEqual(cardIdentifiersByPosition(under: list("To Do")),
                       expected("Buy milk", "Return library books"),
                       "To Do should renumber after the cross-list move")

        // ⌘Z undoes the cross-list move first.
        app.typeKey("z", modifierFlags: .command)
        XCTAssertTrue(poll(timeout: timeout) {
            self.cardIdentifiersByPosition(under: self.list("To Do"))
                == self.expected("Buy milk", "Return library books", "Call plumber")
        }, "first ⌘Z should undo the cross-list move")
        XCTAssertEqual(cardIdentifiersByPosition(under: list("In Progress")),
                       expected("Write report"), "In Progress restored")

        // ⌘Z undoes the within-list move next.
        app.typeKey("z", modifierFlags: .command)
        XCTAssertTrue(poll(timeout: timeout) {
            self.cardIdentifiersByPosition(under: self.list("To Do"))
                == self.expected("Buy milk", "Call plumber", "Return library books")
        }, "second ⌘Z should undo the within-list move (original order restored)")
    }

    // MARK: - Open Card (⌘O)

    /// Card ▸ "Open Card" (⌘O): opens the selected card's detail sheet; disabled with no selection.
    func testCmdOOpensSelectedCardDetail() {
        launch(fixture: "standard")
        XCTAssertTrue(boardDetail.waitForExistence(timeout: timeout))

        // No selection → the menu item is disabled.
        openMenu("Card")
        XCTAssertTrue(menuItem("Open Card").waitForExistence(timeout: timeout), "Card ▸ Open Card should exist")
        XCTAssertFalse(menuItem("Open Card").isEnabled, "Open Card should be disabled with no selection")
        closeMenu()

        // Select Call plumber, then ⌘O opens its detail sheet with the right title.
        let callPlumber = anyCard("Call plumber")
        XCTAssertTrue(callPlumber.waitForExistence(timeout: timeout))
        callPlumber.click()
        XCTAssertTrue(poll(timeout: timeout) { self.anyCard("Call plumber").isSelected })

        openMenu("Card")
        XCTAssertTrue(menuItem("Open Card").isEnabled, "Open Card should be enabled after selecting a card")
        closeMenu()

        app.typeKey("o", modifierFlags: .command)
        let sheet = app.descendants(matching: .any)[AccessibilityID.cardDetailSheet]
        XCTAssertTrue(sheet.waitForExistence(timeout: timeout), "⌘O should open the card-detail sheet")
        let titleField = app.descendants(matching: .any)[AccessibilityID.cardDetailTitleField]
        XCTAssertTrue(titleField.waitForExistence(timeout: timeout))
        XCTAssertEqual(titleField.value as? String, "Call plumber",
                       "the sheet should open on the selected card (Call plumber)")
    }

    // MARK: - ⌘N is collapse-aware

    /// Final review: with the first list collapsed, ⌘N (no selection) targets the first EXPANDED
    /// list, never the collapsed one (whose inline editor isn't on screen).
    func testCmdNTargetsFirstExpandedListWhenFirstCollapsed() {
        launch(fixture: "standard")
        XCTAssertTrue(boardDetail.waitForExistence(timeout: timeout))

        // Collapse To Do (the first list).
        let collapseToDo = app.descendants(matching: .any)[AccessibilityID.collapseListButton("To Do")]
        XCTAssertTrue(collapseToDo.waitForExistence(timeout: timeout), "To Do collapse chevron should exist")
        collapseToDo.click()
        XCTAssertTrue(poll(timeout: timeout) { self.collapseState("To Do") == "collapsed" },
                      "To Do should collapse")

        // ⌘N now opens the add-card editor on In Progress (the first expanded list), NOT To Do.
        app.typeKey("n", modifierFlags: .command)
        XCTAssertTrue(poll(timeout: timeout) { self.newCardField(under: self.list("In Progress")).exists },
                      "⌘N should open the editor on the first EXPANDED list (In Progress)")
        XCTAssertFalse(newCardField(under: list("To Do")).exists,
                       "⌘N must not open an editor on the collapsed To Do")
    }

    // MARK: - Board switching

    func testCmd1Cmd2SwitchBoards() {
        launch(fixture: "standard")
        XCTAssertTrue(poll(timeout: timeout) { self.combinedText(self.boardDetail).contains("Groceries") },
                      "Groceries should be shown by default")

        app.typeKey("2", modifierFlags: .command)
        XCTAssertTrue(poll(timeout: timeout) { self.combinedText(self.boardDetail).contains("Work") },
                      "⌘2 should switch to the Work board")

        app.typeKey("1", modifierFlags: .command)
        XCTAssertTrue(poll(timeout: timeout) { self.combinedText(self.boardDetail).contains("Groceries") },
                      "⌘1 should switch back to Groceries")
    }

    // MARK: - Menu helpers

    private func openMenu(_ title: String) {
        let bar = app.menuBars.menuBarItems[title]
        XCTAssertTrue(bar.waitForExistence(timeout: timeout), "\(title) menu should exist in the menu bar")
        bar.click()
    }

    private func closeMenu() {
        app.typeKey(.escape, modifierFlags: [])
    }

    private func menuItem(_ title: String) -> XCUIElement {
        app.menuBars.menuItems[title]
    }

    private func anyMenuItem(beginningWith prefix: String) -> XCUIElement {
        app.menuBars.menuItems.matching(NSPredicate(format: "title BEGINSWITH %@", prefix)).firstMatch
    }

    // MARK: - Element lookups

    private var rootView: XCUIElement { app.descendants(matching: .any)[AccessibilityID.rootView] }
    private var boardDetail: XCUIElement { app.descendants(matching: .any)[AccessibilityID.boardDetail] }

    private func list(_ name: String) -> XCUIElement {
        app.descendants(matching: .any)[AccessibilityID.list(name)]
    }

    private func anyCard(_ title: String) -> XCUIElement {
        app.descendants(matching: .any)[AccessibilityID.card(title)]
    }

    private func card(_ title: String, under container: XCUIElement) -> XCUIElement {
        container.descendants(matching: .any)[AccessibilityID.card(title)]
    }

    private func newCardField(under container: XCUIElement) -> XCUIElement {
        container.descendants(matching: .any)[AccessibilityID.newCardField]
    }

    /// The machine-readable collapse state ("collapsed"/"expanded") published by a column's detached
    /// marker (mirrors CollapseUITests).
    private func collapseState(_ name: String) -> String? {
        app.descendants(matching: .any)[AccessibilityID.listCollapseState(name)].value as? String
    }

    /// The collapse-toggle chevron for a list (mirrors CollapseUITests).
    private func collapseButton(_ name: String) -> XCUIElement {
        app.descendants(matching: .any)[AccessibilityID.collapseListButton(name)]
    }

    private func expected(_ titles: String...) -> [String] {
        titles.map(AccessibilityID.card)
    }
}
