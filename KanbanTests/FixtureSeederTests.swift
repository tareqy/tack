import Testing
import Foundation
import SwiftData
@testable import Kanban

@MainActor
@Suite("FixtureSeeder")
struct FixtureSeederTests {
    private func fetchBoards(_ context: ModelContext) -> [Board] {
        (try? context.fetch(FetchDescriptor<Board>(sortBy: [SortDescriptor(\.position)]))) ?? []
    }

    private func card(_ title: String, in list: BoardList) -> Card? {
        list.sortedCards.first { $0.title == title }
    }

    @Test("standard fixture seeds exactly Groceries + Work in order")
    func standardSeedsTwoBoards() {
        let env = TestContainer()
        FixtureSeeder.seed("standard", context: env.context)

        let boards = fetchBoards(env.context)
        #expect(boards.map(\.name) == ["Groceries", "Work"])
        #expect(boards.map(\.position) == [0, 1])
        #expect(boards[0].emoji == "🛒")
        #expect(boards[1].emoji == "💼")
    }

    @Test("Groceries lists have exact card names and order")
    func groceriesListsAndCards() {
        let env = TestContainer()
        FixtureSeeder.seed("standard", context: env.context)

        let groceries = fetchBoards(env.context)[0]
        let lists = groceries.sortedLists
        #expect(lists.map(\.name) == ["To Do", "In Progress", "Done"])

        let toDo = lists[0]
        #expect(toDo.sortedCards.map(\.title) == ["Buy milk", "Call plumber", "Return library books"])

        let inProgress = lists[1]
        #expect(inProgress.sortedCards.map(\.title) == ["Write report"])

        let done = lists[2]
        #expect(done.sortedCards.map(\.title) == ["Book flights"])
    }

    @Test("Work board is 3 empty default lists")
    func workBoardIsEmpty() {
        let env = TestContainer()
        FixtureSeeder.seed("standard", context: env.context)

        let work = fetchBoards(env.context)[1]
        let lists = work.sortedLists
        #expect(lists.map(\.name) == ["To Do", "In Progress", "Done"])
        #expect(lists.allSatisfy { $0.cards.isEmpty })
    }

    @Test("labels attach to the right cards")
    func labelsOnRightCards() {
        let env = TestContainer()
        FixtureSeeder.seed("standard", context: env.context)

        let groceries = fetchBoards(env.context)[0]
        let toDo = groceries.sortedLists[0]
        let inProgress = groceries.sortedLists[1]

        let buyMilk = card("Buy milk", in: toDo)
        #expect(Set(buyMilk?.labels.map(\.colorName) ?? []) == ["green", "blue"])

        let writeReport = card("Write report", in: inProgress)
        #expect(writeReport?.labels.map(\.colorName) == ["red"])

        let callPlumber = card("Call plumber", in: toDo)
        #expect(callPlumber?.labels.isEmpty == true)
    }

    @Test("all 8 labels exist after standard seed")
    func allLabelsSeeded() {
        let env = TestContainer()
        FixtureSeeder.seed("standard", context: env.context)

        let labels = (try? env.context.fetch(FetchDescriptor<CardLabel>())) ?? []
        #expect(labels.count == 8)
    }

    @Test("due dates are normalized start-of-day and relative to now")
    func dueDatesNormalizedAndRelative() {
        let env = TestContainer()
        FixtureSeeder.seed("standard", context: env.context)

        let groceries = fetchBoards(env.context)[0]
        let toDo = groceries.sortedLists[0]
        let inProgress = groceries.sortedLists[1]
        let done = groceries.sortedLists[2]

        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: Date())
        let tomorrowStart = calendar.date(byAdding: .day, value: 1, to: todayStart)!
        let yesterdayStart = calendar.date(byAdding: .day, value: -1, to: todayStart)!
        let plusFiveStart = calendar.date(byAdding: .day, value: 5, to: todayStart)!

        #expect(card("Buy milk", in: toDo)?.dueDate == yesterdayStart)
        #expect(card("Call plumber", in: toDo)?.dueDate == todayStart)
        #expect(card("Return library books", in: toDo)?.dueDate == tomorrowStart)
        #expect(card("Write report", in: inProgress)?.dueDate == plusFiveStart)
        #expect(card("Book flights", in: done)?.dueDate == nil)

        // Every non-nil due date must already be start-of-day normalized.
        let allCards = toDo.sortedCards + inProgress.sortedCards + done.sortedCards
        for c in allCards {
            if let due = c.dueDate {
                #expect(due == calendar.startOfDay(for: due))
                #expect(c.includesTime == false)
            }
        }
    }

    @Test("seeding twice does not duplicate boards")
    func seedingTwiceIsIdempotent() {
        let env = TestContainer()
        FixtureSeeder.seed("standard", context: env.context)
        FixtureSeeder.seed("standard", context: env.context)

        let boards = fetchBoards(env.context)
        #expect(boards.count == 2)
    }

    @Test("large fixture seeds 1 board, 3 lists, 500 deterministically-titled cards")
    func largeFixtureShape() {
        let env = TestContainer()
        FixtureSeeder.seed("large", context: env.context)

        let boards = fetchBoards(env.context)
        #expect(boards.count == 1)
        let board = boards[0]
        #expect(board.name == "Large")
        #expect(board.sortedLists.map(\.name) == ["To Do", "In Progress", "Done"])

        let allCards = board.sortedLists.flatMap(\.sortedCards)
        #expect(allCards.count == 500)
        // Deterministic titles: "Card 0001" is the first card of the first list (round-robin).
        #expect(board.sortedLists[0].sortedCards.first?.title == "Card 0001")
        #expect(Set(allCards.map(\.title)).count == 500) // all unique
    }

    @Test("empty fixture seeds zero boards but still seeds labels")
    func emptyFixtureSeedsNoBoardsButLabels() {
        let env = TestContainer()
        FixtureSeeder.seed("empty", context: env.context)

        #expect(fetchBoards(env.context).isEmpty)
        let labels = (try? env.context.fetch(FetchDescriptor<CardLabel>())) ?? []
        #expect(labels.count == 8)
    }
}
