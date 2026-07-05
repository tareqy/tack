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
        default:
            break // Other fixtures (e.g. "standard") arrive in M3.
        }
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
