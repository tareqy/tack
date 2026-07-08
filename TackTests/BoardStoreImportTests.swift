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
        // persistentModelID, not ObjectIdentifier: ObjectIdentifier is not a stable oracle here —
        // SwiftData refaults/reissues Swift instances for the same persistent rows across saves,
        // so instance identity flakes even when the rows are genuinely the same.
        let paletteIDs = Set(fetchLabels(env.context).map(\.persistentModelID))
        #expect(paletteIDs.count == 8)

        try env.store.importBoards(sampleEnvelope())

        #expect(fetchLabels(env.context).count == 8, "import must never insert CardLabel rows")
        let cardA1 = fetchBoards(env.context)[0].sortedLists[0].sortedCards[0]
        #expect(Set(cardA1.labels.map(\.colorName)) == ["red", "blue"])
        #expect(Set(cardA1.labels.map(\.persistentModelID)).isSubset(of: paletteIDs),
                "attached labels are the SAME palette rows, not copies")
    }

    @Test("append import is not undoable: the undo stack is cleared (spike-fail fallback)")
    func appendClearsUndoStack() throws {
        let env = TestContainer(withUndo: true)
        defer { withExtendedLifetime(env) {} }
        env.store.ensureLabelsSeeded()
        env.store.createBoard(name: "Existing", emoji: nil)
        #expect(env.undoManager!.canUndo == true, "precondition: something undoable exists")

        try env.store.importBoards(sampleEnvelope())

        #expect(fetchBoards(env.context).count == 3)
        #expect(env.undoManager!.canUndo == false)
        #expect(env.undoManager!.canRedo == false)
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

    @Test("empty-envelope append preserves existing undo history (early return precedes the detach)")
    func emptyEnvelopeAppendPreservesUndoHistory() throws {
        let env = TestContainer(withUndo: true)
        defer { withExtendedLifetime(env) {} }
        env.store.ensureLabelsSeeded()
        env.store.createBoard(name: "Existing", emoji: nil)
        #expect(env.undoManager!.canUndo == true, "precondition: something undoable exists")

        let empty = ExportEnvelope(formatVersion: 1, exportedAt: .now, boards: [])
        let imported = try env.store.importBoards(empty)

        #expect(imported.isEmpty)
        #expect(env.undoManager!.canUndo == true, "an empty Add must not clear the stack (unlike a real import)")
    }

    @Test("a label name with no palette row is skipped, never inserted")
    func missingPaletteRowSkipped() throws {
        let env = TestContainer()
        defer { withExtendedLifetime(env) {} }
        // Deliberately DO NOT seed the palette: every label lookup misses, exercising
        // materialize's skip-never-insert guard directly.
        let imported = try env.store.importBoards(sampleEnvelope())

        #expect(fetchLabels(env.context).isEmpty, "materialize must never insert CardLabel rows")
        #expect(imported[0].sortedLists[0].sortedCards[0].labels.isEmpty)
    }

    // MARK: - Replace mode (Task 4)

    @Test("replace deletes existing boards; only envelope boards remain; palette stays 8")
    func replaceDeletesExisting() throws {
        let env = TestContainer()
        defer { withExtendedLifetime(env) {} }
        env.store.ensureLabelsSeeded()
        env.store.createBoard(name: "Old 1", emoji: nil)
        env.store.createBoard(name: "Old 2", emoji: nil)

        let imported = try env.store.replaceAllBoards(with: sampleEnvelope())

        #expect(fetchBoards(env.context).map(\.name) == ["Imported A", "Imported B"])
        #expect(fetchBoards(env.context).map(\.position) == [0, 1], "replace re-bases at position 0")
        #expect(fetchLabels(env.context).count == 8)
        #expect(imported.map(\.name) == ["Imported A", "Imported B"])
    }

    @Test("replace clears the undo stack (never undoable)")
    func replaceClearsUndoStack() throws {
        let env = TestContainer(withUndo: true)
        defer { withExtendedLifetime(env) {} }
        env.store.ensureLabelsSeeded()
        env.store.createBoard(name: "Old", emoji: nil)
        #expect(env.undoManager!.canUndo == true, "precondition: something undoable exists")

        try env.store.replaceAllBoards(with: sampleEnvelope())

        #expect(env.undoManager!.canUndo == false)
        #expect(env.undoManager!.canRedo == false)
    }

    @Test("replace with an empty envelope throws .emptyReplace and mutates nothing")
    func replaceEmptyThrowsAndMutatesNothing() throws {
        let env = TestContainer()
        defer { withExtendedLifetime(env) {} }
        env.store.ensureLabelsSeeded()
        env.store.createBoard(name: "Survivor", emoji: nil)

        let empty = ExportEnvelope(formatVersion: 1, exportedAt: .now, boards: [])
        #expect(throws: ImportError.emptyReplace) {
            try env.store.replaceAllBoards(with: empty)
        }
        #expect(fetchBoards(env.context).map(\.name) == ["Survivor"])
    }

    // MARK: - Byte-equality round trip (Task 4; the strongest cheap oracle)

    @Test("export → import into a fresh store → re-export reproduces the original bytes")
    func byteEqualityRoundTrip() throws {
        // Container A: seed via store ops, exercising EVERY format field — emoji, theme + custom
        // hex, a collapsed list, details, multiple labels, a due date (includesTime false).
        let a = TestContainer()
        defer { withExtendedLifetime(a) {} }
        a.store.ensureLabelsSeeded()
        let alpha = a.store.createBoard(name: "Alpha", emoji: "🅰️")
        a.store.setTheme(alpha, themeName: "ocean", customHex: "#ff8800")
        let alphaLists = alpha.sortedLists
        a.store.setCollapsed(alphaLists[1], true)
        let cardOne = a.store.addCard(to: alphaLists[0], title: "Card One")
        a.store.applyCardEdits(cardOne, title: "Card One", details: "line1\nline2",
                               labels: [.red, .blue], dueDate: Date(timeIntervalSince1970: 1_781_800_000))
        a.store.addCard(to: alphaLists[0], title: "Card Two")
        a.store.createBoard(name: "Beta", emoji: nil)

        let fixedExportedAt = Date(timeIntervalSince1970: 1_781_827_200)
        let aBoards = fetchBoards(a.context)
        let original = try ExportDocument.encode(ExportDocument.makeEnvelope(boards: aBoards, exportedAt: fixedExportedAt))

        // Container B: fresh, PALETTE SEEDED FIRST (TestContainer does not seed it; an unseeded B
        // would silently drop every label), import through the full production decode path.
        let b = TestContainer()
        defer { withExtendedLifetime(b) {} }
        b.store.ensureLabelsSeeded()
        try b.store.importBoards(try ExportDocument.decodeForImport(original))

        let bBoards = fetchBoards(b.context)
        let reExported = try ExportDocument.encode(ExportDocument.makeEnvelope(boards: bBoards, exportedAt: fixedExportedAt))
        #expect(reExported == original,
                "byte-stable round trip: positions, label order, dates, theme, collapse state all survive")
    }
}
