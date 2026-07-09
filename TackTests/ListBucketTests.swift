import Testing
import Foundation
@testable import Tack

/// M-C: pure bucketing for the List View's five due-date sections. Built ON TOP of
/// `DueDateStatus.classify`, so these tests focus on the refinement layer (tomorrow/upcoming →
/// This Week vs Later, the 7/8-day boundary, and the timed-overdue passthrough) rather than
/// re-proving classify's own matrix (DueDateStatusTests owns that).
@Suite("ListBucket")
struct ListBucketTests {
    var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }

    func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    var now: Date { date(2026, 7, 5, 15, 30) }

    @Test("nil due date is No Date, even with stray time args")
    func nilDueDateIsNoDate() {
        #expect(ListBucket.bucket(dueDate: nil, now: now, calendar: calendar) == .noDate)
        #expect(ListBucket.bucket(dueDate: nil, includesTime: true, durationMinutes: 30,
                                  now: now, calendar: calendar) == .noDate)
    }

    @Test("yesterday is Overdue")
    func yesterdayIsOverdue() {
        #expect(ListBucket.bucket(dueDate: date(2026, 7, 4), now: now, calendar: calendar) == .overdue)
    }

    @Test("today is Today")
    func todayIsToday() {
        #expect(ListBucket.bucket(dueDate: date(2026, 7, 5), now: now, calendar: calendar) == .today)
    }

    @Test("tomorrow is This Week")
    func tomorrowIsThisWeek() {
        #expect(ListBucket.bucket(dueDate: date(2026, 7, 6), now: now, calendar: calendar) == .thisWeek)
    }

    @Test("seven days out (the DueDateQuickOption nextWeek anchor) is still This Week")
    func sevenDaysOutIsThisWeek() {
        #expect(ListBucket.bucket(dueDate: date(2026, 7, 12), now: now, calendar: calendar) == .thisWeek)
    }

    @Test("eight days out is Later")
    func eightDaysOutIsLater() {
        #expect(ListBucket.bucket(dueDate: date(2026, 7, 13), now: now, calendar: calendar) == .later)
    }

    @Test("365 days out is Later")
    func farFutureIsLater() {
        #expect(ListBucket.bucket(dueDate: date(2027, 7, 5), now: now, calendar: calendar) == .later)
    }

    @Test("timed-overdue passthrough: an ended slot TODAY is Overdue (the M-B classify rule)")
    func timedEndedSlotTodayIsOverdue() {
        // 14:00 + 60-min slot ended 15:00 < now (15:30): classify says .overdue; bucket must NOT
        // re-derive day math and demote it to Today.
        #expect(ListBucket.bucket(dueDate: date(2026, 7, 5, 14, 0), includesTime: true,
                                  durationMinutes: 60, now: now, calendar: calendar) == .overdue)
    }

    @Test("timed today with the slot still ahead is Today")
    func timedFutureSlotTodayIsToday() {
        #expect(ListBucket.bucket(dueDate: date(2026, 7, 5, 18, 0), includesTime: true,
                                  now: now, calendar: calendar) == .today)
    }

    @Test("timed timestamps keep the 7/8-day boundary on calendar days, not 24h windows")
    func timedBoundaryUsesDayDelta() {
        // +7d at 09:00 is only ~6.7×24h away but SEVEN calendar days: This Week.
        #expect(ListBucket.bucket(dueDate: date(2026, 7, 12, 9, 0), includesTime: true,
                                  now: now, calendar: calendar) == .thisWeek)
        // +8d at 09:00: Later.
        #expect(ListBucket.bucket(dueDate: date(2026, 7, 13, 9, 0), includesTime: true,
                                  now: now, calendar: calendar) == .later)
    }

    @Test("titles read as the five section headers")
    func titles() {
        #expect(ListBucket.overdue.title == "Overdue")
        #expect(ListBucket.today.title == "Today")
        #expect(ListBucket.thisWeek.title == "This Week")
        #expect(ListBucket.later.title == "Later")
        #expect(ListBucket.noDate.title == "No Date")
    }

    @Test("section slugs are the lowercased-hyphenated id fragments")
    func sectionSlugs() {
        #expect(ListBucket.allCases.map(\.sectionSlug) ==
                ["overdue", "today", "this-week", "later", "no-date"])
    }

    @Test("snapshotIDs are five distinct, stable literals")
    func snapshotIDsDistinctAndStable() {
        let ids = ListBucket.allCases.map(\.snapshotID)
        #expect(Set(ids).count == ListBucket.allCases.count)
        #expect(ListBucket.allCases.map(\.snapshotID) == ids,
                "ids must be fixed literals, not UUID() — SelectionNavigation and tests rely on stability")
    }
}

/// M-C: the per-board view-mode persistence codec (one UserDefaults string — see
/// `RootView`'s viewModes triad).
@Suite("BoardViewMode codec")
struct BoardViewModeCodecTests {
    @Test("nil and empty raw decode to an empty map; an empty map encodes to the empty string")
    func emptyBothWays() {
        #expect(BoardViewMode.decode(nil).isEmpty)
        #expect(BoardViewMode.decode("").isEmpty)
        #expect(BoardViewMode.encode([:]) == "")
    }

    @Test("encode → decode round-trips a mixed map")
    func roundTrip() {
        let a = UUID(), b = UUID(), c = UUID()
        let map: [UUID: BoardViewMode] = [a: .list, b: .board, c: .list]
        #expect(BoardViewMode.decode(BoardViewMode.encode(map)) == map)
    }

    @Test("encode is deterministic: sorted by uuidString, 'uuid=mode' comma-joined")
    func encodeDeterministic() {
        let a = UUID(uuidString: "AAAAAAAA-0000-4000-8000-000000000000")!
        let b = UUID(uuidString: "BBBBBBBB-0000-4000-8000-000000000000")!
        #expect(BoardViewMode.encode([b: .list, a: .board]) ==
                "\(a.uuidString)=board,\(b.uuidString)=list")
    }

    @Test("malformed entries are dropped, valid ones kept (tolerant decode, never a crash)")
    func malformedDropped() {
        let a = UUID(uuidString: "AAAAAAAA-0000-4000-8000-000000000000")!
        let raw = "not-a-uuid=list,\(a.uuidString)=list,\(UUID().uuidString)=grid,,justgarbage"
        #expect(BoardViewMode.decode(raw) == [a: .list])
    }
}
