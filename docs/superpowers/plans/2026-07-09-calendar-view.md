# Calendar View (M-D) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The per-board view-mode seam (M-C) gains a third mode — a month-grid Calendar View of the SELECTED board. The grid is a 7-column LazyVGrid (weeks as rows) anchored on the current month, with prev/today/next navigation and a machine-readable month title; each in-month day cell shows its day number, up to 3 compact card chips (timed cards prefixed with their time), and a "+N" overflow; today's cell is visually ringed; undated cards live in a compact trailing "No Date" rail (never hidden). Chips select on click and open the standard `CardDetailView` sheet on double-click. Drag-to-reschedule is IN scope: dropping any card chip (or a No-Date rail row) on a day cell calls `store.setDueDate` with the cell's day, PRESERVING a timed card's wall-clock time — and `setDueDate` gains a same-value guard so dropping a card on its own day registers no junk undo step. The mode is switched by a third toolbar segment and a new View ▸ "as Calendar" item (⌥⌘C), persists per board through the existing M-C map, and honestly disables creation, ⌘-arrow moves, the label filter, AND bare-arrow selection navigation (a new `canNavigateSelection` flag — calendar v1 has no arrow-key model).

**Architecture:** M-D extends the M-C seam without re-plumbing anything: `BoardViewMode` gains `case calendar` (raw `"calendar"` — wire format in the persisted defaults string AND the `view-mode-value` marker; the M-C decoder's tolerant-drop posture means a downgraded build silently falls back to `.board`, never crashes), `RootView.detailContent` becomes a three-way switch, the segmented Picker gains a third segment, and the `view-mode-value` marker needs ZERO changes (it already publishes `rawValue`). The month math is pure: `CalendarMonthGrid` (in `CalendarReschedule.swift` — two related pure enums in one Store file, the `ListBucket.swift` precedent) computes the displayed cells (`monthStart`, `days(anchoredAt:calendar:)` — always whole weeks from the calendar's `firstWeekday`, leading/trailing adjacent-month days flagged `isInDisplayedMonth == false`) and the rotated weekday header symbols; `CalendarReschedule.retargetedDueDate(original:includesTime:onto:calendar:)` is the drop's date math (date-only → target start-of-day; timed → original hour/minute re-anchored on the target day via `bySettingHour`, seconds normalized to :00). **DayCellID resolution:** day cells are DATE-keyed, not synthetic-UUID-keyed — the M-C `snapshotID` trick existed solely to feed `SelectionNavigation` a `BoardSnapshot`, and calendar v1 deliberately does NOT use `SelectionNavigation` (bare-arrow `moveSelection` is a published no-op behind `canNavigateSelection: false` — a month grid needs 2D day-cell navigation, not the card-list walk, and faking it would be worse than honestly disabling it). So there is no `BoardSnapshot` bridge, no `[UUID: Date]` side table, and no UUID scheme at all: `CalendarMonthGrid.Day` is `Identifiable` by its start-of-day `Date`, and the accessibility ids are the POSIX-formatted day string (`calendar-day-<yyyy-MM-dd>`). **Clock resolution (explicit, per coordinator):** there is NO `--now` launch argument and NO `AppClock` in v1 — an injected clock would desynchronize the month anchor from the fixture's launch-relative real-`Date()` due dates (seeded with the real clock at launch), which is exactly backwards; instead the view anchors on real `Date()`, and the UI tests compute expected day-cell ids from `Date()` at test runtime with the same relative deltas the fixture uses (−1/0/+1/+5), skipping via `XCTSkipIf` any assertion whose relative day falls outside the currently displayed month (deterministic, documented). Across-midnight runs remain the already-documented fixture-relative flake class — noted and accepted. The ONE store change is the `setDueDate` same-value guard (the `editBoard`/`applyCardEdits` no-change-no-group discipline, ported): the normalized (dueDate, includesTime, durationMinutes) trio is diffed against the card before any undo group opens. Drop architecture honors the CLAUDE.md invariant: each in-month day cell is exactly ONE `.dropDestination(for: CardTransfer.self)` (cells never see ListTransfer — there is nothing list-shaped to drop on a day), dimmed adjacent-month cells get NO destination, no id, and no chips. UI-test strategy mirrors M-C: mouse-driven e2es through the toolbar segment + marker oracle; the ⌥⌘C menu path and the honest-disable enablement asserts are deliberately NOT e2e'd (degraded-keyboard host) — human checklist + fresh-session run.

**Tech Stack:** SwiftUI (macOS 14), SwiftData, XCUITest, Swift Testing, xcodegen.

## Global Constraints

- Every bare `xcodebuild` needs `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`; `pkill -f xcodebuild; pkill -f Tack.app` before every run; FOREGROUND runs; judge only by the log tail; every `TackUITests` invocation carries `-parallel-testing-enabled NO`.
- A unit-test run past ~6 minutes is a **hang, not a slow run** (classically an NSUndoManager registration outside explicit grouping) — kill it and read the log tail for a FAULT line.
- **File accounting (`Tack.xcodeproj` is generated — `make gen` REQUIRED after every file-set change, i.e. in Tasks 0 and 2, before building):** Task 0 adds `Tack/Store/CalendarReschedule.swift` and `TackTests/CalendarRescheduleTests.swift`; Task 2 adds `Tack/Views/Board/CalendarBoardView.swift` and `TackUITests/CalendarViewUITests.swift`. Tasks 1 and 3 add NO files. Any other file creation means you've drifted — stop and re-read the task. New `AccessibilityID` constants need NO project change (`AccessibilityID.swift` is compiled into both the app and TackUITests targets per `project.yml`).
- **The fixture roster is LOAD-BEARING and this milestone does not touch `FixtureSeeder` at all.** The 5 Groceries cards map onto the calendar as: Buy milk = yesterday's cell, Call plumber = today's cell, Return library books = tomorrow's cell, Write report = the +5d cell (timed 14:00, 60 min), Book flights = the No Date rail. All dates are launch-relative REAL now, so every dated card is in the CURRENT month **except near month boundaries** — tests MUST compute expected cells from the same relative deltas at runtime and `XCTSkipIf` boundary-crossing assertions; NEVER hardcode day numbers or month names.
- Signature discipline (type-consistent across all tasks): `BoardViewMode.calendar`'s raw value `"calendar"` is wire format (defaults string + `view-mode-value` marker) — never rename. `CalendarReschedule.retargetedDueDate(original: Date?, includesTime: Bool, onto: Date, calendar: Calendar) -> Date` is total (nil original → target start-of-day). `BoardActions.canNavigateSelection` is a defaulted `var canNavigateSelection: Bool = true` (a defaulted `let` drops out of the memberwise init — the documented `canFilter` reasoning), so `BoardView`'s and `ListBoardView`'s constructions compile unchanged. Day-cell ids use POSIX `yyyy-MM-dd`, LOCAL time zone (the `DueDateBadge.isoDateFormatter` rationale: dueDate is stored as LOCAL start-of-day); the month title's machine value uses POSIX `yyyy-MM`; the chip wire value is `"<HH:mm>|<title>"` for timed cards (POSIX `HH:mm`, the `DueDateBadge.wireTimeFormatter` grammar) and bare `"<title>"` otherwise.
- **No new TextField/TextEditor anywhere in this milestone** — zero new `reportsTextInputFocus()` sites, and (launch-focus pitfall) no `.focused()` bindings anywhere. Chips and rail rows are plain `Text`; all editing goes through the reused `CardDetailView` sheet.
- Ancestor-id-shadowing discipline (the M2 trap) for every new identifier: a day cell is an `.accessibilityElement(children: .contain)` container carrying `calendar-day-<yyyy-MM-dd>` — the PROVEN `card(_:)`/`list(_:)` container shape whose children stay queryable (chips are found via `cell.descendants`), NOT a bare `.accessibilityIdentifier` on an unmarked ancestor. `calendar-month-title` and the chip ids live on `.accessibilityRepresentation` Texts (the `boardThemeValue`/`DueDateBadge` pattern); `calendar-nodate-header` lives on the rail's header `HStack` — a SIBLING of the rail rows, never a container around them. Prefixes `calchip-`/`calrow-` (never `card-`) keep `cardIdentifiersByPosition`'s `BEGINSWITH "card-"` scan clean.
- **Drop-destination shadowing invariant (CLAUDE.md, restated as its own rule):** SwiftUI `.dropDestination` does not dispatch by payload type — a destination swallows every drag landing on it, and stacked different-typed destinations shadow each other. Day cells therefore accept `CardTransfer` ONLY, exactly ONE `.dropDestination` per cell, never stacked with another typed destination; dimmed adjacent-month cells get NO destination at all. Do not "improve" this into per-payload stacks.
- **Drag tests must poll the postcondition before any retry** (CLAUDE.md pitfall): every e2e drag goes through `TackUITestCase.drag(_:to:targetNormalizedOffset:until:)` with a real postcondition closure — an instant `.exists` check triggers a spurious second drag that corrupts state. Never call `press(forDuration:thenDragTo:)` raw.
- `BoardStore` changes are EXACTLY the `setDueDate` same-value guard — nothing else. The schema, the export format, and `FixtureSeeder` are all UNTOUCHED (per the locked feature review: calendar mode is view state, not a format-touching feature). If a task seems to need more store surface, stop — the design routes every calendar mutation through `setDueDate`/`deleteCard`/`applyCardEdits`.
- The environmental keyboard/menu UI-test failure mode can be active on this host. Keyboard/menu-gated suites (`KeyboardShortcutUITests`, `LabelFilterUITests`) are NOT gates for this plan; the gates are the unit suite + the mouse-driven suites (CalendarViewUITests, ListViewUITests, CardDetailUITests, BadgeUITests). Before debugging any red keyboard-driven test, control-run it against committed (known-green) code — if the control fails, it's the environment.
- Commit style: short imperative summary, body optional, `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>` trailer.

