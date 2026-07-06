import Testing
import Foundation
@testable import Kanban

@MainActor
@Suite("BoardStore — Cards")
struct BoardStoreCardTests {
    func makeBoard(_ env: TestContainer) -> Board {
        env.store.createBoard(name: "Board", emoji: nil)
    }

    @Test("addCard appends with the correct position")
    func addCardAppends() {
        let env = TestContainer()
        let board = makeBoard(env)
        let list = board.sortedLists[0]
        let card = env.store.addCard(to: list, title: "First")
        #expect(card.position == 0)
        let second = env.store.addCard(to: list, title: "Second")
        #expect(second.position == 1)
        #expect(list.sortedCards.map(\.title) == ["First", "Second"])
    }

    @Test("updateTitle bumps updatedAt, and only then")
    func updateTitleBumpsUpdatedAt() {
        let env = TestContainer()
        let board = makeBoard(env)
        let list = board.sortedLists[0]
        let card = env.store.addCard(to: list, title: "Original")
        let originalUpdatedAt = card.updatedAt

        Thread.sleep(forTimeInterval: 0.01)
        env.store.updateTitle(card, "Renamed")
        #expect(card.title == "Renamed")
        #expect(card.updatedAt > originalUpdatedAt)

        // moveCard is purely positional and must NOT bump updatedAt.
        let afterRenameUpdatedAt = card.updatedAt
        Thread.sleep(forTimeInterval: 0.01)
        let secondCard = env.store.addCard(to: list, title: "Other")
        env.store.moveCard(card, to: list, at: 1)
        _ = secondCard
        #expect(card.updatedAt == afterRenameUpdatedAt)
    }

    @Test("deleteCard renumbers survivors to 0..<n")
    func deleteCardRenumbers() {
        let env = TestContainer()
        let board = makeBoard(env)
        let list = board.sortedLists[0]
        let first = env.store.addCard(to: list, title: "First")
        _ = env.store.addCard(to: list, title: "Second")
        let third = env.store.addCard(to: list, title: "Third")
        env.store.deleteCard(first)
        let remaining = list.sortedCards
        #expect(remaining.map(\.title) == ["Second", "Third"])
        #expect(remaining.map(\.position) == [0, 1])
        #expect(third.position == 1)
    }

    @Test("moveCard same-list reorder")
    func moveCardSameList() {
        let env = TestContainer()
        let board = makeBoard(env)
        let list = board.sortedLists[0]
        let a = env.store.addCard(to: list, title: "A")
        _ = env.store.addCard(to: list, title: "B")
        _ = env.store.addCard(to: list, title: "C")
        env.store.moveCard(a, to: list, at: 2)
        #expect(list.sortedCards.map(\.title) == ["B", "C", "A"])
        #expect(list.sortedCards.map(\.position) == [0, 1, 2])
    }

    @Test("moveCard cross-list at head updates both lists' positions and card.list")
    func moveCardCrossListHead() {
        let env = TestContainer()
        let board = makeBoard(env)
        let source = board.sortedLists[0]
        let dest = board.sortedLists[1]
        let a = env.store.addCard(to: source, title: "A")
        let b = env.store.addCard(to: source, title: "B")
        let x = env.store.addCard(to: dest, title: "X")
        let y = env.store.addCard(to: dest, title: "Y")

        env.store.moveCard(a, to: dest, at: 0)

        #expect(a.list?.id == dest.id)
        #expect(source.sortedCards.map(\.title) == ["B"])
        #expect(source.sortedCards.map(\.position) == [0])
        #expect(dest.sortedCards.map(\.title) == ["A", "X", "Y"])
        #expect(dest.sortedCards.map(\.position) == [0, 1, 2])
        _ = b; _ = x; _ = y
    }

    @Test("moveCard cross-list at middle updates both lists' positions")
    func moveCardCrossListMiddle() {
        let env = TestContainer()
        let board = makeBoard(env)
        let source = board.sortedLists[0]
        let dest = board.sortedLists[1]
        let a = env.store.addCard(to: source, title: "A")
        _ = env.store.addCard(to: dest, title: "X")
        _ = env.store.addCard(to: dest, title: "Y")

        env.store.moveCard(a, to: dest, at: 1)

        #expect(a.list?.id == dest.id)
        #expect(source.sortedCards.isEmpty)
        #expect(dest.sortedCards.map(\.title) == ["X", "A", "Y"])
        #expect(dest.sortedCards.map(\.position) == [0, 1, 2])
    }

    @Test("moveCard cross-list at tail updates both lists' positions")
    func moveCardCrossListTail() {
        let env = TestContainer()
        let board = makeBoard(env)
        let source = board.sortedLists[0]
        let dest = board.sortedLists[1]
        let a = env.store.addCard(to: source, title: "A")
        _ = env.store.addCard(to: dest, title: "X")
        _ = env.store.addCard(to: dest, title: "Y")

        env.store.moveCard(a, to: dest, at: 2)

        #expect(a.list?.id == dest.id)
        #expect(source.sortedCards.isEmpty)
        #expect(dest.sortedCards.map(\.title) == ["X", "Y", "A"])
        #expect(dest.sortedCards.map(\.position) == [0, 1, 2])
    }

