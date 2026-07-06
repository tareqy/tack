import Testing
import Foundation
@testable import Kanban

@MainActor
@Suite("BoardStore — Lists")
struct BoardStoreListTests {
    @Test("addList appends with the correct position")
    func addListAppends() {
        let env = TestContainer()
        let board = env.store.createBoard(name: "Board", emoji: nil)
        let newList = env.store.addList(to: board, name: "Backlog")
        #expect(newList.position == 3)
        #expect(board.sortedLists.map(\.name) == ["To Do", "In Progress", "Done", "Backlog"])
    }

    @Test("renameList updates the name")
    func renameList() {
        let env = TestContainer()
        let board = env.store.createBoard(name: "Board", emoji: nil)
        let list = board.sortedLists[0]
        env.store.renameList(list, to: "Todo Renamed")
        #expect(list.name == "Todo Renamed")
    }

    @Test("deleteList renumbers survivors to 0..<n")
    func deleteListRenumbers() {
        let env = TestContainer()
        let board = env.store.createBoard(name: "Board", emoji: nil)
        let middle = board.sortedLists[1] // "In Progress"
        env.store.deleteList(middle)
        let remaining = board.sortedLists
        #expect(remaining.map(\.name) == ["To Do", "Done"])
        #expect(remaining.map(\.position) == [0, 1])
    }

    @Test("moveList within board renumbers all lists 0..<n")
    func moveListRenumbers() {
        let env = TestContainer()
        let board = env.store.createBoard(name: "Board", emoji: nil)
        let toDo = board.sortedLists[0]
        env.store.moveList(toDo, to: 2)
        let names = board.sortedLists.map(\.name)
        #expect(names == ["In Progress", "Done", "To Do"])
        #expect(board.sortedLists.map(\.position) == [0, 1, 2])
    }

    // MARK: - M9: setCollapsed

    @Test("setCollapsed(true) collapses the list without touching any list's position")
    func setCollapsedCollapsesWithoutTouchingPositions() {
        let env = TestContainer()
        let board = env.store.createBoard(name: "Board", emoji: nil)
        let list = board.sortedLists[1] // "In Progress"
        let positionsBefore = board.sortedLists.map(\.position)
        #expect(list.isCollapsed == false)

        env.store.setCollapsed(list, true)

        #expect(list.isCollapsed == true)
        #expect(board.sortedLists.map(\.position) == positionsBefore)
    }

    @Test("setCollapsed(false) expands a previously collapsed list")
    func setCollapsedExpands() {
        let env = TestContainer()
        let board = env.store.createBoard(name: "Board", emoji: nil)
        let list = board.sortedLists[0]
        env.store.setCollapsed(list, true)
        #expect(list.isCollapsed == true)

        env.store.setCollapsed(list, false)

        #expect(list.isCollapsed == false)
    }

    @Test("setCollapsed is exactly one undo step in each direction")
    func setCollapsedIsOneUndoStepEachWay() {
        let env = TestContainer(withUndo: true)
        let board = env.store.createBoard(name: "Board", emoji: nil)
        let list = board.sortedLists[0]

        env.store.setCollapsed(list, true)
        #expect(list.isCollapsed == true)
        env.undoManager?.undo()
        #expect(list.isCollapsed == false)
        env.undoManager?.redo()
        #expect(list.isCollapsed == true)

        env.store.setCollapsed(list, false)
        #expect(list.isCollapsed == false)
        env.undoManager?.undo()
        #expect(list.isCollapsed == true)
        env.undoManager?.redo()
        #expect(list.isCollapsed == false)
    }

    @Test("setCollapsed with the current value registers no undo step")
    func setCollapsedNoOpRegistersNoUndoStep() {
        let env = TestContainer(withUndo: true)
        let board = env.store.createBoard(name: "Board", emoji: nil)
        let list = board.sortedLists[0]
        #expect(list.isCollapsed == false)

        // Already expanded: calling setCollapsed(false) must be a no-op. This is what
        // makes the pill's double `expand()` binding (chevron Button + onTapGesture) safe —
        // a double-fire pushes zero extra undo groups.
        env.store.setCollapsed(list, false)
        #expect(list.isCollapsed == false)

        // createBoard == exactly 1 undoable user step. If the no-op call above had
        // registered a 2nd (spurious) group, this count would be 2.
        var undoCount = 0
        while env.undoManager?.canUndo == true {
            env.undoManager?.undo()
            undoCount += 1
        }
        #expect(undoCount == 1)
    }
}
