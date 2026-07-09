import Testing
import Foundation
import SwiftData
@testable import Tack

/// M-F SPIKE (Task 0) — the evidence that decides the undo posture of deleteArea / setArea /
/// createArea(named:moving:). Three prior findings frame the risk: the on-disk Board delete
/// fatally asserts inside SwiftData's undo snapshotting; the import spike's redo silently
/// dropped third-level inserts; and moveCard's cross-list reassignment (Card.list rewritten
/// across two relationship collections) broke REDO and ships on manual inverses. Area delete
/// (.nullify releasing N Board.area fields at once) and setArea (Board.area reassigned across
/// two Area.boards inverse collections) are those exact shapes one level up.
///
/// ORACLES: exact fetchCounts + membership by `persistentModelID` — NEVER ObjectIdentifier
/// (instances refault across saves; the import spike's ObjectIdentifier verdicts varied
/// run-to-run) and never bare "didn't crash" (the known failure mode is SILENT wrong state
/// after redo, not just a crash).
///
/// VERDICT PROTOCOL (per LEG, judged independently): run the suite 3×. A leg is GREEN when its
/// tests pass in 3/3 runs; RED on any crash, hang (>6 min IS a hang), or failed assertion in
/// any run. A crash aborts the runner and MASKS later tests — the suite is .serialized with the
/// delete leg LAST for exactly that reason; any masked test is re-run individually 3× via
/// -only-testing:TackTests/AreaUndoOnDiskTests/<testName> before its leg is judged.
/// GREEN legs keep their trial withUndoGroup forms (Task 1a; this file stays verbatim as the
/// regression sentinel). RED legs take their PRE-AGREED fallback (Task 1b): leg A (deleteArea)
/// → deleteBoard's detach-and-clear, non-undoable, stack-wiping; leg B (setArea) → moveCard's
/// manual-inverse registerUndoable pattern; leg C (createArea moving a board) → the area insert
/// keeps withUndoGroup and the board move routes through setArea's shipped form afterwards.
@MainActor
@Suite("Area relationship-undo on-disk spike", .serialized)
struct AreaUndoOnDiskTests {

    /// Boards Alpha/Beta/Gamma (global positions 0/1/2); Alpha and Beta grouped into "Home";
    /// Gamma stays ungrouped as the untouched control. Stack CLEARED after seeding so the only
    /// group under test is the operation itself.
    private func seed(_ env: OnDiskTestStore) throws -> (home: Area, alpha: Board, beta: Board, gamma: Board) {
        env.store.ensureLabelsSeeded()
        let alpha = env.store.createBoard(name: "Alpha", emoji: nil)
        let beta = env.store.createBoard(name: "Beta", emoji: nil)
        let gamma = env.store.createBoard(name: "Gamma", emoji: nil)
        let home = try #require(env.store.createArea(named: "Home", moving: alpha))
        env.store.setArea(beta, to: home)
        try env.context.save()
        env.undoManager.removeAllActions()
        return (home, alpha, beta, gamma)
    }

    // MARK: - Leg C: createArea(named:moving:) — insert + relationship write in ONE group

