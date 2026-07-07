import Testing
import Foundation
import SwiftData
@testable import Tack

@MainActor
@Suite("BoardStore — Boards")
struct BoardStoreBoardTests {
    @Test("createBoard yields exactly 3 default lists in order To Do, In Progress, Done")
    func createBoardDefaultLists() {
        let env = TestContainer()
        let board = env.store.createBoard(name: "Launch", emoji: "🚀")
        let lists = board.sortedLists
        #expect(lists.map(\.name) == ["To Do", "In Progress", "Done"])
        #expect(lists.map(\.position) == [0, 1, 2])
    }

    @Test("board positions increment across successive creates")
    func boardPositionsIncrement() {
        let env = TestContainer()
        let first = env.store.createBoard(name: "A", emoji: nil)
        let second = env.store.createBoard(name: "B", emoji: nil)
        let third = env.store.createBoard(name: "C", emoji: nil)
        #expect(first.position == 0)
        #expect(second.position == 1)
        #expect(third.position == 2)
    }

    @Test("renameBoard updates the name")
    func renameBoard() {
        let env = TestContainer()
        let board = env.store.createBoard(name: "Old", emoji: nil)
        env.store.renameBoard(board, to: "New")
        #expect(board.name == "New")
    }

    @Test("deleteBoard removes it from the store")
    func deleteBoard() {
        let env = TestContainer()
        let board = env.store.createBoard(name: "Doomed", emoji: nil)
        env.store.deleteBoard(board)
        let remaining = try! env.context.fetch(FetchDescriptor<Board>())
        #expect(remaining.isEmpty)
    }

    @Test("filterBoards is case-insensitive substring match")
    func filterBoardsCaseInsensitive() {
        let env = TestContainer()
        let alpha = env.store.createBoard(name: "Alpha Project", emoji: nil)
        _ = env.store.createBoard(name: "Beta Project", emoji: nil)
        let result = BoardStore.filterBoards([alpha], query: "alpha")
        #expect(result.map(\.id) == [alpha.id])
    }

    @Test("filterBoards with empty query returns all boards")
    func filterBoardsEmptyQuery() {
        let env = TestContainer()
        let alpha = env.store.createBoard(name: "Alpha", emoji: nil)
        let beta = env.store.createBoard(name: "Beta", emoji: nil)
        let result = BoardStore.filterBoards([alpha, beta], query: "")
        #expect(result.map(\.id) == [alpha.id, beta.id])
    }

    @Test("filterBoards substring match (not just prefix)")
    func filterBoardsSubstring() {
        let env = TestContainer()
        let board = env.store.createBoard(name: "Marketing Launch", emoji: nil)
        let result = BoardStore.filterBoards([board], query: "arket")
        #expect(result.map(\.id) == [board.id])
    }

    @Test("filterBoards excludes non-matching boards")
    func filterBoardsExcludesNonMatches() {
        let env = TestContainer()
        let board = env.store.createBoard(name: "Marketing", emoji: nil)
        let result = BoardStore.filterBoards([board], query: "zzz")
        #expect(result.isEmpty)
    }
}
