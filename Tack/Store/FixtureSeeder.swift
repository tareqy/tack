import Foundation
import SwiftData

/// Seeds deterministic data for UI-test launches. Seeding is idempotent per store: it only runs
/// when the store is empty, so a relaunch WITHOUT `--reset` reopens the same store and preserves
/// whatever mutations the previous launch made (that is how the persistence assertions work).
enum FixtureSeeder {
    @MainActor
    static func seed(_ fixture: String, context: ModelContext) {
        let existingBoards = (try? context.fetch(FetchDescriptor<Board>())) ?? []
        guard existingBoards.isEmpty else { return }

        switch fixture {
        case "spike":
            seedSpike(context: context)
        case "empty":
            // Zero boards, but labels are still seeded (every later milestone assumes the 8-color
            // palette exists regardless of which board fixture is in play).
            BoardStore(context: context).ensureLabelsSeeded()
        case "large":
            seedLarge(context: context)
        default:
            // "standard" and any other value fall back to the same deterministic fixture used by
            // every later milestone's UI tests.
            seedStandard(context: context)
        }
    }

    /// Board "Groceries" (position 0) with realistic cards/labels/due-dates, plus an empty
    /// "Work" board (position 1). Built via `BoardStore` (not direct model construction) so
    /// position bookkeeping and due-date normalization go through the exact same invariants the
    /// rest of the app relies on.
    @MainActor
    private static func seedStandard(context: ModelContext) {
        let store = BoardStore(context: context)
        store.ensureLabelsSeeded()

        seedGroceries(store: store)
        let work = store.createBoard(name: "Work", emoji: "💼")
        // M-F: the fixture's ONE area — "Office", EXPANDED, wrapping the EXISTING Work board;
        // Groceries stays ungrouped. Grouping an existing board (rather than adding one) keeps
        // the load-bearing roster byte-identical: same two rows, same names, same global
        // positions (Groceries 0, Work 1), same flat ⌘1/⌘2 order — every pre-M-F suite sees its
        // rows exactly where they were, plus one sibling header element (`area-Office`) that no
        // `board-`-prefixed query can match. Do not rename the area or the boards; do not
        // collapse Office at seed (a hidden Work row would break half the suites).
        _ = store.createArea(named: "Office", moving: work)
    }

    @MainActor
    private static func seedGroceries(store: BoardStore) {
        let board = store.createBoard(name: "Groceries", emoji: "🛒", about: "Weekly shopping run")
        let lists = board.sortedLists
        guard lists.count == 3 else { return } // ["To Do", "In Progress", "Done"]
        let toDo = lists[0]
        let inProgress = lists[1]
        let done = lists[2]

        let calendar = Calendar.current
        let now = Date()
        func daysFromNow(_ delta: Int) -> Date {
            calendar.date(byAdding: .day, value: delta, to: now) ?? now
        }

        let buyMilk = store.addCard(to: toDo, title: "Buy milk")
        store.setDueDate(daysFromNow(-1), on: buyMilk)
        store.toggleLabel(.green, on: buyMilk)
        store.toggleLabel(.blue, on: buyMilk)

        let callPlumber = store.addCard(to: toDo, title: "Call plumber")
        store.setDueDate(now, on: callPlumber)

        let returnBooks = store.addCard(to: toDo, title: "Return library books")
        store.setDueDate(daysFromNow(1), on: returnBooks)
        // M-E: the fixture's ONE checklist-bearing card — 3 items, 2 done, face fraction "2/3".
        // Deliberately Return library books: the least-detail-coupled dated card (no UI test ever
        // opens its detail sheet; its face-level uses are id/badge-value-based, which the fraction
        // chip on the EXISTING meta line can't disturb). Seeded through applyCardEdits so drafts →
        // rows exercise the exact production diff path. Do not move these items to another card —
        // Call plumber / Write report / Book flights all anchor CardDetailUITests flows.
        store.applyCardEdits(returnBooks, title: returnBooks.title, details: returnBooks.details,
                             labels: [], dueDate: returnBooks.dueDate, includesTime: false,
                             durationMinutes: nil,
                             checklist: [
                                 ChecklistDraft(id: nil, text: "Renew library card", isDone: true),
                                 ChecklistDraft(id: nil, text: "Gather books from car", isDone: true),
                                 ChecklistDraft(id: nil, text: "Pay late fee", isDone: false),
                             ])

        let writeReport = store.addCard(to: inProgress, title: "Write report")
        // M-B: the fixture's ONE timed card — a 2:00 PM slot, 60 minutes, five days out. Still
        // `|upcoming` for BadgeUITests' suffix assertion (+5d 14:00 is always in the future),
        // and the card roster/names are load-bearing across the UI suites — do not rename.
        let writeReportSlot = calendar.date(bySettingHour: 14, minute: 0, second: 0, of: daysFromNow(5))!
        store.setDueDate(writeReportSlot, on: writeReport, includesTime: true, durationMinutes: 60)
        store.toggleLabel(.red, on: writeReport)

        store.addCard(to: done, title: "Book flights") // no due date
    }

    /// NFR smoke fixture (N-04 responsiveness): one board "Large" with 3 lists and 500 cards
    /// ("Card 0001"…"Card 0500", round-robin across the lists so each holds ~167), inserted
    /// directly with one save for speed. Deterministic titles: "Card 0001" is the first card of
    /// the first list. Labels are still seeded for palette parity.
    @MainActor
    private static func seedLarge(context: ModelContext) {
        BoardStore(context: context).ensureLabelsSeeded()

        let board = Board(name: "Large", emoji: "🗃️", position: 0)
        context.insert(board)
        let lists = ["To Do", "In Progress", "Done"].enumerated().map { index, name in
            BoardList(name: name, position: index, board: board)
        }
        lists.forEach { context.insert($0) }

        var perListCount = [0, 0, 0]
        for n in 1...500 {
            let listIndex = (n - 1) % 3
            let title = String(format: "Card %04d", n)
            context.insert(Card(title: title, position: perListCount[listIndex], list: lists[listIndex]))
            perListCount[listIndex] += 1
        }
        try? context.save()
    }

    private static func seedSpike(context: ModelContext) {
        let board = Board(name: "Spike", position: 0)
        context.insert(board)

        let left = BoardList(name: "Left", position: 0, board: board)
        let right = BoardList(name: "Right", position: 1, board: board)
        context.insert(left)
        context.insert(right)

        for (index, title) in ["Spike A1", "Spike A2", "Spike A3"].enumerated() {
            context.insert(Card(title: title, position: index, list: left))
        }
        context.insert(Card(title: "Spike B1", position: 0, list: right))

        try? context.save()
    }
}
