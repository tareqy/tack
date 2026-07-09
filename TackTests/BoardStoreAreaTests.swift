import Testing
import Foundation
import SwiftData
@testable import Tack

/// M-F: the Area store surface — creation (find-or-create by the exact trimmed merge key),
/// membership moves, nullify delete, rename, collapse, and the per-section board reorder.
/// In-memory (`TestContainer`); the on-disk undo posture is AreaUndoOnDiskTests' job.
@MainActor
@Suite("BoardStore areas")
struct BoardStoreAreaTests {

    private func boards(_ env: TestContainer) -> [Board] {
        ((try? env.context.fetch(FetchDescriptor<Board>())) ?? []).sorted { $0.position < $1.position }
    }

    @Test("createArea appends position max+1 and is one undo step")
    func createAreaAppendsPositionAndIsOneUndoStep() throws {
        let env = TestContainer(withUndo: true)
        let first = try #require(env.store.createArea(named: "Home", moving: nil))
        #expect(first.position == 0)
        #expect(env.undoManager?.canUndo == true)
        env.undoManager?.removeAllActions()

        let second = try #require(env.store.createArea(named: "Work", moving: nil))
        #expect(second.position == 1)
        env.undoManager?.undo()
        #expect(env.store.fetchAreasForTesting().count == 1, "one ⌘Z removes exactly the new area")
        #expect(env.undoManager?.canUndo == false, "exactly one step")
    }

    @Test("createArea finds an existing area by exact trimmed name — never a duplicate row")
    func createAreaFindsExistingByExactTrimmedName() throws {
        let env = TestContainer()
        let home = try #require(env.store.createArea(named: "Home", moving: nil))
        let again = try #require(env.store.createArea(named: "  Home  ", moving: nil))
        #expect(again.persistentModelID == home.persistentModelID, "trimmed exact match reuses the row")
        #expect(env.store.fetchAreasForTesting().count == 1)
    }

