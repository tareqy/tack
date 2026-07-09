import XCTest

/// M-D exit-gate tests for the Calendar View. Fixture "standard" (board Groceries) maps onto the
/// month grid as: Buy milk → yesterday's cell, Call plumber → today's cell, Return library
/// books → tomorrow's cell, Write report → the +5d cell (timed 14:00), Book flights → the
/// No Date rail. All expected day-cell ids are computed from `Date()` at TEST RUNTIME with those
/// same relative deltas (the fixture seeds launch-relative real-now dates) — NEVER hardcoded day
/// numbers — and any assertion whose relative day falls outside the currently displayed month is
/// skipped via XCTSkipIf (deterministic, documented). Across-midnight runs remain the documented
/// fixture-relative flake class. All tests are MOUSE-driven: mode switching goes through the
/// toolbar segment + the `view-mode-value` marker oracle, never the View menu.
///
/// DELIBERATELY NOT e2e'd here:
/// - View ▸ as Calendar + ⌥⌘C, and the honest-disable enablement asserts (bare arrows, ⌘F, ⌘N)
///   — menu-enablement assertions fail deterministically in the host's degraded-keyboard state
///   (CLAUDE.md). Deferred to the fresh-session full run + the M-D human checklist.
/// - prev/next month grid CONTENTS beyond what the title value proves — the cell math is
///   exhaustively unit-covered (CalendarMonthGridTests, incl. a 48-month invariant sweep).
/// - the "+N" overflow (the untouched fixture never puts 4 cards on one day) and the today-ring
///   VISUAL (colors are screenshot/human-verified per the M10 posture) — human checklist.
final class CalendarViewUITests: TackUITestCase {

    private let timeout: TimeInterval = 15

    func testSwitchToCalendarShowsMonthTodayCellAndRail() {
        launch(fixture: "standard")

        switchToCalendar()

        // The displayed month is the real current month (no injected clock — see the plan's
        // Architecture clock resolution), machine-readable as POSIX yyyy-MM.
        XCTAssertTrue(element(AccessibilityID.calendarMonthTitle).waitForExistence(timeout: timeout))
        XCTAssertEqual(monthTitleValue(), expectedMonthValue(),
                       "the calendar should open on the current month")

        // Today's cell exists under its runtime-computed date id and holds Call plumber's chip.
        // (Cell id == date, so chip-in-cell containment IS the due-date assertion.)
        let today = cell(dayID(0))
        XCTAssertTrue(today.waitForExistence(timeout: timeout), "today's cell should exist")
        XCTAssertTrue(chip("Call plumber", in: today).exists,
                      "Call plumber (due today) should be a chip inside today's cell")

        // Month navigation controls are present.
        XCTAssertTrue(element(AccessibilityID.calendarPrevButton).exists)
        XCTAssertTrue(element(AccessibilityID.calendarTodayButton).exists)
        XCTAssertTrue(element(AccessibilityID.calendarNextButton).exists)

        // The undated card lives in the No Date rail — visible, never hidden.
        XCTAssertTrue(element(AccessibilityID.calendarNoDateHeader).exists)
        XCTAssertTrue(element(AccessibilityID.calendarNoDateRow("Book flights")).exists)

        // The board canvas is genuinely gone (not just the marker flipped): no To Do column.
        XCTAssertFalse(element(AccessibilityID.list("To Do")).exists,
                       "the column canvas must not render in calendar mode")

        // Month nav round-trip via the title value only (grid contents are unit-covered):
        // next flips the month string, Today restores it.
        element(AccessibilityID.calendarNextButton).click()
        XCTAssertTrue(poll(timeout: timeout) { self.monthTitleValue() != self.expectedMonthValue() },
                      "Next should move the title off the current month")
        element(AccessibilityID.calendarTodayButton).click()
        XCTAssertTrue(poll(timeout: timeout) { self.monthTitleValue() == self.expectedMonthValue() },
                      "Today should restore the current month")
    }

    func testTimedChipCarriesTimePrefix() throws {
        // The fixture's one timed card sits at +5d, which leaves the displayed month near
        // month-end — the documented deterministic skip, never a hardcoded day.
        try XCTSkipIf(!dayIsInCurrentMonth(5),
                      "+5d crosses the month boundary today; timed-chip prefix is asserted only when Write report's day is in the displayed grid")
        launch(fixture: "standard")

        switchToCalendar()

        let writeReport = chip("Write report", in: cell(dayID(5)))
        XCTAssertTrue(writeReport.waitForExistence(timeout: timeout),
                      "Write report (+5d) should be a chip in its day's cell")
        XCTAssertTrue((writeReport.value as? String ?? "").hasPrefix("14:00|"),
                      "a timed chip's wire value leads with its POSIX HH:mm slot time")
    }

    func testChipDoubleClickOpensDetail() {
        launch(fixture: "standard")
        switchToCalendar()

        let target = chip("Call plumber", in: cell(dayID(0)))
        XCTAssertTrue(target.waitForExistence(timeout: timeout))
        target.doubleClick()

        XCTAssertTrue(detailSheet.waitForExistence(timeout: timeout),
                      "double-clicking a chip should open the card-detail sheet")
        XCTAssertEqual(element(AccessibilityID.cardDetailTitleField).value as? String, "Call plumber",
                       "the sheet should show the double-clicked card")

        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(poll(timeout: timeout) { !self.detailSheet.exists }, "Esc should close the sheet")
    }

