import Testing
import Foundation
import SwiftData
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

    @Test("a duplicate key keeps the LAST entry's value, not the first")
    func decodeDuplicateKeyLastWins() {
        let a = UUID(uuidString: "AAAAAAAA-0000-4000-8000-000000000000")!
        #expect(BoardViewMode.decode("\(a.uuidString)=board,\(a.uuidString)=list") == [a: .list])
    }

    @Test("encode(decode(canonical)) round-trips the canonical literal byte-for-byte")
    func encodeDecodeCanonicalRoundTrip() {
        let a = UUID(uuidString: "AAAAAAAA-0000-4000-8000-000000000000")!
        let b = UUID(uuidString: "BBBBBBBB-0000-4000-8000-000000000000")!
        let canonical = "\(a.uuidString)=board,\(b.uuidString)=list"
        #expect(BoardViewMode.encode(BoardViewMode.decode(canonical)) == canonical)
    }
}

/// M-C: the live-board → bucket-sections bridge. Uses TestContainer (in-memory) because the
/// input is a real SwiftData Board; the bucketing math itself is pinned pure in ListBucketTests
/// above. NOTE: these run against the REAL clock via relative fixture dates — same accepted
/// midnight-adjacent caveat as FixtureSeederTests.
@MainActor
@Suite("ListBucketSnapshot")
struct ListBucketSnapshotTests {
    private func fetchBoards(_ context: ModelContext) -> [Board] {
        (try? context.fetch(FetchDescriptor<Board>(sortBy: [SortDescriptor(\.position)]))) ?? []
    }

    @Test("flattens ALL lists in position order and IGNORES isCollapsed")
    func flattenIgnoresCollapse() {
        let env = TestContainer()
        let board = env.store.createBoard(name: "B", emoji: nil)
        let lists = board.sortedLists // ["To Do", "In Progress", "Done"]
        let first = env.store.addCard(to: lists[0], title: "First")
        let second = env.store.addCard(to: lists[1], title: "Second")
        env.store.setCollapsed(lists[1], true) // collapse must NOT hide Second from the flat list

        let snapshot = ListBucketSnapshot.build(board: board, now: .now, calendar: .current)

        #expect(snapshot.lists.count == 1, "both cards undated → exactly one No Date bucket")
        #expect(snapshot.lists[0].id == ListBucket.noDate.snapshotID)
        #expect(snapshot.lists[0].cardIDs == [first.id, second.id],
                "flatten keeps list-position-then-card-position order, collapsed or not")
    }

    @Test("buckets appear in allCases order with empty buckets omitted")
    func bucketOrderAndOmission() {
        let env = TestContainer()
        let board = env.store.createBoard(name: "B", emoji: nil)
        let toDo = board.sortedLists[0]
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)

        // Inserted in scrambled order on purpose: bucket order must come from allCases, not
        // from card positions.
        let laterCard = env.store.addCard(to: toDo, title: "Later card")
        env.store.setDueDate(calendar.date(byAdding: .day, value: 30, to: today)!, on: laterCard)
        let todayCard = env.store.addCard(to: toDo, title: "Today card")
        env.store.setDueDate(today, on: todayCard)
        let noDateCard = env.store.addCard(to: toDo, title: "No date card")

        let snapshot = ListBucketSnapshot.build(board: board, now: .now, calendar: calendar)

        #expect(snapshot.lists.map(\.id) ==
                [ListBucket.today.snapshotID, ListBucket.later.snapshotID, ListBucket.noDate.snapshotID],
                "allCases order, with the empty Overdue and This Week buckets omitted")
        #expect(snapshot.lists[0].cardIDs == [todayCard.id])
        #expect(snapshot.lists[1].cardIDs == [laterCard.id])
        #expect(snapshot.lists[2].cardIDs == [noDateCard.id])
    }

    @Test("the standard fixture buckets exactly as ListViewUITests asserts")
    func standardFixtureBuckets() {
        let env = TestContainer()
        FixtureSeeder.seed("standard", context: env.context)
        let board = fetchBoards(env.context)[0] // Groceries

        let sections = ListBucketSnapshot.sections(board: board, now: .now, calendar: .current)

        #expect(sections.map(\.bucket) == [.overdue, .today, .thisWeek, .noDate],
                "Later is empty for the fixture and must be omitted")
        #expect(sections.map { $0.cards.map(\.title) } ==
                [["Buy milk"], ["Call plumber"], ["Return library books", "Write report"], ["Book flights"]],
                "the timed Write report (+5d 14:00) lands in This Week, after Return library books (flatten order)")
    }

    @Test("SelectionNavigation crosses bucket boundaries over the built snapshot")
    func selectionNavigationOverBuckets() {
        let env = TestContainer()
        FixtureSeeder.seed("standard", context: env.context)
        let board = fetchBoards(env.context)[0]
        let snapshot = ListBucketSnapshot.build(board: board, now: .now, calendar: .current)

        let buyMilkID = snapshot.lists[0].cardIDs[0]
        // nil selection enters at the first card of the first bucket (keyboard entry point).
        #expect(SelectionNavigation.next(selectedCardID: nil, direction: .down, board: snapshot) == buyMilkID)
        // Down from the last Overdue card lands on the first Today card — bucket crossing works
        // because buckets ARE ListSnapshots; SelectionNavigation needed zero changes.
        #expect(SelectionNavigation.next(selectedCardID: buyMilkID, direction: .down, board: snapshot)
                == snapshot.lists[1].cardIDs[0])
    }
}