    @Test("createArea is case-sensitive: 'home' and 'Home' are different areas (the merge-key decision)")
    func createAreaIsCaseSensitive() throws {
        let env = TestContainer()
        _ = try #require(env.store.createArea(named: "Home", moving: nil))
        _ = try #require(env.store.createArea(named: "home", moving: nil))
        #expect(env.store.fetchAreasForTesting().count == 2,
                "exact match (the CardLabel attach precedent) — NOT localizedCaseInsensitive (a search affordance)")
    }

    @Test("createArea moving a board is ONE undo step covering insert + membership")
    func createAreaMovingBoardIsOneUndoStep() throws {
        let env = TestContainer(withUndo: true)
        let board = env.store.createBoard(name: "B", emoji: nil)
        env.undoManager?.removeAllActions()

        _ = try #require(env.store.createArea(named: "Home", moving: board))
        #expect(board.area?.name == "Home")
        env.undoManager?.undo()
        #expect(board.area == nil, "one ⌘Z reverses the whole New Area gesture")
        #expect(env.store.fetchAreasForTesting().isEmpty)
        #expect(env.undoManager?.canUndo == false, "exactly one step")
    }

    @Test("createArea with a whitespace-only name is a total no-op returning nil")
    func createAreaWhitespaceOnlyNameIsNoOp() {
        let env = TestContainer(withUndo: true)
        #expect(env.store.createArea(named: "   ", moving: nil) == nil)
        #expect(env.store.fetchAreasForTesting().isEmpty)
        #expect(env.undoManager?.canUndo == false, "no junk undo step")
    }

    @Test("setArea moves membership without touching any board's global position")
    func setAreaMovesWithoutTouchingPositions() throws {
        let env = TestContainer()
        let a = env.store.createBoard(name: "A", emoji: nil)
        let b = env.store.createBoard(name: "B", emoji: nil)
        let c = env.store.createBoard(name: "C", emoji: nil)
        let home = try #require(env.store.createArea(named: "Home", moving: nil))

        env.store.setArea(b, to: home)

        #expect(b.area?.persistentModelID == home.persistentModelID)
        #expect([a, b, c].map(\.position) == [0, 1, 2],
                "design (b): a board keeps its global position when it changes area")
    }

    @Test("setArea to the same destination is a whole-call no-op (no undo step) — grouped and ungrouped")
    func setAreaSameAreaIsNoOp() throws {
        let env = TestContainer(withUndo: true)
        let grouped = env.store.createBoard(name: "Grouped", emoji: nil)
        let ungrouped = env.store.createBoard(name: "Ungrouped", emoji: nil)
        let home = try #require(env.store.createArea(named: "Home", moving: grouped))
        env.undoManager?.removeAllActions()

        env.store.setArea(grouped, to: home)     // already there
        #expect(env.undoManager?.canUndo == false)

        env.store.setArea(ungrouped, to: nil)    // already ungrouped (nil == nil, the optional path)
        #expect(env.undoManager?.canUndo == false)
    }

    @Test("setArea to nil releases the board to ungrouped")
    func setAreaToNilReleases() throws {
        let env = TestContainer()
        let board = env.store.createBoard(name: "B", emoji: nil)
        let home = try #require(env.store.createArea(named: "Home", moving: board))

        env.store.setArea(board, to: nil)

        #expect(board.area == nil)
        #expect(home.boards.isEmpty)
        #expect(env.store.fetchAreasForTesting().count == 1, "the emptied area survives — deletion is explicit")
    }

    @Test("renameArea is one undo step; a no-change rename opens no group")
    func renameAreaIsOneUndoStep() throws {
        let env = TestContainer(withUndo: true)
        let home = try #require(env.store.createArea(named: "Home", moving: nil))
        env.undoManager?.removeAllActions()

        env.store.renameArea(home, to: "Home") // identity
        #expect(env.undoManager?.canUndo == false, "no-change rename must not be 'a change'")

        env.store.renameArea(home, to: "  Studio ")
        #expect(home.name == "Studio", "store trims — the one merge key is always trimmed")
        env.undoManager?.undo()
        #expect(home.name == "Home")
        #expect(env.undoManager?.canUndo == false, "exactly one step")
    }

    @Test("setAreaCollapsed toggles as one named step; a no-change call opens no group")
    func setAreaCollapsedTogglesOneUndoStep() throws {
        let env = TestContainer(withUndo: true)
        let home = try #require(env.store.createArea(named: "Home", moving: nil))
        env.undoManager?.removeAllActions()

        env.store.setAreaCollapsed(home, false) // already expanded
        #expect(env.undoManager?.canUndo == false)

        env.store.setAreaCollapsed(home, true)
        #expect(home.isCollapsed == true)
        env.undoManager?.undo()
        #expect(home.isCollapsed == false)
    }

    // MARK: - moveBoards(in:) — the sectioned B-06

    /// Global positions 0..4: A(un) B(Home) C(un) D(Home) E(Home).
    private func seedSections(_ env: TestContainer) throws -> (home: Area, all: [Board]) {
        let a = env.store.createBoard(name: "A", emoji: nil)
        let b = env.store.createBoard(name: "B", emoji: nil)
        let c = env.store.createBoard(name: "C", emoji: nil)
        let d = env.store.createBoard(name: "D", emoji: nil)
        let e = env.store.createBoard(name: "E", emoji: nil)
        let home = try #require(env.store.createArea(named: "Home", moving: b))
        env.store.setArea(d, to: home)
        env.store.setArea(e, to: home)
        return (home, [a, b, c, d, e])
    }

    @Test("moveBoards(in: area) reorders only that section; other boards keep exact positions")
    func moveBoardsInAreaReordersOnlyThatSection() throws {
        let env = TestContainer()
        let (home, _) = try seedSections(env)

        // Home section rows are [B, D, E] (global order). Move E (offset 2) to the front (offset 0).
        env.store.moveBoards(fromOffsets: IndexSet(integer: 2), toOffset: 0, in: home)

        #expect(boards(env).map(\.name) == ["A", "E", "C", "B", "D"],
                "members permute across slots 1/3/4; A and C never move")
        #expect(boards(env).map(\.position) == [0, 1, 2, 3, 4], "global contiguity renumbered")
    }

    @Test("moveBoards(in: nil) reorders the ungrouped section; area members keep exact positions")
    func moveBoardsInUngroupedSectionLeavesAreaMembersFixed() throws {
        let env = TestContainer()
        _ = try seedSections(env)

        // Ungrouped rows are [A, C]. Move C (offset 1) to the front (offset 0).
        env.store.moveBoards(fromOffsets: IndexSet(integer: 1), toOffset: 0, in: nil)

        #expect(boards(env).map(\.name) == ["C", "B", "A", "D", "E"],
                "A and C swap across slots 0/2; the Home members hold slots 1/3/4")
    }

    @Test("identity moveBoards(in:) registers no undo step and changes nothing")
    func moveBoardsInAreaIdentityIsNoOp() throws {
        let env = TestContainer(withUndo: true)
        let (home, _) = try seedSections(env)
        env.undoManager?.removeAllActions()

        env.store.moveBoards(fromOffsets: IndexSet(integer: 0), toOffset: 1, in: home)

        #expect(env.undoManager?.canUndo == false, "drop-it-back-where-it-was never eats a ⌘Z")
        #expect(boards(env).map(\.name) == ["A", "B", "C", "D", "E"])
    }

    @Test("moveBoards(in:) self-heals position gaps left by deleteBoard (the B-06 invariant, sectioned)")
    func moveBoardsHealsGapsAcrossSections() throws {
        let env = TestContainer()
        let (home, all) = try seedSections(env)
        env.store.deleteBoard(all[2]) // delete C (ungrouped) — leaves gap at position 2

        env.store.moveBoards(fromOffsets: IndexSet(integer: 1), toOffset: 0, in: home)

        #expect(boards(env).map(\.position) == [0, 1, 2, 3], "ALL boards renumbered contiguous")
        #expect(boards(env).map(\.name) == ["A", "D", "B", "E"], "D moved before B within Home's slots")
    }
}
