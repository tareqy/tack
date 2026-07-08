import Testing
import Foundation
import SwiftData
@testable import Tack

/// E-02 store-level import: materialization, positions, label attachment, undo shape, atomicity.
/// In-memory (`TestContainer`) — the on-disk undo behavior is covered by `ImportUndoOnDiskTests`.
@MainActor
@Suite("BoardStore import")
struct BoardStoreImportTests {

    /// A fixed envelope exercising nesting, labels, due dates, collapse state, and DELIBERATELY
    /// scrambled DTO positions (99/7/5/3/2/0) — the materializer must ignore them all.
    private func sampleEnvelope() -> ExportEnvelope {
        let created = Date(timeIntervalSince1970: 1_750_000_000)
        return ExportEnvelope(
            formatVersion: 1,
            exportedAt: Date(timeIntervalSince1970: 1_781_827_200),
            boards: [
                ExportBoard(
                    name: "Imported A", emoji: "📦", position: 99, themeName: "ocean",
                    customThemeHex: "FF8800", createdAt: created,
                    lists: [
                        ExportList(name: "Alpha", position: 7, isCollapsed: true, cards: [
                            ExportCard(title: "A1", details: "first", position: 5,
                                       dueDate: Date(timeIntervalSince1970: 1_781_740_800),
                                       includesTime: false, createdAt: created, updatedAt: created,
                                       labels: ["red", "blue"]),
                            ExportCard(title: "A2", details: nil, position: 2, dueDate: nil,
                                       includesTime: false, createdAt: created, updatedAt: created,
                                       labels: []),
                        ]),
                        ExportList(name: "Beta", position: 3, isCollapsed: false, cards: []),
                    ]
                ),
                ExportBoard(name: "Imported B", emoji: nil, position: 0, themeName: "default",
                            customThemeHex: nil, createdAt: created, lists: []),
            ]
        )
    }

    private func fetchBoards(_ context: ModelContext) -> [Board] {
        (try? context.fetch(FetchDescriptor<Board>(sortBy: [SortDescriptor(\.position)]))) ?? []
    }

    private func fetchLabels(_ context: ModelContext) -> [CardLabel] {
        (try? context.fetch(FetchDescriptor<CardLabel>())) ?? []
    }

    @Test("append into an empty store materializes the exact graph")
    func appendIntoEmptyMaterializesGraph() throws {
        let env = TestContainer()
        defer { withExtendedLifetime(env) {} }
        env.store.ensureLabelsSeeded()

        let imported = try env.store.importBoards(sampleEnvelope(), importedAt: Date(timeIntervalSince1970: 1_781_827_200))

        let boards = fetchBoards(env.context)
        #expect(boards.map(\.name) == ["Imported A", "Imported B"])
        #expect(boards.map(\.position) == [0, 1])
        #expect(imported.map(\.name) == ["Imported A", "Imported B"], "return value matches envelope order")

        let boardA = boards[0]
        #expect(boardA.emoji == "📦")
        #expect(boardA.themeName == "ocean")
        #expect(boardA.customThemeHex == "FF8800")
        #expect(boardA.createdAt == Date(timeIntervalSince1970: 1_750_000_000))

        let lists = boardA.sortedLists
        #expect(lists.map(\.name) == ["Alpha", "Beta"])
        #expect(lists.map(\.position) == [0, 1], "list positions come from array order, not DTO values")
        #expect(lists[0].isCollapsed == true)
        #expect(lists[0].createdAt == Date(timeIntervalSince1970: 1_781_827_200),
                "BoardList.createdAt is synthesized from importedAt (absent from the format)")

        let cards = lists[0].sortedCards
        #expect(cards.map(\.title) == ["A1", "A2"])
        #expect(cards.map(\.position) == [0, 1], "card positions come from array order, not DTO values")
        #expect(cards[0].details == "first")
        #expect(cards[0].dueDate == Date(timeIntervalSince1970: 1_781_740_800))
        #expect(cards[0].includesTime == false)
    }

    @Test("appended boards get positions after the existing max; existing boards untouched")
    func appendAfterExistingMax() throws {
        let env = TestContainer()
        defer { withExtendedLifetime(env) {} }
        env.store.ensureLabelsSeeded()
        let existing1 = env.store.createBoard(name: "Existing 0", emoji: nil)
        let existing2 = env.store.createBoard(name: "Existing 1", emoji: nil)
        existing2.position = 5   // simulate a position gap (deleteBoard doesn't renumber)
        try env.context.save()

        try env.store.importBoards(sampleEnvelope())

        let boards = fetchBoards(env.context)
        #expect(boards.map(\.name) == ["Existing 0", "Existing 1", "Imported A", "Imported B"])
        #expect(boards.map(\.position) == [0, 5, 6, 7], "imported = (max 5) + 1, +2; existing untouched")
        #expect(existing1.name == "Existing 0")
    }

    @Test("labels attach to the fetched palette rows by identity; palette stays exactly 8")
    func labelsAttachByIdentity() throws {
        let env = TestContainer()
        defer { withExtendedLifetime(env) {} }
        env.store.ensureLabelsSeeded()
        let paletteIDs = Set(fetchLabels(env.context).map(ObjectIdentifier.init))
        #expect(paletteIDs.count == 8)

        try env.store.importBoards(sampleEnvelope())

        #expect(fetchLabels(env.context).count == 8, "import must never insert CardLabel rows")
        let cardA1 = fetchBoards(env.context)[0].sortedLists[0].sortedCards[0]
        #expect(Set(cardA1.labels.map(\.colorName)) == ["red", "blue"])
        #expect(Set(cardA1.labels.map(ObjectIdentifier.init)).isSubset(of: paletteIDs),
                "attached labels are the SAME palette row objects, not copies")
    }

    @Test("append is exactly one undo step: undo removes the whole import, redo restores it")
    func appendIsOneUndoStep() throws {
        let env = TestContainer(withUndo: true)
        defer { withExtendedLifetime(env) {} }
        env.store.ensureLabelsSeeded()
        env.store.createBoard(name: "Existing", emoji: nil)

        try env.store.importBoards(sampleEnvelope())
        #expect(fetchBoards(env.context).count == 3)

        env.undoManager!.undo()
        #expect(fetchBoards(env.context).map(\.name) == ["Existing"], "one ⌘Z removes the entire import")
        #expect(fetchLabels(env.context).count == 8, "palette untouched by undo (fetched, not inserted)")

        env.undoManager!.redo()
        #expect(fetchBoards(env.context).count == 3, "one redo restores the entire import")
        #expect(fetchBoards(env.context)[1].sortedLists[0].sortedCards[0].labels.count == 2,
                "label joins restored by redo")
    }

    @Test("empty-envelope append is a no-op that registers no undo step")
    func emptyEnvelopeAppendIsNoOp() throws {
        let env = TestContainer(withUndo: true)
        defer { withExtendedLifetime(env) {} }

        let empty = ExportEnvelope(formatVersion: 1, exportedAt: .now, boards: [])
        let imported = try env.store.importBoards(empty)

        #expect(imported.isEmpty)
        #expect(fetchBoards(env.context).isEmpty)
        #expect(env.undoManager!.canUndo == false, "no empty 'Import Boards' group on the stack")
    }

    @Test("undo action name is 'Import Boards'")
    func undoActionName() throws {
        let env = TestContainer(withUndo: true)
        defer { withExtendedLifetime(env) {} }
        env.store.ensureLabelsSeeded()
        try env.store.importBoards(sampleEnvelope())
        #expect(env.undoManager!.undoActionName == "Import Boards")
    }
}