    @Test("moveCard to an empty list")
    func moveCardToEmptyList() {
        let env = TestContainer()
        let board = makeBoard(env)
        let source = board.sortedLists[0]
        let dest = board.sortedLists[1]
        let a = env.store.addCard(to: source, title: "A")
        _ = env.store.addCard(to: source, title: "B")

        env.store.moveCard(a, to: dest, at: 0)

        #expect(a.list?.id == dest.id)
        #expect(dest.sortedCards.map(\.title) == ["A"])
        #expect(dest.sortedCards.map(\.position) == [0])
        #expect(source.sortedCards.map(\.title) == ["B"])
        #expect(source.sortedCards.map(\.position) == [0])
    }

    // MARK: - applyCardEdits (M6 card detail sheet)

    @Test("applyCardEdits with no changes registers no undo step and does not bump updatedAt")
    func applyCardEditsNoOpRegistersNoUndoStep() {
        let env = TestContainer(withUndo: true)
        env.store.ensureLabelsSeeded()
        let board = makeBoard(env)
        let list = board.sortedLists[0]
        let card = env.store.addCard(to: list, title: "Task")
        env.store.toggleLabel(.red, on: card)
        let originalUpdatedAt = card.updatedAt

        Thread.sleep(forTimeInterval: 0.01)
        env.store.applyCardEdits(
            card,
            title: card.title,
            details: card.details,
            labels: [.red],
            dueDate: card.dueDate
        )

        #expect(card.updatedAt == originalUpdatedAt)

        // ensureLabelsSeeded, createBoard (+3 lists), addCard, toggleLabel(.red) == exactly 4
        // undoable user steps. If the no-op call had registered a 5th (spurious) group, this
        // count would be 5.
        var undoCount = 0
        while env.undoManager?.canUndo == true {
            env.undoManager?.undo()
            undoCount += 1
        }
        #expect(undoCount == 4)
    }

    @Test("applyCardEdits applies title, details, and dueDate changes and bumps updatedAt")
    func applyCardEditsAppliesFieldChanges() {
        let env = TestContainer()
        let board = makeBoard(env)
        let list = board.sortedLists[0]
        let card = env.store.addCard(to: list, title: "Original")
        let originalUpdatedAt = card.updatedAt

        Thread.sleep(forTimeInterval: 0.01)
        let dueDateWithTime = Calendar.current.date(byAdding: .day, value: 3, to: .now)!
        env.store.applyCardEdits(
            card,
            title: "Renamed",
            details: "Some details",
            labels: [],
            dueDate: dueDateWithTime
        )

        #expect(card.title == "Renamed")
        #expect(card.details == "Some details")
        #expect(card.dueDate == Calendar.current.startOfDay(for: dueDateWithTime))
        #expect(card.includesTime == false)
        #expect(card.updatedAt > originalUpdatedAt)
    }

    @Test("applyCardEdits diffs labels: adds new ones and removes dropped ones")
    func applyCardEditsDiffsLabels() {
        let env = TestContainer()
        env.store.ensureLabelsSeeded()
        let board = makeBoard(env)
        let list = board.sortedLists[0]
        let card = env.store.addCard(to: list, title: "Task")
        env.store.toggleLabel(.red, on: card)
        env.store.toggleLabel(.blue, on: card)
        #expect(Set(card.labels.map(\.colorName)) == ["red", "blue"])

        env.store.applyCardEdits(
            card,
            title: card.title,
            details: card.details,
            labels: [.blue, .green], // drop red, keep blue, add green
            dueDate: card.dueDate
        )

        #expect(Set(card.labels.map(\.colorName)) == ["blue", "green"])
    }

    @Test("applyCardEdits's whole edit undoes in one step, including labels")
    func applyCardEditsUndoesInOneStep() {
        let env = TestContainer(withUndo: true)
        env.store.ensureLabelsSeeded()
        let board = makeBoard(env)
        let list = board.sortedLists[0]
        let card = env.store.addCard(to: list, title: "Original")
        env.store.toggleLabel(.red, on: card)

        env.store.applyCardEdits(
            card,
            title: "Renamed",
            details: "New details",
            labels: [.blue],
            dueDate: .now
        )
        #expect(card.title == "Renamed")
        #expect(card.details == "New details")
        #expect(Set(card.labels.map(\.colorName)) == ["blue"])
        #expect(card.dueDate != nil)

        env.undoManager?.undo()

        #expect(card.title == "Original")
        #expect(card.details == nil)
        #expect(Set(card.labels.map(\.colorName)) == ["red"])
        #expect(card.dueDate == nil)
    }

    @Test("applyCardEdits keeps the existing title when the new title is empty/whitespace")
    func applyCardEditsEmptyTitleIsNoOp() {
        let env = TestContainer()
        let board = makeBoard(env)
        let list = board.sortedLists[0]
        let card = env.store.addCard(to: list, title: "Keep Me")
        let originalUpdatedAt = card.updatedAt

        Thread.sleep(forTimeInterval: 0.01)
        env.store.applyCardEdits(card, title: "   ", details: "Added details", labels: [], dueDate: nil)

        #expect(card.title == "Keep Me")
        // Other fields DID change, so the whole call still applies and still bumps updatedAt —
        // the empty-title rule only no-ops the title itself.
        #expect(card.updatedAt > originalUpdatedAt)
        #expect(card.details == "Added details")
    }
}