---

### Task 0: `.calendar` mode + `CalendarReschedule`/`CalendarMonthGrid` pure logic + `setDueDate` guard (unit TDD)

**Files:**
- Modify: `Tack/Store/BoardViewMode.swift` (add `case calendar`)
- Create: `Tack/Store/CalendarReschedule.swift` (two pure enums — the `ListBucket.swift` two-enums-one-file precedent)
- Modify: `Tack/Store/BoardStore.swift` (`setDueDate` same-value guard)
- Create: `TackTests/CalendarRescheduleTests.swift`
- Test (modify): `TackTests/ListBucketTests.swift` (append one codec test to `BoardViewModeCodecTests`)
- Test (modify): `TackTests/LabelTests.swift` (append the guard tests beside the existing `setDueDate` suite)
- `make gen` twice (after the test file, after the source file).

**Interfaces:**
- Consumes: `Calendar` (Foundation only — both new enums are pure), `BoardStore.withUndoGroup`/the `editBoard` no-change-no-group precedent.
- Produces: `BoardViewMode.calendar`; `CalendarReschedule.retargetedDueDate(original:includesTime:onto:calendar:)`; `CalendarMonthGrid.Day` / `.monthStart(containing:calendar:)` / `.days(anchoredAt:calendar:)` / `.weekdayHeaders(calendar:)` — all consumed by Task 2's view; the guarded `setDueDate` consumed by Task 2's drop handler. Adding `case calendar` in this task is compile-safe: `RootView`'s mode check is an if/else (not an exhaustive switch) and nothing sets `.calendar` until Task 1.

- [ ] **Step 1: Write the failing tests**

Append to `TackTests/ListBucketTests.swift`, inside `BoardViewModeCodecTests` (below `malformedDropped` — which already proves the tolerance story: its `"=grid"` entry shows unknown modes drop silently, so an M-C-era decoder reading a `"calendar"` entry falls back to `.board`, never crashes):

```swift
    @Test("M-D: calendar round-trips; its raw value is wire format")
    func calendarRoundTrips() {
        let a = UUID(uuidString: "AAAAAAAA-0000-4000-8000-000000000000")!
        let b = UUID(uuidString: "BBBBBBBB-0000-4000-8000-000000000000")!
        let map: [UUID: BoardViewMode] = [a: .calendar, b: .list]
        #expect(BoardViewMode.decode(BoardViewMode.encode(map)) == map)
        #expect(BoardViewMode.encode([a: .calendar]) == "\(a.uuidString)=calendar",
                "raw value 'calendar' appears verbatim in the persisted string — wire format")
    }
```

Create `TackTests/CalendarRescheduleTests.swift`:

```swift
import Testing
import Foundation
@testable import Tack

/// M-D: the drop-to-reschedule date math. Fixed-clock style (UTC gregorian) copied from
/// DueDateStatusTests/ListBucketTests so the three suites' date math reads identically.
@Suite("CalendarReschedule")
struct CalendarRescheduleTests {
    var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }

    func date(_ year: Int, _ month: Int, _ day: Int,
              _ hour: Int = 0, _ minute: Int = 0, _ second: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day,
                                           hour: hour, minute: minute, second: second))!
    }

    @Test("date-only card onto a new day lands on that day's start-of-day")
    func dateOnlyRetargets() {
        #expect(CalendarReschedule.retargetedDueDate(original: date(2026, 7, 4),
                                                     includesTime: false,
                                                     onto: date(2026, 7, 10),
                                                     calendar: calendar) == date(2026, 7, 10))
    }

    @Test("nil original (a No-Date rail drag) lands on the target's start-of-day, whatever the flag says")
    func nilOriginalRetargets() {
        #expect(CalendarReschedule.retargetedDueDate(original: nil, includesTime: false,
                                                     onto: date(2026, 7, 10), calendar: calendar)
                == date(2026, 7, 10))
        // Degenerate flag combination (includesTime true with no original time to preserve):
        // still total, still the target's start-of-day — never a crash, never a stray time.
        #expect(CalendarReschedule.retargetedDueDate(original: nil, includesTime: true,
                                                     onto: date(2026, 7, 10), calendar: calendar)
                == date(2026, 7, 10))
    }

    @Test("timed card keeps its wall-clock time on the new day (the 14:00 rule)")
    func timedKeepsWallClock() {
        #expect(CalendarReschedule.retargetedDueDate(original: date(2026, 7, 4, 14, 0),
                                                     includesTime: true,
                                                     onto: date(2026, 7, 10),
                                                     calendar: calendar) == date(2026, 7, 10, 14, 0))
    }

    @Test("timed card dropped on its own day retargets byte-identically (feeds the setDueDate no-op guard)")
    func sameDayTimedIsIdentity() {
        let original = date(2026, 7, 4, 14, 0)
        #expect(CalendarReschedule.retargetedDueDate(original: original, includesTime: true,
                                                     onto: date(2026, 7, 4), calendar: calendar)
                == original)
    }

    @Test("seconds are normalized to :00 on retarget (documented; every UI-creatable slot is minute-precision)")
    func secondsZeroed() {
        #expect(CalendarReschedule.retargetedDueDate(original: date(2026, 7, 4, 14, 0, 37),
                                                     includesTime: true,
                                                     onto: date(2026, 7, 10),
                                                     calendar: calendar) == date(2026, 7, 10, 14, 0, 0))
    }

    @Test("a mid-day target timestamp is normalized to its start-of-day first")
    func midDayTargetNormalized() {
        #expect(CalendarReschedule.retargetedDueDate(original: date(2026, 7, 4, 14, 0),
                                                     includesTime: true,
                                                     onto: date(2026, 7, 10, 11, 45),
                                                     calendar: calendar) == date(2026, 7, 10, 14, 0))
    }
}

/// M-D: the month grid's cell math. Weekday facts used below (verifiable by hand from
/// 2026-01-01 = Thursday): Feb 1 2026 = Sunday (a 28-day month starting on Sunday — the exact
/// 4-week grid), Jul 1 2026 = Wednesday, Jul 31 2026 = Friday.
@Suite("CalendarMonthGrid")
struct CalendarMonthGridTests {
    func calendar(firstWeekday: Int) -> Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        cal.firstWeekday = firstWeekday // pinned explicitly — the default is locale-dependent
        return cal
    }

    func date(_ year: Int, _ month: Int, _ day: Int, in cal: Calendar) -> Date {
        cal.date(from: DateComponents(year: year, month: month, day: day))!
    }

    @Test("monthStart of a mid-month timestamp is the 1st at midnight")
    func monthStartMidMonth() {
        let cal = calendar(firstWeekday: 1)
        let midMonth = cal.date(from: DateComponents(year: 2026, month: 7, day: 9, hour: 15, minute: 30))!
        #expect(CalendarMonthGrid.monthStart(containing: midMonth, calendar: cal) == date(2026, 7, 1, in: cal))
    }

    @Test("July 2026, Sunday-start: 35 cells, Jun 28 through Aug 1, 3 leading + 1 trailing dimmed")
    func july2026SundayStart() {
        let cal = calendar(firstWeekday: 1)
        let days = CalendarMonthGrid.days(anchoredAt: date(2026, 7, 1, in: cal), calendar: cal)

        #expect(days.count == 35)
        #expect(days.first?.date == date(2026, 6, 28, in: cal), "grid opens on the week's first day")
        #expect(days.last?.date == date(2026, 8, 1, in: cal), "grid closes on the week's last day")
        #expect(days.prefix(3).allSatisfy { !$0.isInDisplayedMonth }, "Jun 28–30 are dimmed fillers")
        #expect(days[3].isInDisplayedMonth && days[3].date == date(2026, 7, 1, in: cal))
        #expect(days.suffix(1).allSatisfy { !$0.isInDisplayedMonth }, "Aug 1 is a dimmed filler")
        #expect(days.filter(\.isInDisplayedMonth).count == 31)
    }

    @Test("February 2026, Sunday-start: the exact 4-week month — 28 cells, zero fillers")
    func february2026ExactWeeks() {
        let cal = calendar(firstWeekday: 1)
        let days = CalendarMonthGrid.days(anchoredAt: date(2026, 2, 1, in: cal), calendar: cal)

        #expect(days.count == 28)
        #expect(days.allSatisfy(\.isInDisplayedMonth))
        #expect(days.first?.date == date(2026, 2, 1, in: cal))
        #expect(days.last?.date == date(2026, 2, 28, in: cal))
    }

    @Test("July 2026, Monday-start: the grid shifts with firstWeekday — Jun 29 through Aug 2")
    func july2026MondayStart() {
        let cal = calendar(firstWeekday: 2)
        let days = CalendarMonthGrid.days(anchoredAt: date(2026, 7, 1, in: cal), calendar: cal)

        #expect(days.count == 35)
        #expect(days.first?.date == date(2026, 6, 29, in: cal))
        #expect(days.last?.date == date(2026, 8, 2, in: cal))
        #expect(days.prefix(2).allSatisfy { !$0.isInDisplayedMonth })
        #expect(days.suffix(2).allSatisfy { !$0.isInDisplayedMonth })
    }

    @Test("grid invariants hold for every month of 2026–2027 (whole weeks, each month day exactly once)")
    func gridInvariantsSweep() {
        for firstWeekday in [1, 2] {
            let cal = calendar(firstWeekday: firstWeekday)
            for year in [2026, 2027] {
                for month in 1...12 {
                    let anchor = date(year, month, 1, in: cal)
                    let days = CalendarMonthGrid.days(anchoredAt: anchor, calendar: cal)
                    let expectedCount = cal.range(of: .day, in: .month, for: anchor)!.count
                    #expect(days.count % 7 == 0, "\(year)-\(month) fw\(firstWeekday): whole weeks only")
                    #expect(days.filter(\.isInDisplayedMonth).count == expectedCount,
                            "\(year)-\(month) fw\(firstWeekday): every in-month day exactly once")
                    #expect(cal.component(.weekday, from: days.first!.date) == firstWeekday,
                            "\(year)-\(month) fw\(firstWeekday): grid opens on the calendar's first weekday")
                }
            }
        }
    }

    @Test("weekday headers rotate with firstWeekday")
    func weekdayHeadersRotate() {
        let sundayFirst = CalendarMonthGrid.weekdayHeaders(calendar: calendar(firstWeekday: 1))
        let mondayFirst = CalendarMonthGrid.weekdayHeaders(calendar: calendar(firstWeekday: 2))
        #expect(sundayFirst.count == 7 && mondayFirst.count == 7)
        #expect(mondayFirst == Array(sundayFirst[1...] + sundayFirst[..<1]),
                "Monday-start is the Sunday-start list rotated by one")
    }

    @Test("month navigation from a month-start anchor is exact (no Jan-31 clamping drift)")
    func monthNavigationArithmetic() {
        let cal = calendar(firstWeekday: 1)
        let jan = date(2026, 1, 1, in: cal)
        let next = cal.date(byAdding: .month, value: 1, to: jan)!
        #expect(CalendarMonthGrid.monthStart(containing: next, calendar: cal) == date(2026, 2, 1, in: cal),
                "the view only ever adds months to a month-START anchor, so navigation can't drift")
    }
}
```

