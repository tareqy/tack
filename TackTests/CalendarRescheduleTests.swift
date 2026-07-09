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
        #expect(days.allSatisfy { $0.isInDisplayedMonth })
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
