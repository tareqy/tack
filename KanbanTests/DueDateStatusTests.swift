import Testing
import Foundation
@testable import Kanban

@Suite("DueDateStatus")
struct DueDateStatusTests {
    var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }

    func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    var now: Date { date(2026, 7, 5, 15, 30) }

    @Test("nil due date has no status")
    func nilDueDate() {
        #expect(DueDateStatus.classify(dueDate: nil, now: now, calendar: calendar) == .none)
    }

    @Test("yesterday 23:59 is overdue")
    func yesterdayLateIsOverdue() {
        let due = date(2026, 7, 4, 23, 59)
        #expect(DueDateStatus.classify(dueDate: due, now: now, calendar: calendar) == .overdue)
    }

    @Test("30 days ago is overdue")
    func thirtyDaysAgoIsOverdue() {
        let due = date(2026, 6, 5)
        #expect(DueDateStatus.classify(dueDate: due, now: now, calendar: calendar) == .overdue)
    }

    @Test("today at 00:00 is today")
    func todayMidnightIsToday() {
        let due = date(2026, 7, 5, 0, 0)
        #expect(DueDateStatus.classify(dueDate: due, now: now, calendar: calendar) == .today)
    }

    @Test("today at 23:59 is today")
    func todayLateIsToday() {
        let due = date(2026, 7, 5, 23, 59)
        #expect(DueDateStatus.classify(dueDate: due, now: now, calendar: calendar) == .today)
    }

    @Test("tomorrow at 00:00 is tomorrow")
    func tomorrowMidnightIsTomorrow() {
        let due = date(2026, 7, 6, 0, 0)
        #expect(DueDateStatus.classify(dueDate: due, now: now, calendar: calendar) == .tomorrow)
    }

    @Test("day after tomorrow is upcoming")
    func dayAfterTomorrowIsUpcoming() {
        let due = date(2026, 7, 7)
        #expect(DueDateStatus.classify(dueDate: due, now: now, calendar: calendar) == .upcoming)
    }

    @Test("365 days out is upcoming")
    func farFutureIsUpcoming() {
        let due = date(2027, 7, 5)
        #expect(DueDateStatus.classify(dueDate: due, now: now, calendar: calendar) == .upcoming)
    }

    @Test("year boundary: Dec 31 now, Jan 1 due is tomorrow")
    func yearBoundaryIsTomorrow() {
        let boundaryNow = date(2026, 12, 31, 9, 0)
        let due = date(2027, 1, 1, 0, 0)
        #expect(DueDateStatus.classify(dueDate: due, now: boundaryNow, calendar: calendar) == .tomorrow)
    }

    @Test("year boundary: Dec 31 now, Dec 31 due (same day) is today")
    func yearBoundarySameDayIsToday() {
        let boundaryNow = date(2026, 12, 31, 9, 0)
        let due = date(2026, 12, 31, 23, 0)
        #expect(DueDateStatus.classify(dueDate: due, now: boundaryNow, calendar: calendar) == .today)
    }
}