Append to `TackTests/LabelTests.swift` (below the existing `setDueDate` tests, same suite):

```swift
    // MARK: - M-D: setDueDate same-value guard

    @Test("setDueDate with an identical resulting trio registers no undo step and keeps updatedAt")
    func setDueDateSameValueIsNoOp() {
        let env = TestContainer(withUndo: true)
        let board = env.store.createBoard(name: "B", emoji: nil)
        let card = env.store.addCard(to: board.sortedLists[0], title: "Card")
        let day = Calendar.current.startOfDay(for: .now)
        env.store.setDueDate(day, on: card)
        env.undoManager?.removeAllActions()
        let stamp = card.updatedAt

        env.store.setDueDate(day, on: card) // same resulting (dueDate, includesTime, duration) trio

        #expect(env.undoManager?.canUndo == false,
                "dropping a card on its own day must not register a junk undo step")
        #expect(card.updatedAt == stamp, "a no-change call must not bump updatedAt either")
    }

    @Test("the guard compares the NORMALIZED trio: same-day date-only re-set at a different clock time is a no-op")
    func setDueDateSameDayDifferentClockTimeIsNoOp() {
        let env = TestContainer(withUndo: true)
        let board = env.store.createBoard(name: "B", emoji: nil)
        let card = env.store.addCard(to: board.sortedLists[0], title: "Card")
        let day = Calendar.current.startOfDay(for: .now)
        env.store.setDueDate(day, on: card)
        env.undoManager?.removeAllActions()

        // 15:30 on the same day normalizes to the same start-of-day — identical trio.
        env.store.setDueDate(day.addingTimeInterval(15.5 * 3600), on: card)

        #expect(env.undoManager?.canUndo == false)
        #expect(card.dueDate == day)
    }

    @Test("timed same trio is a no-op; changing only the duration still registers")
    func setDueDateTimedGuardAndDurationChange() {
        let env = TestContainer(withUndo: true)
        let board = env.store.createBoard(name: "B", emoji: nil)
        let card = env.store.addCard(to: board.sortedLists[0], title: "Card")
        let slot = Calendar.current.date(bySettingHour: 14, minute: 0, second: 0, of: .now)!
        env.store.setDueDate(slot, on: card, includesTime: true, durationMinutes: 60)
        env.undoManager?.removeAllActions()

        env.store.setDueDate(slot, on: card, includesTime: true, durationMinutes: 60)
        #expect(env.undoManager?.canUndo == false, "identical timed trio → no undo step")

        env.store.setDueDate(slot, on: card, includesTime: true, durationMinutes: 30)
        #expect(env.undoManager?.canUndo == true, "a real duration change still registers")
        #expect(card.durationMinutes == 30)
    }

    @Test("nil-to-nil is a no-op")
    func setDueDateNilToNilIsNoOp() {
        let env = TestContainer(withUndo: true)
        let board = env.store.createBoard(name: "B", emoji: nil)
        let card = env.store.addCard(to: board.sortedLists[0], title: "Card") // dueDate starts nil
        env.undoManager?.removeAllActions()

        env.store.setDueDate(nil, on: card)

        #expect(env.undoManager?.canUndo == false)
    }
```

- [ ] **Step 2: Run to verify failure**