    @Test("leg C: createArea moving a board — undo removes area AND releases board; redo restores both")
    func createAreaMovingBoardUndoRedo() throws {
        let env = try OnDiskTestStore(directoryPrefix: "TackAreaSpike")
        defer { env.tearDown() }
        let (_, _, _, gamma) = try seed(env)
        let gammaPID = gamma.persistentModelID

        let work = try #require(env.store.createArea(named: "Work", moving: gamma))
        #expect(try env.context.fetchCount(FetchDescriptor<Area>()) == 2)
        #expect(gamma.area?.name == "Work")

        env.undoManager.undo()
        #expect(try env.context.fetchCount(FetchDescriptor<Area>()) == 1, "the Work area insert must revert")
        #expect(gamma.area == nil, "one ⌘Z reverses the WHOLE New Area gesture, move included")
        #expect(try env.context.fetchCount(FetchDescriptor<Board>()) == 3, "no board may vanish")

        env.undoManager.redo()
        #expect(try env.context.fetchCount(FetchDescriptor<Area>()) == 2)
        let restoredWork = try #require(env.store.fetchAreasForTesting().first { $0.name == "Work" })
        #expect(restoredWork.sortedBoards.map(\.persistentModelID) == [gammaPID],
                "redo must restore MEMBERSHIP, not just the area row — the silent-drop oracle")
        _ = work
    }

    // MARK: - Leg B: setArea — the two-inverse-collections reassignment (the moveCard shape)

    @Test("leg B: setArea between areas — undo → redo → undo, exact membership both ways")
    func setAreaBetweenAreasUndoRedoIntegrity() throws {
        let env = try OnDiskTestStore(directoryPrefix: "TackAreaSpike")
        defer { env.tearDown() }
        let (home, alpha, beta, _) = try seed(env)
        let work = try #require(env.store.createArea(named: "Work", moving: nil))
        try env.context.save()
        env.undoManager.removeAllActions()
        let alphaPID = alpha.persistentModelID
        let betaPID = beta.persistentModelID

        env.store.setArea(alpha, to: work)   // area→area: BOTH inverse collections rewritten
        #expect(home.sortedBoards.map(\.persistentModelID) == [betaPID])
        #expect(work.sortedBoards.map(\.persistentModelID) == [alphaPID])

        env.undoManager.undo()
        #expect(alpha.area?.persistentModelID == home.persistentModelID)
        #expect(home.sortedBoards.map(\.persistentModelID) == [alphaPID, betaPID],
                "undo must restore BOTH collections exactly")
        #expect(work.sortedBoards.isEmpty)

        env.undoManager.redo()
        #expect(home.sortedBoards.map(\.persistentModelID) == [betaPID],
                "redo is the moveCard-class probe: membership must be EXACT, not dropped")
        #expect(work.sortedBoards.map(\.persistentModelID) == [alphaPID])

        env.undoManager.undo()
        #expect(home.sortedBoards.map(\.persistentModelID) == [alphaPID, betaPID])
        #expect(work.sortedBoards.isEmpty)
        #expect(try env.context.fetchCount(FetchDescriptor<Board>()) == 3, "no board lost in the cycle")
    }

    @Test("leg B: setArea ungrouped → area and back to nil — each one clean undo/redo step")
    func setAreaIntoAreaFromUngroupedUndoRedo() throws {
        let env = try OnDiskTestStore(directoryPrefix: "TackAreaSpike")
        defer { env.tearDown() }
        let (home, _, _, gamma) = try seed(env)
        let gammaPID = gamma.persistentModelID

        env.store.setArea(gamma, to: home)   // nil → area
        #expect(gamma.area?.persistentModelID == home.persistentModelID)
        env.undoManager.undo()
        #expect(gamma.area == nil)
        #expect(home.sortedBoards.count == 2, "home's own membership untouched by the undo")
        env.undoManager.redo()
        #expect(home.sortedBoards.map(\.persistentModelID).contains(gammaPID))

        env.undoManager.removeAllActions()
        env.store.setArea(gamma, to: nil)    // area → nil
        #expect(gamma.area == nil)
        env.undoManager.undo()
        #expect(gamma.area?.persistentModelID == home.persistentModelID)
        env.undoManager.redo()
        #expect(gamma.area == nil)
        #expect(gamma.position == 2, "global position never moves with area membership")
    }

    // MARK: - Leg A: deleteArea — the N-board .nullify release (LAST: likeliest to crash)

    @Test("leg A: deleteArea releases members — undo restores row AND membership; redo re-releases")
    func deleteAreaUndoRedoIntegrity() throws {
        let env = try OnDiskTestStore(directoryPrefix: "TackAreaSpike")
        defer { env.tearDown() }
        let (home, alpha, beta, gamma) = try seed(env)
        let homePID = home.persistentModelID
        let alphaPID = alpha.persistentModelID
        let betaPID = beta.persistentModelID

        env.store.deleteArea(home)
        #expect(try env.context.fetchCount(FetchDescriptor<Area>()) == 0)
        #expect(try env.context.fetchCount(FetchDescriptor<Board>()) == 3, "nullify NEVER deletes boards")
        #expect(alpha.area == nil && beta.area == nil, "members released to ungrouped")
        #expect([alpha, beta, gamma].map(\.position) == [0, 1, 2], "global positions untouched")

        env.undoManager.undo()
        #expect(try env.context.fetchCount(FetchDescriptor<Area>()) == 1)
        let restored = try #require(env.store.fetchAreasForTesting().first)
        #expect(restored.persistentModelID == homePID, "undo must restore the row, not a lookalike")
        #expect(restored.sortedBoards.map(\.persistentModelID) == [alphaPID, betaPID],
                "MEMBERSHIP is the silent-loss oracle — an empty restored area is a RED verdict")
        #expect(gamma.area == nil, "the control board stays ungrouped")

        env.undoManager.redo()
        #expect(try env.context.fetchCount(FetchDescriptor<Area>()) == 0)
        #expect(alpha.area == nil && beta.area == nil)
        #expect(try env.context.fetchCount(FetchDescriptor<Board>()) == 3)

        env.undoManager.undo()
        let restoredAgain = try #require(env.store.fetchAreasForTesting().first)
        #expect(restoredAgain.persistentModelID == homePID)
        #expect(restoredAgain.sortedBoards.map(\.persistentModelID) == [alphaPID, betaPID])
    }
}