    func testDragChipToNewDayReschedules() throws {
        // Needs BOTH yesterday and tomorrow inside the displayed (current) month: on the 1st the
        // source chip wouldn't render (dimmed cells show no cards), on the last day the target
        // cell wouldn't accept drops. Deterministic skip, computed — never hardcoded.
        try XCTSkipIf(!dayIsInCurrentMonth(-1) || !dayIsInCurrentMonth(1),
                      "yesterday/tomorrow crosses the month boundary today — drag path skipped")
        launch(fixture: "standard")

        switchToCalendar()

        let source = chip("Buy milk", in: cell(dayID(-1)))
        XCTAssertTrue(source.waitForExistence(timeout: timeout),
                      "Buy milk (−1d) should start in yesterday's cell")
        let target = cell(dayID(1))
        XCTAssertTrue(target.exists)

        // Postcondition-polled drag (the drag-retry pitfall): the base helper polls `until`
        // before deciding to retry, so a slow-but-successful drop is never dragged twice.
        drag(source, to: target, targetNormalizedOffset: CGVector(dx: 0.5, dy: 0.5),
             until: { self.chip("Buy milk", in: self.cell(self.dayID(1))).exists })

        XCTAssertTrue(chip("Buy milk", in: cell(dayID(1))).exists,
                      "the chip should now live in tomorrow's cell (cell id encodes the new date)")
        XCTAssertFalse(chip("Buy milk", in: cell(dayID(-1))).exists,
                       "…and be gone from yesterday's cell")

        // Store-truth oracle beyond calendar view state: List mode's row badge publishes
        // "<iso>|<status>", and Buy milk at +1d must classify as tomorrow.
        switchToList()
        let badge = element(AccessibilityID.dueDateBadge(card: "Buy milk"))
        XCTAssertTrue(badge.waitForExistence(timeout: timeout))
        XCTAssertTrue((badge.value as? String ?? "").hasSuffix("|tomorrow"),
                      "the store should hold the rescheduled date, not just the view")
    }

    func testModePersistsAcrossRelaunch() {
        launch(fixture: "standard")

        switchToCalendar()

        relaunchPreservingStore()

        XCTAssertTrue(element(AccessibilityID.calendarMonthTitle).waitForExistence(timeout: timeout),
                      "Groceries should come back in CALENDAR mode after relaunch")
        XCTAssertEqual(viewModeValue(), "calendar")
    }

    // MARK: - Helpers

    /// Segment-click + marker-poll (the M-C switchToList grammar, generalized for 3 segments).
    private func switchToCalendar() { switchMode(segment: "Calendar", expected: "calendar", fallbackDx: 0.85) }
    private func switchToList() { switchMode(segment: "List", expected: "list", fallbackDx: 0.5) }

    private func switchMode(segment: String, expected: String, fallbackDx: CGFloat) {
        let picker = element(AccessibilityID.viewModePicker)
        XCTAssertTrue(picker.waitForExistence(timeout: timeout),
                      "the view-mode switcher should be in the toolbar")
        let radio = picker.radioButtons[segment]
        if radio.exists {
            radio.click()
        } else if picker.buttons[segment].exists {
            picker.buttons[segment].click()
        } else {
            // Last resort: segment centres of the three-segment control (Board 0.17 / List 0.5 /
            // Calendar 0.85).
            picker.coordinate(withNormalizedOffset: CGVector(dx: fallbackDx, dy: 0.5)).click()
        }
        XCTAssertTrue(poll(timeout: timeout) { self.viewModeValue() == expected },
                      "view-mode-value should read '\(expected)' after clicking the \(segment) segment")
    }

    private func viewModeValue() -> String {
        element(AccessibilityID.viewModeValue).value as? String ?? ""
    }

    // MARK: date math (runtime-relative, never hardcoded — see the class doc)

    private func dateFromToday(_ delta: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: delta, to: Date())!
    }

    private func dayIsInCurrentMonth(_ delta: Int) -> Bool {
        Calendar.current.isDate(dateFromToday(delta), equalTo: Date(), toGranularity: .month)
    }

    private func dayID(_ delta: Int) -> String {
        AccessibilityID.calendarDay(Self.isoDayFormatter.string(from: dateFromToday(delta)))
    }

    private func expectedMonthValue() -> String {
        Self.wireMonthFormatter.string(from: Date())
    }

    private func monthTitleValue() -> String {
        element(AccessibilityID.calendarMonthTitle).value as? String ?? ""
    }

    // MARK: element shorthands

    private func cell(_ id: String) -> XCUIElement { element(id) }

    /// Chip CONTAINMENT query: chips are AX descendants of their `.contain` day cell (the
    /// `card(_:)`-under-`list(_:)` precedent), so scoping to the cell asserts membership.
    private func chip(_ title: String, in cell: XCUIElement) -> XCUIElement {
        cell.descendants(matching: .any)[AccessibilityID.calendarChip(title)]
    }

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

    private var detailSheet: XCUIElement {
        app.descendants(matching: .any)[AccessibilityID.cardDetailSheet]
    }

    /// POSIX + LOCAL time zone, byte-matching the app's cell-id/title formatters.
    private static let isoDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = .current
        return formatter
    }()

    private static let wireMonthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM"
        formatter.timeZone = .current
        return formatter
    }()
}