```bash
pkill -f xcodebuild; pkill -f Tack.app
make gen
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild -project Tack.xcodeproj -scheme Tack \
  -destination "platform=macOS,arch=$(uname -m)" -derivedDataPath .build/DerivedData \
  -only-testing:TackTests/CalendarRescheduleTests -only-testing:TackTests/CalendarMonthGridTests \
  -only-testing:TackTests/BoardViewModeCodecTests -only-testing:TackTests/LabelTests \
  test 2>&1 | tee .build/md-task0-red.log
```
Expected: compile FAILURE (`CalendarReschedule`/`CalendarMonthGrid` and `.calendar` don't exist) — the red state. The guard tests would fail at RUNTIME (`canUndo == true`) once compilation is fixed; the compile red dominates first.

- [ ] **Step 3: Implement**

`Tack/Store/BoardViewMode.swift` — add the case (and extend the type doc's first line to mention the month calendar):

```swift
enum BoardViewMode: String {
    case board
    case list
    /// M-D: the month-grid Calendar View. Raw value "calendar" is wire format like its siblings
    /// (persisted defaults string + view-mode-value marker). Downgrade posture: the M-C decoder
    /// drops unknown modes silently (see `decode`), so a defaults string containing "calendar"
    /// read by an older build falls back to `.board` — tolerated by design, never a crash.
    case calendar
```

Create `Tack/Store/CalendarReschedule.swift`:

```swift
import Foundation

/// M-D: pure calendar-view math — this file hosts TWO related pure enums (the `ListBucket.swift`
/// precedent: bucket + snapshot builder share a file), both Foundation-only and clock-injected
/// for exhaustive unit testing.

/// The drop-to-reschedule date math: what `dueDate` a card should get when dropped on a day cell.
enum CalendarReschedule {
    /// Retargets `original` onto the calendar day containing `day` (normalized to start-of-day
    /// first — a cell's date is always a start-of-day, but the function doesn't rely on it).
    ///
    /// - Date-only cards (`includesTime == false`) and nil originals (a No-Date rail drag, or the
    ///   degenerate timed-with-no-date combination) land on the target's start-of-day — which is
    ///   exactly what `BoardStore.setDueDate`'s date-only normalization would produce anyway, so
    ///   the store's same-value guard sees a byte-identical trio for a same-day drop.
    /// - Timed cards keep their wall-clock hour/minute on the new day (dropping a 14:00 card on
    ///   Thursday means 14:00 Thursday), via `bySettingHour` on the target's start-of-day.
    ///   Seconds are normalized to :00 — every UI-creatable slot is minute-precision (the M-B
    ///   time field), so a same-day drop of any real card is still an exact identity.
    static func retargetedDueDate(original: Date?, includesTime: Bool, onto day: Date,
                                  calendar: Calendar) -> Date {
        let targetDay = calendar.startOfDay(for: day)
        guard includesTime, let original else { return targetDay }
        let time = calendar.dateComponents([.hour, .minute], from: original)
        return calendar.date(bySettingHour: time.hour ?? 0, minute: time.minute ?? 0,
                             second: 0, of: targetDay) ?? targetDay
    }
}

/// The month grid's cell math. Day cells are DATE-keyed (`Day.id` is the start-of-day `Date`) —
/// deliberately NOT the M-C synthetic-UUID trick: that existed solely to feed SelectionNavigation
/// a BoardSnapshot, and calendar v1 doesn't use SelectionNavigation at all (bare-arrow selection
/// is honestly disabled via `BoardActions.canNavigateSelection`; see `CalendarBoardView`).
enum CalendarMonthGrid {
    /// One grid cell. `isInDisplayedMonth == false` marks the leading/trailing filler days from
    /// adjacent months — rendered dimmed, NON-interactive (no id, no chips, no drop destination).
    struct Day: Equatable, Identifiable {
        let date: Date
        let isInDisplayedMonth: Bool
        var id: Date { date }
    }

    /// The first instant of the month containing `date` — the ONLY shape a month anchor is ever
    /// stored in (`CalendarBoardView.monthAnchor`), so prev/next navigation (`byAdding: .month`)
    /// can never hit the Jan-31 clamping drift.
    static func monthStart(containing date: Date, calendar: Calendar) -> Date {
        calendar.dateInterval(of: .month, for: date)?.start ?? calendar.startOfDay(for: date)
    }

    /// Every cell of the displayed month's grid, in row order: whole weeks from the calendar's
    /// `firstWeekday`, spanning the week containing the 1st through the week containing the last
    /// day of the month. Always a multiple of 7 (28–42 cells).
    static func days(anchoredAt anchor: Date, calendar: Calendar) -> [Day] {
        let start = monthStart(containing: anchor, calendar: calendar)
        guard let dayCount = calendar.range(of: .day, in: .month, for: start)?.count,
              let monthEnd = calendar.date(byAdding: .day, value: dayCount - 1, to: start),
              let gridStart = calendar.dateInterval(of: .weekOfYear, for: start)?.start,
              let gridEnd = calendar.dateInterval(of: .weekOfYear, for: monthEnd)?.end else {
            return []
        }
        var days: [Day] = []
        var cursor = gridStart
        while cursor < gridEnd {
            days.append(Day(date: cursor,
                            isInDisplayedMonth: calendar.isDate(cursor, equalTo: start,
                                                                toGranularity: .month)))
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        return days
    }

    /// The 7 column headers (very-short weekday symbols), rotated so index 0 is the calendar's
    /// `firstWeekday` — `veryShortWeekdaySymbols` is ALWAYS Sunday-first regardless of locale.
    static func weekdayHeaders(calendar: Calendar) -> [String] {
        let symbols = calendar.veryShortWeekdaySymbols
        let shift = (calendar.firstWeekday - 1) % symbols.count
        return Array(symbols[shift...] + symbols[..<shift])
    }
}
```

`Tack/Store/BoardStore.swift` — restructure `setDueDate` (normalization hoisted above the group so the guard and the writes share one computation; the `editBoard`/`applyCardEdits` no-change-no-group discipline):

```swift
    /// One undo step ("Set Due Date"). Date-only calls (the defaults — every pre-M-B call site)
    /// normalize to local start-of-day with `includesTime` false, exactly as before. Timed calls
    /// (M-B) store the raw wall-clock `date` with `includesTime` true. `durationMinutes` is kept
    /// only when the call is timed AND the value is positive — nil otherwise, so a date-only card
    /// can never carry a stray duration and a zero/negative slot is never persisted.
    ///
    /// M-D: a call whose NORMALIZED (dueDate, includesTime, durationMinutes) trio already matches
    /// the card opens no undo group, does not save, and does not bump `updatedAt` (the
    /// `editBoard`/`applyCardEdits` discipline) — without this, dropping a calendar chip on its
    /// own day would register a junk undo step that makes the next ⌘Z a silent no-op.
    func setDueDate(_ date: Date?, on card: Card, includesTime: Bool = false, durationMinutes: Int? = nil) {
        let normalizedIncludesTime = date != nil && includesTime
        let normalizedDueDate = date.map { normalizedIncludesTime ? $0 : Calendar.current.startOfDay(for: $0) }
        let normalizedDuration = (normalizedIncludesTime && (durationMinutes ?? 0) > 0) ? durationMinutes : nil

        guard normalizedDueDate != card.dueDate
                || normalizedIncludesTime != card.includesTime
                || normalizedDuration != card.durationMinutes else { return }

        withUndoGroup("Set Due Date") {
            card.dueDate = normalizedDueDate
            card.includesTime = normalizedIncludesTime
            card.durationMinutes = normalizedDuration
            card.updatedAt = .now
            save()
        }
    }
```

- [ ] **Step 4: Run to verify pass**

Same command as Step 2 (log `.build/md-task0-green.log`; `make gen` again — Step 3 changed the file set). Expected: `** TEST SUCCEEDED **` — 6 CalendarReschedule + 7 CalendarMonthGrid + the extended codec suite + the extended Labels suite (all pre-existing `setDueDate` tests must still pass: every one of them changes at least one leg of the trio, so the guard never fires for them).

- [ ] **Step 5: Run the FULL unit suite**

```bash
pkill -f xcodebuild; pkill -f Tack.app; make unit 2>&1 | tee .build/md-task0-unit.log
```
Expected: `** TEST SUCCEEDED **`. This is the guard's real gate: `FixtureSeederTests`, `UndoRedoTests`, and `BoardStoreCardTests` all call `setDueDate` and must be behaviorally untouched (fixture seeding always sets nil→value; undo tests always change values).

- [ ] **Step 6: Commit**

```bash
git add Tack/Store/BoardViewMode.swift Tack/Store/CalendarReschedule.swift Tack/Store/BoardStore.swift TackTests/CalendarRescheduleTests.swift TackTests/ListBucketTests.swift TackTests/LabelTests.swift
git commit -m "Calendar pure logic: month grid math, drop retargeting, setDueDate guard (M-D)

CalendarMonthGrid computes whole-week month cells (date-keyed, no
synthetic ids — calendar v1 doesn't use SelectionNavigation) and rotated
weekday headers; CalendarReschedule preserves a timed card's wall-clock
time across day drops. setDueDate now diffs the normalized trio and
opens no undo group on a no-change call (the editBoard discipline), so
dropping a chip on its own day can't register a junk undo step.
BoardViewMode gains the 'calendar' wire value (tolerantly dropped by
older decoders).

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 1: seam extension (third segment, ⌥⌘C menu item, `canNavigateSelection` — build gate)

**Files:**
- Modify: `Tack/Commands/FocusedValues.swift` (`BoardActions.canNavigateSelection`)
- Modify: `Tack/Commands/AppCommands.swift` (View ▸ "as Calendar" ⌥⌘C; bare-arrow honesty gates)
- Modify: `Tack/Views/RootView.swift` (third Picker segment; `detailContent` three-way switch with a temporary `.calendar` → `BoardView` arm)
- Modify: `TackUITests/ListViewUITests.swift` (ONE line: the segment-click coordinate fallback, invalidated by the third segment)

No new files → no `make gen` in this task. No unit tests either — everything here is view/command wiring with no pure logic (M-C's Task 1 had `viewModeDefaultsKey`; M-D reuses that key untouched, and there are no new launch arguments per the Architecture clock resolution). The gates are the full unit suite, a build, and one UI-suite regression run.

**Interfaces:**
- Consumes: `BoardViewMode.calendar` (Task 0); the M-C seam (`viewModes` triad, `setViewMode`, `viewModeBinding`, the marker — ALL unchanged: the marker publishes `selectedBoardViewMode.rawValue`, so it reports `"calendar"` for free; verify by reading, not by editing).
- Produces: `BoardActions.canNavigateSelection: Bool` (defaulted `true`; Task 2's `CalendarBoardView` passes `false`); the ⌥⌘C item and the third segment. Task 2 consumes the `.calendar` switch arm (a one-line swap) — in THIS task `.calendar` still renders `BoardView`, so the seam ships green without the view. KNOWN, temporary, honest (the M-C Task 1 posture verbatim): with a board switched to calendar mode during this window, `view-mode-value` reads `"calendar"` while the canvas still renders — the marker reports the MODE, not the view; Task 2 closes the gap.

- [ ] **Step 1: `FocusedValues.swift` — the honesty flag**

In `BoardActions`, add after `canCreateList` (the fourth flag in the family):

```swift
    /// M-D: whether View ▸ Select Next/Previous/Left/Right (bare arrows) apply to the current
    /// board surface. Calendar mode has no arrow-key selection model in v1 — a month grid wants
    /// 2D day-cell navigation, not the card-list walk `SelectionNavigation` implements, and
    /// faking one would be worse than none — so `CalendarBoardView` passes `false` to disable
    /// the four items HONESTLY instead of leaving them enabled-but-inert (the
    /// canFilter/canMoveCards/canCreateList precedent, one more time). Defaulted `true` so
    /// `BoardView`'s and `ListBoardView`'s constructions are untouched — same
    /// defaulted-`var`-not-`let` reasoning as `canFilter` (a defaulted `let` drops out of the
    /// memberwise init).
    var canNavigateSelection: Bool = true
```

- [ ] **Step 2: `AppCommands.swift` — menu item + arrow gates**

1. Insert "as Calendar" directly after the "as List" button (before that group's trailing `Divider()`), and extend the M-C shortcut-table comment above "as Board" to cover ⌥⌘C:

```swift
            // M-C/M-D: per-board view mode. Sentence-style titles under the View menu ("View as
            // Board"). ⌥⌘B / ⌥⌘L / ⌥⌘C — all free in the shortcut table (⌘1–9, ⌘N-family,
            // ⇧⌘E/I, ⌃⌘S, ⌘F, ⌘O, ⌘-arrows and bare arrows are all taken; these three are not).
            // ⌥⌘C specifically: the only system claimant is Format ▸ "Copy Style", and Tack has
            // no Format menu (no TextFormattingCommands installed) — verified by grepping every
            // `keyboardShortcut` in the app (only sheet default/cancel actions outside this
            // file) and by walking the running app's menus; the human checklist re-confirms no
            // duplicate-shortcut beep. Enabled whenever boards exist; `setViewMode` itself
            // no-ops without a selected board (the `guardedMutation` belt-and-suspenders
            // posture New Board already uses).
```

```swift
            Button("as Calendar") { guardedMutation { boardSelection?.setViewMode(.calendar) } }
                .keyboardShortcut("c", modifiers: [.command, .option])
                .disabled(boardSelection == nil || boardSelection?.boardNames.isEmpty == true)
```

2. All FOUR bare-arrow buttons ("Select Previous Card" / "Select Next Card" / "Select Card Left" / "Select Card Right") gain the honesty gate — each `.disabled` becomes:

```swift
                .disabled(boardActions == nil || isTextInputActive
                          || boardActions?.canNavigateSelection == false)
```

(Keep the existing comment block above "Select Previous Card"; append one sentence to it: `// M-D: canNavigateSelection honestly disables all four in calendar mode, which has no arrow-key selection model in v1.`)

- [ ] **Step 3: `RootView.swift` — segment + branch**

1. The toolbar Picker gains a third segment after the List segment (and its `.help` copy is extended):

```swift
                        Image(systemName: "calendar")
                            .accessibilityLabel("Calendar")
                            .tag(BoardViewMode.calendar)
```

```swift
                    .help("Show the selected board as columns, a due-date list, or a month calendar")
```

2. `detailContent`'s seam branch becomes a three-way switch (exhaustive — the compiler now enforces that a fourth mode can't ship without a view decision):

```swift
        } else if let selectedBoard {
            // M-C/M-D: the view-mode seam. The views are different TYPES in this switch, so
            // switching modes tears down the old view's @State (board-local selection, filter
            // bar, month anchor) — accepted and honest: a mode switch is a context switch.
            switch selectedBoardViewMode {
            case .list:
                ListBoardView(board: selectedBoard, store: store)
            case .calendar:
                // M-D Task 1: temporary — the calendar view lands in Task 2 (CalendarBoardView);
                // until then calendar mode renders the board canvas so the seam (third segment,
                // menu item, persistence through the existing map, marker) ships green without
                // the view. KNOWN + temporary: view-mode-value honestly reads "calendar" while
                // the canvas still renders.
                BoardView(board: selectedBoard, store: store)
            case .board:
                BoardView(board: selectedBoard, store: store)
            }
        } else {
```

Nothing else in `RootView` changes: `viewModes`/`viewModesRaw`/`setViewMode`/`viewModeBinding`/`restoreViewModesIfNeeded`, the `--reset` clearing in `TackApp`, and the `view-mode-value` marker are all mode-agnostic already — READ them to confirm, do not edit them.

- [ ] **Step 4: `ListViewUITests.swift` — fix the invalidated coordinate fallback**

The third segment moves every segment's geometry: with THREE segments, "List" is now the middle third (its centre is dx 0.5), and the old two-segment fallback of dx 0.75 lands inside the CALENDAR segment — a latent booby trap that would silently flip a board to calendar mode if the radio-button and button queries ever both miss. In `switchToList()`:

```swift
        } else {
            // Last resort: List is the MIDDLE third of the (since M-D) three-segment control.
            picker.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
        }
```

- [ ] **Step 5: Run the gates**

```bash
pkill -f xcodebuild; pkill -f Tack.app; make unit 2>&1 | tee .build/md-task1-unit.log
pkill -f xcodebuild; pkill -f Tack.app; make build 2>&1 | tee .build/md-task1-build.log
pkill -f xcodebuild; pkill -f Tack.app
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild -project Tack.xcodeproj -scheme Tack \
  -destination "platform=macOS,arch=$(uname -m)" -derivedDataPath .build/DerivedData \
  -only-testing:TackUITests/ListViewUITests -parallel-testing-enabled NO test 2>&1 | tee .build/md-task1-ui.log
```
Expected: `** TEST SUCCEEDED **` twice and a green ListViewUITests. The build gate proves the defaulted `canNavigateSelection` compiles against all three `BoardActions` construction sites unchanged (`BoardView`, `ListBoardView`); the ListViewUITests run proves the THIRD SEGMENT did not break the M-C segment-click path (the suite's radio-button query is label-based and segment-count-agnostic, but this is exactly the kind of geometry change that deserves a regression run, and it also re-validates the fixed fallback file compiles).

- [ ] **Step 6: Commit**

```bash
git add Tack/Commands/FocusedValues.swift Tack/Commands/AppCommands.swift Tack/Views/RootView.swift TackUITests/ListViewUITests.swift
git commit -m "View-mode seam grows a Calendar arm: segment, opt-cmd-C, arrow gating (M-D)

Third toolbar segment + View > as Calendar (opt-cmd-C, verified free —
Tack has no Format menu to claim Copy Style). detailContent becomes an
exhaustive three-way switch; calendar temporarily renders BoardView
until Task 2 lands the view (marker honestly reports the mode).
BoardActions.canNavigateSelection honestly disables the four bare-arrow
items on surfaces with no arrow-key selection model. ListViewUITests'
two-segment coordinate fallback fixed for three-segment geometry.

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 2: `CalendarBoardView` + `CalendarViewUITests` (UI TDD)

**Files:**
- Modify: `Tack/Support/AccessibilityID.swift` (M-D section)
- Create: `TackUITests/CalendarViewUITests.swift`
- Create: `Tack/Views/Board/CalendarBoardView.swift`
- Modify: `Tack/Views/RootView.swift` (the one-line `.calendar` arm swap)
- `make gen` after each file-set change (Steps 1 and 3).

**Interfaces:**
- Consumes: `CalendarMonthGrid`/`CalendarReschedule`/guarded `setDueDate` (Task 0), the seam + `canNavigateSelection` (Task 1), `CardTransfer` (unchanged), `CardDetailView`, `ThemeResolution`, `Color.cardSurface`/`.insetSurface`/`.surfaceHairline`, `HoverHighlightButtonStyle`, `store.deleteCard`.
- Produces: `CalendarBoardView(board:store:)`; AX ids `calendar-month-title`, `calendar-prev`/`calendar-today`/`calendar-next`, `calendar-day-<yyyy-MM-dd>`, `calchip-<title>`, `calendar-nodate-header`, `calrow-<title>`.

- [ ] **Step 1: Write the failing UI tests**

`Tack/Support/AccessibilityID.swift` — add a new section after the M-C block:

```swift
    // MARK: - M-D: calendar view

    /// The month header ("July 2026" visible). Machine value is POSIX "yyyy-MM" via an
    /// `.accessibilityRepresentation` Text carrying this id (the `boardThemeValue`/`DueDateBadge`
    /// pattern) — tests assert the displayed month without locale-dependent month names.
    static let calendarMonthTitle = "calendar-month-title"
    static let calendarPrevButton = "calendar-prev"
    static let calendarTodayButton = "calendar-today"
    static let calendarNextButton = "calendar-next"
    /// A day cell OF THE DISPLAYED MONTH: "calendar-day-<yyyy-MM-dd>" (POSIX, LOCAL time zone —
    /// the DueDateBadge.isoDateFormatter rationale). An `.accessibilityElement(children:
    /// .contain)` container (the proven `card(_:)` shape), so chip ids inside stay queryable via
    /// `cell.descendants`. Dimmed adjacent-month cells get NO id: they are non-interactive, and a
    /// date-keyed id on them would let a boundary-week test grab the wrong month's cell.
    static func calendarDay(_ isoDay: String) -> String { "calendar-day-\(isoDay)" }
    /// A day cell's compact card chip. Prefixed "calchip-", never "card-"
    /// (`cardIdentifiersByPosition` counts `BEGINSWITH "card-"`). The id lives on the chip's
    /// representation Text, whose value is "<HH:mm>|<title>" for timed cards (POSIX HH:mm — the
    /// DueDateBadge wire-time grammar) and "<title>" otherwise.
    static func calendarChip(_ title: String) -> String { "calchip-\(title)" }
    /// The No-Date rail's header HStack — a SIBLING of the rail rows, never a container around
    /// them (the `listSection` discipline).
    static let calendarNoDateHeader = "calendar-nodate-header"
    /// A No-Date rail row (`.contain` container, the `listRow(_:)` shape): "calrow-<title>".
    static func calendarNoDateRow(_ title: String) -> String { "calrow-\(title)" }
```

Create `TackUITests/CalendarViewUITests.swift`:

```swift
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
```

- [ ] **Step 2: Run to verify failure**

```bash
pkill -f xcodebuild; pkill -f Tack.app
make gen
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild -project Tack.xcodeproj -scheme Tack \
  -destination "platform=macOS,arch=$(uname -m)" -derivedDataPath .build/DerivedData \
  -only-testing:TackUITests/CalendarViewUITests -parallel-testing-enabled NO test 2>&1 | tee .build/md-task2-red.log
```
NOTE on the red state's shape: the `AccessibilityID` additions land in THIS step, so the UI target COMPILES — the red is runtime failures. `switchToCalendar` itself succeeds (the segment and marker are live from Task 1, and the marker honestly reads "calendar"), and each test then fails on a missing `calendar-*` element because `CalendarBoardView` doesn't exist yet. Expected: 5 runtime element-existence failures past the mode switch (or 4 failures + 1 skip if today is within 5 days of month-end, and the drag test skips instead on the 1st/last of the month). That runtime red — against a live seam with the view genuinely absent — is what proves these tests bite.

- [ ] **Step 3: Implement the view + the branch swap**

Create `Tack/Views/Board/CalendarBoardView.swift`:

```swift
import SwiftUI

/// M-D: the Calendar View — the selected board's dated cards on a month grid (7-column
/// LazyVGrid, weeks as rows), undated cards in a trailing "No Date" rail, a SIBLING of
/// `BoardView`/`ListBoardView` behind `RootView.detailContent`'s per-board mode switch.
/// Chips select (click), open the shared `CardDetailView` sheet (double-click / context menu /
/// ⌘O), delete (context menu / ⌘⌫), and DRAG onto day cells to reschedule
/// (`CalendarReschedule.retargetedDueDate` → the guarded `store.setDueDate` — a same-day drop
/// is a store-level no-op). Creation, ⌘-arrow moves, the label filter, AND bare-arrow selection
/// navigation are HONESTLY disabled through the published `BoardActions` (see `boardActions`
/// below — `canNavigateSelection: false` is new in M-D: a month grid has no card-list arrow
/// walk, and v1 ships none rather than a fake one).
///
/// CLOCK: anchors on real `Date()` by design (no injected clock — an injected 'now' would
/// desynchronize the grid from the fixture's launch-relative real-now due dates; see the M-D
/// plan's Architecture note). The month anchor is ALWAYS a month start
/// (`CalendarMonthGrid.monthStart`), so prev/next `byAdding: .month` can never clamp-drift.
///
/// OVERFLOW (v1): a cell shows at most 3 chips + a non-clickable "+N" — the full day list is
/// reachable by switching to List mode. Adjacent-month filler days render dimmed and
/// NON-interactive: no id, no chips, no drop destination — a card due outside the displayed
/// month appears only when its month is displayed.
struct CalendarBoardView: View {
    let board: Board
    let store: BoardStore

    /// Calendar-mode single-card selection. Same @State-leak caveat as ListBoardView's:
    /// `detailContent` swaps only the `board:` argument across a board switch (the view is NOT
    /// recreated), so this — and the month anchor — reset via `.onChange(of: board.id)` below.
    @State private var selectedCardID: UUID?
    /// The card currently showing its detail sheet (same `.sheet(item:)` shape as its siblings).
    @State private var selectedDetailCard: Card?
    /// First instant of the displayed month (see the clock note above).
    @State private var monthAnchor = CalendarMonthGrid.monthStart(containing: Date(), calendar: .current)
    /// The day currently highlighted as a drop target (nil when no drag hovers a cell).
    @State private var targetedDay: Date?

    private var calendar: Calendar { .current }
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)

    var body: some View {
        HStack(spacing: 0) {
            calendarColumn
            if !undatedCards.isEmpty {
                Divider()
                noDateRail
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // HIG: the window title reflects the shown content — same as BoardView/ListBoardView.
        .navigationTitle(board.name)
        // M8 theme wash, verbatim from BoardView: cells/chips keep their own surfaces on top.
        .background(themeBackground)
        .sheet(item: $selectedDetailCard) { card in
            CardDetailView(card: card, store: store, onDelete: {
                // Order matters — see CardDetailView.onDelete: close the sheet (nil the item)
                // BEFORE deleting, so no re-render evaluates the sheet against a deleted card.
                selectedDetailCard = nil
                store.deleteCard(card)
            })
        }
        // Exported command surface — the same keys the siblings publish, including the M7 rule:
        // boardActions goes NIL while the detail sheet is up (menu key equivalents match before
        // the sheet's responder chain; an enabled ⌘⌫ would delete the card behind its own sheet).
        .focusedSceneValue(\.focusedBoard, board)
        .focusedSceneValue(\.selectedCard, selectedCard)
        .focusedSceneValue(\.focusedList, selectedCard?.list)
        .focusedSceneValue(\.boardActions, selectedDetailCard == nil ? boardActions : nil)
        .onChange(of: board.id) { _, _ in
            // A board switch is a context switch: drop the old board's selection and snap the
            // grid back to the current month.
            selectedCardID = nil
            monthAnchor = CalendarMonthGrid.monthStart(containing: Date(), calendar: calendar)
        }
    }

    // MARK: - Month header + grid

    private var calendarColumn: some View {
        VStack(alignment: .leading, spacing: 8) {
            monthHeader
            weekdayHeaderRow
            ScrollView {
                LazyVGrid(columns: columns, spacing: 4) {
                    ForEach(days) { day in
                        dayCell(day)
                    }
                }
            }
        }
        .padding(16)
    }

    private var monthHeader: some View {
        HStack(spacing: 8) {
            Text(monthAnchor.formatted(.dateTime.month(.wide).year()))
                .font(.title3.weight(.semibold))
                // Visible "July 2026", machine value POSIX "yyyy-MM" — the DueDateBadge
                // visible/wire split, so tests never parse localized month names.
                .accessibilityRepresentation {
                    Text(Self.wireMonthFormatter.string(from: monthAnchor))
                        .accessibilityIdentifier(AccessibilityID.calendarMonthTitle)
                }
            Spacer()
            Button {
                shiftMonth(-1)
            } label: {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(HoverHighlightButtonStyle())
            .help("Previous month")
            .accessibilityLabel("Previous Month")
            .accessibilityIdentifier(AccessibilityID.calendarPrevButton)

            Button("Today") {
                monthAnchor = CalendarMonthGrid.monthStart(containing: Date(), calendar: calendar)
            }
            .buttonStyle(HoverHighlightButtonStyle())
            .help("Go to the current month")
            .accessibilityIdentifier(AccessibilityID.calendarTodayButton)

            Button {
                shiftMonth(1)
            } label: {
                Image(systemName: "chevron.right")
            }
            .buttonStyle(HoverHighlightButtonStyle())
            .help("Next month")
            .accessibilityLabel("Next Month")
            .accessibilityIdentifier(AccessibilityID.calendarNextButton)
        }
    }

    private func shiftMonth(_ delta: Int) {
        if let shifted = calendar.date(byAdding: .month, value: delta, to: monthAnchor) {
            monthAnchor = CalendarMonthGrid.monthStart(containing: shifted, calendar: calendar)
        }
    }

    private var days: [CalendarMonthGrid.Day] {
        CalendarMonthGrid.days(anchoredAt: monthAnchor, calendar: calendar)
    }

    private var weekdayHeaderRow: some View {
        LazyVGrid(columns: columns, spacing: 4) {
            // enumerated + offset id: very-short weekday symbols REPEAT ("S", "S", "T", "T"), so
            // `id: \.self` would collapse duplicate columns.
            ForEach(Array(CalendarMonthGrid.weekdayHeaders(calendar: calendar).enumerated()),
                    id: \.offset) { _, symbol in
                Text(symbol)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: - Day cells

    /// One in-month cell = ONE `.dropDestination(for: CardTransfer.self)` — the CLAUDE.md
    /// shadowing invariant: destinations swallow every drag landing on them and stacked
    /// different-typed destinations shadow each other, so cells accept exactly one payload type
    /// and dimmed filler cells get no destination at all.
    @ViewBuilder
    private func dayCell(_ day: CalendarMonthGrid.Day) -> some View {
        if day.isInDisplayedMonth {
            let dayCards = cardsByDay[day.date] ?? []
            let isToday = calendar.isDateInToday(day.date)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(calendar.component(.day, from: day.date))")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(isToday ? Color.accentColor : Color.secondary)
                ForEach(dayCards.prefix(3)) { card in
                    chipView(card)
                }
                if dayCards.count > 3 {
                    // v1: NOT clickable — the full day list is reachable via List mode.
                    Text("+\(dayCards.count - 3)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(4)
            .frame(maxWidth: .infinity, minHeight: 92, alignment: .topLeading)
            // The CardView surface treatment: raised cell + hairline; today gets the accent ring.
            .background {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.cardSurface)
                    .shadow(color: .black.opacity(0.06), radius: 1, y: 0.5)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(isToday ? Color.accentColor : Color.surfaceHairline,
                                  lineWidth: isToday ? 2 : 1)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .fill(targetedDay == day.date ? Color.accentColor.opacity(0.10) : .clear)
                    .allowsHitTesting(false)
            }
            // `.contain` + id is the proven card(_:) container shape — chip ids inside stay
            // queryable (CalendarViewUITests' membership queries depend on it).
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(AccessibilityID.calendarDay(Self.isoDayFormatter.string(from: day.date)))
            .dropDestination(for: CardTransfer.self) { items, _ in
                drop(items, onto: day.date)
            } isTargeted: { targeting in
                if targeting {
                    targetedDay = day.date
                } else if targetedDay == day.date {
                    targetedDay = nil
                }
            }
        } else {
            // Adjacent-month filler: dimmed day number only — NO id, NO chips, NO drop
            // destination (see the type doc + AccessibilityID.calendarDay).
            Text("\(calendar.component(.day, from: day.date))")
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.quaternary)
                .padding(4)
                .frame(maxWidth: .infinity, minHeight: 92, alignment: .topLeading)
                .background {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.insetSurface)
                }
        }
    }

    private func drop(_ items: [CardTransfer], onto day: Date) -> Bool {
        guard let transfer = items.first,
              let card = allCards.first(where: { $0.id == transfer.cardID }) else { return false }
        // Timed cards keep their wall-clock time on the new day; the guarded setDueDate makes a
        // same-day drop a store-level no-op (no junk undo step).
        store.setDueDate(
            CalendarReschedule.retargetedDueDate(original: card.dueDate,
                                                 includesTime: card.includesTime,
                                                 onto: day, calendar: calendar),
            on: card, includesTime: card.includesTime, durationMinutes: card.durationMinutes)
        return true
    }

    // MARK: - Chips

    private func chipView(_ card: Card) -> some View {
        HStack(spacing: 4) {
            if card.includesTime, let dueDate = card.dueDate {
                // Visible time is locale-appropriate ("2:00 PM"/"14:00"); the WIRE time in the
                // representation below is POSIX HH:mm — the DueDateBadge visible/wire split.
                Text(Self.chipTimeFormatter.string(from: dueDate))
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Text(card.title)
                .font(.caption2)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 4)
                .fill(selectedCardID == card.id ? Color.accentColor.opacity(0.10) : Color.insetSurface)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 4)
                .strokeBorder(selectedCardID == card.id ? Color.accentColor.opacity(0.8) : Color.surfaceHairline,
                              lineWidth: selectedCardID == card.id ? 1.5 : 1)
        }
        .contentShape(Rectangle())
        // The CardView/CardListRow click grammar: first click selects immediately, double-click
        // opens (`.simultaneously`, not `.exclusively` — no selection lag).
        .gesture(
            TapGesture(count: 2).onEnded { selectedDetailCard = card }
                .simultaneously(with: TapGesture(count: 1).onEnded { selectedCardID = card.id })
        )
        // Representation Text (NOT .accessibilityValue — empty under XCUITest on macOS, the M6
        // finding): value "<HH:mm>|<title>" for timed cards, "<title>" otherwise. AX-only — the
        // real view underneath keeps its gestures and drag source (XCUITest drives both by
        // frame coordinates). If a live run ever shows the representation eating clicks/drags,
        // fall back to `.accessibilityElement(children: .combine)` + a POSIX-visible time — but
        // try the badge-proven representation first.
        .accessibilityRepresentation {
            Text(chipWireValue(card))
                .accessibilityIdentifier(AccessibilityID.calendarChip(card.title))
        }
        .draggable(CardTransfer(cardID: card.id))
        // The CardListRow v1 menu: Open + Delete only (moving between LISTS lives on the canvas;
        // moving between DAYS is the drag).
        .contextMenu {
            Button("Open Card") { selectedDetailCard = card }
            Button("Delete Card", role: .destructive) { deleteCard(card) }
        }
    }

    private func chipWireValue(_ card: Card) -> String {
        guard card.includesTime, let dueDate = card.dueDate else { return card.title }
        return "\(Self.wireTimeFormatter.string(from: dueDate))|\(card.title)"
    }

    // MARK: - No Date rail

    /// The undated cards, always visible beside the grid (per the M-D scope decision: a calendar
    /// that silently hides undated cards would lie about the board). Omitted entirely only when
    /// EMPTY — the M-C empty-buckets-omitted posture.
    private var noDateRail: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("No Date")
                    .font(.headline)
                Text("\(undatedCards.count)")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            // Header is a SIBLING of the rows (the listSection discipline).
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier(AccessibilityID.calendarNoDateHeader)

            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(undatedCards) { card in
                        CalendarNoDateRow(
                            card: card,
                            isSelected: selectedCardID == card.id,
                            onSelect: { selectedCardID = card.id },
                            onOpen: { selectedDetailCard = card },
                            onDelete: { deleteCard(card) }
                        )
                    }
                }
            }
        }
        .padding(12)
        .frame(width: 220)
    }

    // MARK: - M8: theme (verbatim from BoardView)

    private var themeBackground: Color {
        switch ThemeResolution.resolve(themeName: board.themeName, customHex: board.customThemeHex) {
        case .preset(let theme): theme.backgroundColor
        // Custom hex is a WASH like every preset — see BoardView.themeBackground.
        case .custom(let color): color.opacity(0.15)
        }
    }

    // MARK: - Card partitions

    /// Flatten order (list-position-then-card-position), the M-C rule: collapse is board-canvas
    /// layout state, never a data filter, and there is no label filter here (`canFilter: false`).
    private var allCards: [Card] {
        board.sortedLists.flatMap { $0.sortedCards }
    }

    /// Dated cards keyed by their LOCAL start-of-day (chip order within a day = flatten order).
    private var cardsByDay: [Date: [Card]] {
        var map: [Date: [Card]] = [:]
        for card in allCards {
            guard let dueDate = card.dueDate else { continue }
            map[calendar.startOfDay(for: dueDate), default: []].append(card)
        }
        return map
    }

    private var undatedCards: [Card] {
        allCards.filter { $0.dueDate == nil }
    }

    // MARK: - Selection + command surface

    /// The live `Card` for the current selection (nil when none / stale — a stale id degrades to
    /// "no selection" everywhere).
    private var selectedCard: Card? {
        guard let selectedCardID else { return nil }
        return allCards.first { $0.id == selectedCardID }
    }

    /// Calendar-mode command surface. REAL: selection (`selectedCard`), ⌘O open, ⌘⌫ delete.
    /// HONESTLY DISABLED, all via published `false` flags rather than enabled-but-inert items:
    /// `canCreateCard`/`canCreateList` (no canvas to open an inline editor on), Card ▸ Move
    /// Left/Right/Up/Down (`canMoveSelectedCard` false everywhere + `canMoveCards: false` — day
    /// membership is the drag's job, not ⌘-arrows'), `canFilter: false` (no label filter here),
    /// and — new in M-D — `canNavigateSelection: false`: `moveSelection` is a NO-OP closure
    /// because calendar v1 has no arrow-key selection model (a month grid wants 2D day-cell
    /// navigation, not the card-list walk), and the four View-menu arrow items disable honestly
    /// instead of firing that no-op. ⌘N / File ▸ New Tack Window keeps the deliberate M-C
    /// fall-through exception (see ListBoardView.boardActions).
    private var boardActions: BoardActions {
        BoardActions(
            selectedCard: selectedCard,
            newCard: {},
            canCreateCard: false,
            newList: {},
            deleteSelectedCard: deleteSelectedCard,
            openSelectedCard: openSelectedCard,
            moveSelectedCard: { _ in },
            moveSelection: { _ in }, // v1 no-op by design — gated by canNavigateSelection below
            canMoveSelectedCard: { _ in false },
            toggleLabelFilterBar: {},
            canFilter: false,
            canMoveCards: false,
            canCreateList: false,
            canNavigateSelection: false
        )
    }

    private func deleteSelectedCard() {
        guard let card = selectedCard else { return }
        selectedCardID = nil
        store.deleteCard(card)
    }

    private func openSelectedCard() {
        guard let card = selectedCard else { return }
        selectedDetailCard = card
    }

    /// Chip/rail context-menu delete: nil the selection FIRST if it's the deleted card (the
    /// CardView discipline), then one undoable store call.
    private func deleteCard(_ card: Card) {
        if selectedCardID == card.id { selectedCardID = nil }
        store.deleteCard(card)
    }

    // MARK: - Formatters

    /// POSIX + LOCAL time zone for cell ids — byte-matching CalendarViewUITests' formatter and
    /// the DueDateBadge.isoDateFormatter rationale (dueDate is stored as LOCAL start-of-day).
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

    /// Locale-appropriate short time for the VISIBLE chip prefix (DueDateBadge.shortTimeFormatter).
    private static let chipTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()

    /// Machine-readable 24-hour "HH:mm" for the chip wire value — POSIX-pinned for the same
    /// reason as DueDateBadge.wireTimeFormatter (the 12/24-hour system preference rewrites even
    /// explicit dateFormats).
    private static let wireTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm"
        formatter.timeZone = .current
        return formatter
    }()
}

