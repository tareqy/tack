import Testing
import Foundation
@testable import Tack

@Suite("DueDateQuickOption")
struct DueDateQuickOptionTests {
    var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }

    func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    var now: Date { date(2026, 7, 5, 15, 30) }

    @Test(".today returns the start of the current day")
    func todayIsStartOfDay() {
        let result = DueDateQuickOption.date(for: .today, now: now, calendar: calendar)
        #expect(result == date(2026, 7, 5))
    }

    @Test(".tomorrow returns the start of the next day")
    func tomorrowIsStartOfNextDay() {
        let result = DueDateQuickOption.date(for: .tomorrow, now: now, calendar: calendar)
        #expect(result == date(2026, 7, 6))
    }

    @Test(".nextWeek returns the start of the day 7 days out")
    func nextWeekIsSevenDaysOut() {
        let result = DueDateQuickOption.date(for: .nextWeek, now: now, calendar: calendar)
        #expect(result == date(2026, 7, 12))
    }

    @Test("nextWeek crosses a month boundary correctly")
    func nextWeekCrossesMonthBoundary() {
        let lateJanuary = date(2026, 1, 28, 9, 0)
        let result = DueDateQuickOption.date(for: .nextWeek, now: lateJanuary, calendar: calendar)
        #expect(result == date(2026, 2, 4))
    }

    @Test("today drops any time-of-day component from `now`")
    func todayDropsTimeComponent() {
        let lateInDay = date(2026, 7, 5, 23, 59)
        let result = DueDateQuickOption.date(for: .today, now: lateInDay, calendar: calendar)
        #expect(result == date(2026, 7, 5, 0, 0))
    }

    @Test("tomorrow drops any time-of-day component from `now`")
    func tomorrowDropsTimeComponent() {
        let lateInDay = date(2026, 7, 5, 23, 59)
        let result = DueDateQuickOption.date(for: .tomorrow, now: lateInDay, calendar: calendar)
        #expect(result == date(2026, 7, 6, 0, 0))
    }
}
