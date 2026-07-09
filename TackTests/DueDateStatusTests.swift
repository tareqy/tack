import Testing
import Foundation
@testable import Tack

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

    // MARK: - M-B: timed classification (includesTime / durationMinutes)

    @Test("timed today with the time still ahead is today")
    func timedTodayFutureTimeIsToday() {
        let due = date(2026, 7, 5, 18, 0)
        #expect(DueDateStatus.classify(dueDate: due, includesTime: true, now: now, calendar: calendar) == .today)
    }

    @Test("timed today with the time just passed is overdue")
    func timedTodayTimePassedIsOverdue() {
        let due = date(2026, 7, 5, 15, 29) // one minute before now — no duration → slot already ended
        #expect(DueDateStatus.classify(dueDate: due, includesTime: true, now: now, calendar: calendar) == .overdue)
    }

    @Test("timed slot still running (start passed, start+duration ahead) is today")
    func timedSlotStillRunningIsToday() {
        let due = date(2026, 7, 5, 15, 0) // 60-min slot runs until 16:00 > now (15:30)
        #expect(DueDateStatus.classify(dueDate: due, includesTime: true, durationMinutes: 60,
                                       now: now, calendar: calendar) == .today)
    }

    @Test("timed slot fully ended (start+duration passed) is overdue")
    func timedSlotEndedIsOverdue() {
        let due = date(2026, 7, 5, 14, 0) // 60-min slot ended 15:00 < now (15:30)
        #expect(DueDateStatus.classify(dueDate: due, includesTime: true, durationMinutes: 60,
                                       now: now, calendar: calendar) == .overdue)
    }

    @Test("timed tomorrow is tomorrow")
    func timedTomorrowIsTomorrow() {
        let due = date(2026, 7, 6, 9, 0)
        #expect(DueDateStatus.classify(dueDate: due, includesTime: true, now: now, calendar: calendar) == .tomorrow)
    }

    @Test("timed several days out is upcoming")
    func timedUpcomingIsUpcoming() {
        let due = date(2026, 7, 10, 9, 0)
        #expect(DueDateStatus.classify(dueDate: due, includesTime: true, durationMinutes: 120,
                                       now: now, calendar: calendar) == .upcoming)
    }

    @Test("zero and negative durations are ignored (treated as nil)")
    func nonPositiveDurationIgnored() {
        // Zero: the slot ends at its start (15:00), already past now (15:30) → overdue, same as nil.
        let passed = date(2026, 7, 5, 15, 0)
        #expect(DueDateStatus.classify(dueDate: passed, includesTime: true, durationMinutes: 0,
                                       now: now, calendar: calendar) == .overdue)
        // Negative must NOT pull the slot end earlier: an 18:00 slot with -600 is still ahead.
        let future = date(2026, 7, 5, 18, 0)
        #expect(DueDateStatus.classify(dueDate: future, includesTime: true, durationMinutes: -600,
                                       now: now, calendar: calendar) == .today)
    }

    @Test("nil dueDate with includesTime true is still none")
    func nilDueDateWithTimeIsNone() {
        #expect(DueDateStatus.classify(dueDate: nil, includesTime: true, durationMinutes: 30,
                                       now: now, calendar: calendar) == .none)
    }
}