/// One No-Date rail row: title + label dots — CardListRow's surface/selection/click grammar
/// minus the list name and due badge (an undated card has no badge by definition), plus a drag
/// source: dragging a rail row onto a day cell gives the card that date (nil-original
/// `CalendarReschedule` path). Plain `Text` title — no text inputs in this milestone.
private struct CalendarNoDateRow: View {
    let card: Card
    let isSelected: Bool
    let onSelect: () -> Void
    let onOpen: () -> Void
    let onDelete: () -> Void

    @State private var isHovering = false

    /// Ordered by `LabelColor.allCases`, not insertion order — same as CardView/CardListRow.
    private var sortedLabelColors: [LabelColor] {
        let owned = Set(card.labels.compactMap { LabelColor(rawValue: $0.colorName) })
        return LabelColor.allCases.filter { owned.contains($0) }
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(card.title)
                .lineLimit(1)
                .truncationMode(.tail)
            if !sortedLabelColors.isEmpty {
                HStack(spacing: 4) {
                    ForEach(sortedLabelColors, id: \.self) { color in
                        Circle()
                            .fill(color.swatchColor)
                            .overlay(Circle().strokeBorder(Color.primary.opacity(0.2), lineWidth: 0.5))
                            .frame(width: 8, height: 8)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.cardSurface)
                .shadow(color: .black.opacity(0.06), radius: 1, y: 0.5)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(isSelected ? Color.accentColor.opacity(0.8) : Color.surfaceHairline,
                              lineWidth: isSelected ? 1.5 : 1)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Color.accentColor.opacity(0.10)
                      : isHovering ? Color.primary.opacity(0.045) : .clear)
                .allowsHitTesting(false)
        }
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
        .gesture(
            TapGesture(count: 2).onEnded { onOpen() }
                .simultaneously(with: TapGesture(count: 1).onEnded { onSelect() })
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AccessibilityID.calendarNoDateRow(card.title))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .draggable(CardTransfer(cardID: card.id))
        .contextMenu {
            Button("Open Card") { onOpen() }
            Button("Delete Card", role: .destructive) { onDelete() }
        }
    }
}
```

`Tack/Views/RootView.swift` — the Task 1 `.calendar` arm becomes the real view (delete the "Task 1: temporary" comment block):

```swift
            case .calendar:
                CalendarBoardView(board: selectedBoard, store: store)
