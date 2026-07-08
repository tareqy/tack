import Testing
import Foundation
import SwiftData
@testable import Tack

/// E-01 export DTO: pure mapping + deterministic, versioned, round-trippable JSON. Seeds the
/// standard fixture through the real `FixtureSeeder`/`BoardStore` path, then asserts the encoded
/// envelope decodes back to the same data graph.
@MainActor
@Suite("ExportDocument")
struct ExportDocumentTests {

    /// Seeds the standard fixture and runs `body` with the position-ordered boards, keeping the
    /// backing `TestContainer` (hence its `ModelContainer`) alive for the whole body — otherwise
    /// the container would deallocate and reset its context, invalidating the `Board` models
    /// mid-test.
    private func withStandardBoards(_ body: ([Board]) throws -> Void) rethrows {
        let env = TestContainer()
        defer { withExtendedLifetime(env) {} }
        FixtureSeeder.seed("standard", context: env.context)
        let boards = (try? env.context.fetch(FetchDescriptor<Board>(sortBy: [SortDescriptor(\.position)]))) ?? []
        try body(boards)
    }

    @Test("formatVersion is 2 and present in the encoded JSON")
    func formatVersionIsTwo() throws {
        try withStandardBoards { boards in
            let envelope = ExportDocument.makeEnvelope(boards: boards)
            #expect(envelope.formatVersion == 2)

            let json = String(data: try ExportDocument.encode(envelope), encoding: .utf8)!
            #expect(json.contains("\"formatVersion\""))
            // The value round-trips as 2 regardless of pretty-print spacing.
            #expect(try ExportDocument.decode(Data(json.utf8)).formatVersion == 2)
        }
    }

    @Test("round trip preserves board/list/card counts, fields, order, and labels")
    func roundTripPreservesStructureAndValues() throws {
        try withStandardBoards { boards in
            let envelope = ExportDocument.makeEnvelope(boards: boards)
            let data = try ExportDocument.encode(envelope)
            let decoded = try ExportDocument.decode(data)

            // Counts + order.
            #expect(decoded.boards.map(\.name) == ["Groceries", "Work"])
            #expect(decoded.boards.map(\.position) == [0, 1])
            #expect(decoded.boards.map(\.emoji) == ["🛒", "💼"])

            let groceries = decoded.boards[0]
            #expect(groceries.about == "Weekly shopping run", "the fixture's about note round-trips")
            #expect(groceries.lists.map(\.name) == ["To Do", "In Progress", "Done"])
            #expect(groceries.lists.map(\.position) == [0, 1, 2])
            #expect(groceries.lists.allSatisfy { !$0.isCollapsed })

            let toDo = groceries.lists[0]
            #expect(toDo.cards.map(\.title) == ["Buy milk", "Call plumber", "Return library books"])
            #expect(toDo.cards.map(\.position) == [0, 1, 2])
            #expect(groceries.lists[1].cards.map(\.title) == ["Write report"])
            #expect(groceries.lists[2].cards.map(\.title) == ["Book flights"])

            // Labels round-trip as color-name arrays in fixed palette order.
            #expect(toDo.cards[0].labels == ["green", "blue"])   // Buy milk
            #expect(toDo.cards[1].labels.isEmpty)                 // Call plumber (unlabeled)
            #expect(groceries.lists[1].cards[0].labels == ["red"]) // Write report

            // Work board: 3 empty default lists.
            let work = decoded.boards[1]
            #expect(work.lists.map(\.name) == ["To Do", "In Progress", "Done"])
            #expect(work.lists.allSatisfy { $0.cards.isEmpty })

            // Re-encoding the decoded envelope reproduces the exact bytes — proves the whole graph
            // (dates included) survives the round trip stably.
            #expect(try ExportDocument.encode(decoded) == data)
        }
    }

    @Test("dates round-trip as ISO-8601 (due dates exactly; timestamps to the second)")
    func datesRoundTrip() throws {
        try withStandardBoards { boards in
            let envelope = ExportDocument.makeEnvelope(boards: boards)
            let decoded = try ExportDocument.decode(try ExportDocument.encode(envelope))

            // Due dates are start-of-day (zero sub-seconds), so ISO-8601 is lossless: exact equality.
            let buyMilkDue = boards[0].sortedLists[0].sortedCards[0].dueDate
            #expect(decoded.boards[0].lists[0].cards[0].dueDate == buyMilkDue)
            // Book flights has no due date — round-trips as nil (key omitted).
            #expect(decoded.boards[0].lists[2].cards[0].dueDate == nil)

            // createdAt (a `.now` with sub-seconds) survives to whole-second precision.
            let originalCreatedAt = boards[0].createdAt
            let roundTripped = decoded.boards[0].createdAt
            #expect(abs(roundTripped.timeIntervalSince(originalCreatedAt)) < 1.0)
        }
    }

    @Test("encoded JSON has stable sorted keys and position-ordered boards")
    func stableKeyOrderAndPositionOrder() throws {
        try withStandardBoards { boards in
            let json = String(data: try ExportDocument.encode(ExportDocument.makeEnvelope(boards: boards)), encoding: .utf8)!

            // `.sortedKeys` → top-level keys alphabetical: boards, exportedAt, formatVersion.
            let boardsAt = json.range(of: "\"boards\"")!.lowerBound
            let exportedAt = json.range(of: "\"exportedAt\"")!.lowerBound
            let versionAt = json.range(of: "\"formatVersion\"")!.lowerBound
            #expect(boardsAt < exportedAt)
            #expect(exportedAt < versionAt)

            // Boards appear in position order (Groceries before Work).
            let groceriesAt = json.range(of: "\"Groceries\"")!.lowerBound
            let workAt = json.range(of: "\"Work\"")!.lowerBound
            #expect(groceriesAt < workAt)
        }
    }

    @Test("an empty store exports a well-formed, boardless envelope")
    func emptyStoreExportsZeroBoards() throws {
        let env = TestContainer()
        FixtureSeeder.seed("empty", context: env.context)
        let boards = (try? env.context.fetch(FetchDescriptor<Board>())) ?? []

        let decoded = try ExportDocument.decode(try ExportDocument.encode(ExportDocument.makeEnvelope(boards: boards)))
        #expect(decoded.boards.isEmpty)
        #expect(decoded.formatVersion == 2)
    }
}
