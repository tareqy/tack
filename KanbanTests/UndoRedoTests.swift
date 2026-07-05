import Testing
import Foundation
import SwiftData
@testable import Kanban

@MainActor
@Suite("Undo/Redo")
struct UndoRedoTests {
    @Test("undo after two separate creates only reverts the most recent one")
    func undoRevertsOnlyMostRecentOperation() {
        let env = TestContainer(withUndo: true)
        _ = env.store.createBoard(name: "Alpha", emoji: nil)
        _ = env.store.createBoard(name: "Beta", emoji: nil)

        env.undoManager?.undo()

        let boards = try! env.context.fetch(FetchDescriptor<Board>())
        #expect(boards.map(\.name) == ["Alpha"])
    }

    @Test("undo fully reverses createBoard including its 3 default lists")
    func undoReversesCreateBoardAndLists() {
        let env = TestContainer(withUndo: true)
        _ = env.store.createBoard(name: "Board", emoji: nil)

        env.undoManager?.undo()

        let boards = try! env.context.fetch(FetchDescriptor<Board>())
        let lists = try! env.context.fetch(FetchDescriptor<BoardList>())
        #expect(boards.isEmpty)
        #expect(lists.isEmpty)
    }

    @Test("redo re-creates the board and its lists after an undo")
    func redoRecreatesBoardAndLists() {
        let env = TestContainer(withUndo: true)
        _ = env.store.createBoard(name: "Board", emoji: nil)

        env.undoManager?.undo()
        env.undoManager?.redo()

        let boards = try! env.context.fetch(FetchDescriptor<Board>())
        #expect(boards.map(\.name) == ["Board"])
        #expect(boards.first?.sortedLists.map(\.name) == ["To Do", "In Progress", "Done"])
    }

    @Test("undo of renameBoard restores the previous name")
    func undoRenameBoard() {
        let env = TestContainer(withUndo: true)
        let board = env.store.createBoard(name: "Old", emoji: nil)
        env.store.renameBoard(board, to: "New")
        #expect(board.name == "New")

        env.undoManager?.undo()
        #expect(board.name == "Old")
    }

    @Test("undo of a cross-list moveCard restores both lists' exact order")
    func undoMoveCardRestoresBothLists() {
        let env = TestContainer(withUndo: true)
        let board = env.store.createBoard(name: "Board", emoji: nil)
        let source = board.sortedLists[0]
        let dest = board.sortedLists[1]
        let a = env.store.addCard(to: source, title: "A")
        _ = env.store.addCard(to: source, title: "B")
        _ = env.store.addCard(to: dest, title: "X")

        env.store.moveCard(a, to: dest, at: 0)
        #expect(source.sortedCards.map(\.title) == ["B"])
        #expect(dest.sortedCards.map(\.title) == ["A", "X"])

        env.undoManager?.undo()

        #expect(source.sortedCards.map(\.title) == ["A", "B"])
        #expect(dest.sortedCards.map(\.title) == ["X"])
        #expect(a.list?.id == source.id)
    }

    @Test("redo re-applies a moveCard after undo")
    func redoReappliesMoveCard() {
        let env = TestContainer(withUndo: true)
        let board = env.store.createBoard(name: "Board", emoji: nil)
        let source = board.sortedLists[0]
        let dest = board.sortedLists[1]
        let a = env.store.addCard(to: source, title: "A")
        _ = env.store.addCard(to: source, title: "B")
        _ = env.store.addCard(to: dest, title: "X")

        env.store.moveCard(a, to: dest, at: 0)
        env.undoManager?.undo()
        env.undoManager?.redo()

        #expect(source.sortedCards.map(\.title) == ["B"])
        #expect(dest.sortedCards.map(\.title) == ["A", "X"])
        #expect(a.list?.id == dest.id)
    }

    @Test("50 consecutive undoable creates can all be undone one step at a time")
    func fiftyConsecutiveOperationsAllUndoable() {
        let env = TestContainer(withUndo: true)
        for i in 0..<50 {
            env.store.createBoard(name: "Board \(i)", emoji: nil)
        }
        for _ in 0..<50 {
            env.undoManager?.undo()
        }
        let boards = try! env.context.fetch(FetchDescriptor<Board>())
        #expect(boards.isEmpty)
    }
}