```

Then generate + build:

```bash
pkill -f xcodebuild; pkill -f Tack.app
make gen
make build 2>&1 | tee .build/md-task2-build.log
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Run the green set**

```bash
pkill -f xcodebuild; pkill -f Tack.app
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild -project Tack.xcodeproj -scheme Tack \
  -destination "platform=macOS,arch=$(uname -m)" -derivedDataPath .build/DerivedData \
  -only-testing:TackUITests/CalendarViewUITests -parallel-testing-enabled NO test 2>&1 | tee .build/md-task2-green.log
```
Expected: `** TEST SUCCEEDED **` — 5 tests (up to 2 legitimately SKIPPED near month boundaries: the timed-chip test within 5 days of month-end, the drag test on the first/last day of the month; a skip is a pass for gate purposes, and the skipped path runs on the next ordinary day). If the drag test fails at the drop itself, check the xcresult recording FIRST (desktop-notification interference, the documented environmental mode) before touching the drop code — and remember the chip-drag path is `.draggable` + `.dropDestination` (the Transferable machinery CGEvent/XCUITest drags are PROVEN to commit on this codebase, unlike native List `.onMove` — the B-06 finding), so a never-initiating drag points at the chip's gesture stack, not the machinery.

- [ ] **Step 5: Commit**

```bash
git add Tack/Support/AccessibilityID.swift Tack/Views/Board/CalendarBoardView.swift Tack/Views/RootView.swift TackUITests/CalendarViewUITests.swift
git commit -m "CalendarBoardView: month grid with drag-to-reschedule behind the seam (M-D)

7-column month grid (CalendarMonthGrid cells, date-keyed ids), compact
card chips (timed = HH:mm wire prefix), non-clickable +N overflow,
today ring, prev/today/next month nav with a POSIX yyyy-MM title value,
and a No Date rail. Chips and rail rows drag onto day cells: one
CardTransfer dropDestination per in-month cell (shadowing invariant),
CalendarReschedule preserves wall-clock time, the guarded setDueDate
makes same-day drops a no-op. Creation, cmd-arrows, cmd-F, and bare
arrows honestly disabled (canNavigateSelection). 5 mouse-driven e2es,
month-boundary-proof via runtime-computed cell ids + XCTSkipIf.

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 3: Milestone gate

**Files:** none (verification only).

- [ ] **Step 1:** `pkill -f xcodebuild; pkill -f Tack.app; make unit 2>&1 | tee .build/md-gate-unit.log` → `** TEST SUCCEEDED **`.

- [ ] **Step 2:** Mouse-driven UI suites this milestone touched or depends on:

```bash
pkill -f xcodebuild; pkill -f Tack.app
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild -project Tack.xcodeproj -scheme Tack \
  -destination "platform=macOS,arch=$(uname -m)" -derivedDataPath .build/DerivedData \
  -only-testing:TackUITests/CalendarViewUITests -only-testing:TackUITests/ListViewUITests \
  -only-testing:TackUITests/CardDetailUITests -only-testing:TackUITests/BadgeUITests \
  -parallel-testing-enabled NO test 2>&1 | tee .build/md-gate-ui.log
```
Expected: green. ListViewUITests proves the third segment didn't disturb the M-C switcher path; CardDetailUITests proves the reused sheet is unbroken from its new third host; BadgeUITests proves the badge grammar the drag test's store-truth oracle leans on. Any failure must be triaged against the environmental playbook (control-run committed code; check the xcresult recording) — a failure that reproduces against known-green code is the environment, not this milestone; any NEW deterministic failure is a real regression, fix before proceeding. `KeyboardShortcutUITests` and `LabelFilterUITests` are NOT gates here (documented environmentally-red keyboard/menu class); run them opportunistically in the next fresh login session along with the deferred menu-path e2e (View ▸ as Calendar / ⌥⌘C) noted in `CalendarViewUITests`' doc comment.

- [ ] **Step 3: Human checklist (hand to Ty, accumulate with M-A/M-B/M-C's)**

Launch against a scratch store — and remember the windowless-launch pitfall: **File ▸ New Tack Window (⌘N) is the second step**, or every board-dependent menu item stays disabled:

```sh
open .build/DerivedData/Build/Products/Debug/Tack.app --args --uitest --fixture standard --store-name scratch --reset
```

1. Toolbar: the switcher now has three segments (Board / List / Calendar), all legible; click Calendar — Groceries becomes a month grid of the current month with the month-year title, weekday header row, and prev/Today/next buttons; the theme wash still covers the surface; dimmed leading/trailing days from adjacent months show a day number only (no cards) and refuse drops.
2. Cells + chips: today's cell wears the accent ring; Call plumber's chip sits in it; Write report's chip (at +5d, if this month) leads with its time; chips single-click select (ring), double-click opens the detail sheet (Esc closes), right-click offers exactly Open Card / Delete Card.
3. Drag feel: drag Buy milk's chip from yesterday's cell to a new day — the target cell highlights while hovered, the chip moves on drop, and the badge in List mode agrees; drag a chip onto its OWN cell, then press ⌘Z — the undo must reverse the PREVIOUS action, not a phantom "Set Due Date" (the guard); drag Book flights out of the No Date rail onto a day — it gains that date and leaves the rail (rail disappears when it empties).
4. Timed preservation: drag Write report's chip to another day — its badge/detail still reads 2:00 PM on the new day (wall-clock preserved, duration intact in the detail sheet).
5. Month nav: prev/next walk adjacent months (title updates; Groceries' dated cards vanish from months they're not in); Today snaps back. Overflow: add a fourth card due today via the detail sheet — today's cell shows 3 chips + "+1", and "+1" is NOT clickable (v1; the full list is in List mode).
6. Menu + shortcuts (the deliberately-not-e2e'd path — this IS its verification): View ▸ as Calendar exists under as List, ⌥⌘C flips the mode with NO duplicate-shortcut beep (the Copy Style check); in calendar mode View ▸ Filter by Label, File ▸ New Card / New List, Card ▸ Move Card items, and all four Select Next/Previous/Left/Right items are DISABLED (honest gating — the four arrow items are the new canNavigateSelection flag); ⌘O opens the selected chip's card, ⌘⌫ deletes it (⌘Z brings it back).
7. Per-board persistence: Groceries → calendar, Work stays board; quit; relaunch WITHOUT `--reset` — Groceries reopens as calendar, Work as board; the M-C List mode still round-trips too.
8. Appearance: relaunch with `--appearance dark` — cells read RAISED off the wash (not cut-in wells), dimmed filler days recede, the today ring and chip selection ring stay legible, the No Date rail rows match List-mode rows.

