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
            formatVersion: 1, // deliberately v1: exercises the tolerant gate
            exportedAt: Date(timeIntervalSince1970: 1_781_827_200),
            boards: [
                ExportBoard(
                    name: "Imported A", emoji: "📦", about: "Imported note", position: 99, themeName: "ocean",
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
        #expect(boardA.about == "Imported note")
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

    @Test("M-E: import materializes checklist items in array order with positions 0..<n")
    func importMaterializesChecklistItems() throws {
        let env = TestContainer()
        env.store.ensureLabelsSeeded()
        var card = ExportCard(title: "C", details: nil, position: 0, dueDate: nil,
                              includesTime: false, createdAt: .now, updatedAt: .now, labels: [])
        card.checklist = [ExportChecklistItem(text: "One", isDone: true),
                          ExportChecklistItem(text: "Two", isDone: false)]
        let envelope = ExportEnvelope(formatVersion: 4, exportedAt: .now, boards: [
            ExportBoard(name: "B", emoji: nil, position: 0, themeName: "default",
                        customThemeHex: nil, createdAt: .now,
                        lists: [ExportList(name: "L", position: 0, isCollapsed: false, cards: [card])]),
        ])

        let imported = try env.store.importBoards(envelope)

        let items = imported[0].sortedLists[0].sortedCards[0].sortedChecklistItems
        #expect(items.map(\.text) == ["One", "Two"])
        #expect(items.map(\.isDone) == [true, false])
        #expect(items.map(\.position) == [0, 1])
    }

    // MARK: - Byte-equality round trip (Task 4; the strongest cheap oracle)

    @Test("export → import into a fresh store → re-export reproduces the original bytes")
    func byteEqualityRoundTrip() throws {
        // Container A: seed via store ops, exercising EVERY format field — emoji, about, theme +
        // custom hex, a collapsed list, details, multiple labels, a due date (includesTime false),
        // a timed card + duration.
        let a = TestContainer()
        defer { withExtendedLifetime(a) {} }
        a.store.ensureLabelsSeeded()
        let alpha = a.store.createBoard(name: "Alpha", emoji: "🅰️", about: "Weekly notes")
        a.store.setTheme(alpha, themeName: "ocean", customHex: "#ff8800")
        let alphaLists = alpha.sortedLists
        a.store.setCollapsed(alphaLists[1], true)
        let cardOne = a.store.addCard(to: alphaLists[0], title: "Card One")
        a.store.applyCardEdits(cardOne, title: "Card One", details: "line1\nline2",
                               labels: [.red, .blue], dueDate: Date(timeIntervalSince1970: 1_781_800_000),
                               includesTime: false, durationMinutes: nil, checklist: [])
        let cardTwo = a.store.addCard(to: alphaLists[0], title: "Card Two")
        // M-B: a timed card with a duration — includesTime true skips startOfDay normalization,
        // so the raw whole-second epoch survives ISO-8601 byte-stably.
        a.store.setDueDate(Date(timeIntervalSince1970: 1_781_803_800), on: cardTwo,
                           includesTime: true, durationMinutes: 90)
        a.store.createBoard(name: "Beta", emoji: nil)

        let fixedExportedAt = Date(timeIntervalSince1970: 1_781_827_200)
        let aBoards = fetchBoards(a.context)
        let aAreas = ((try? a.context.fetch(FetchDescriptor<Area>(sortBy: [SortDescriptor(\.position)]))) ?? [])
        let original = try ExportDocument.encode(ExportDocument.makeEnvelope(boards: aBoards, areas: aAreas, exportedAt: fixedExportedAt))

        // Container B: fresh, PALETTE SEEDED FIRST (TestContainer does not seed it; an unseeded B
        // would silently drop every label), import through the full production decode path.
        let b = TestContainer()
        defer { withExtendedLifetime(b) {} }
        b.store.ensureLabelsSeeded()
        try b.store.importBoards(try ExportDocument.decodeForImport(original))

        let bBoards = fetchBoards(b.context)
        let bAreas = ((try? b.context.fetch(FetchDescriptor<Area>(sortBy: [SortDescriptor(\.position)]))) ?? [])
        let reExported = try ExportDocument.encode(ExportDocument.makeEnvelope(boards: bBoards, areas: bAreas, exportedAt: fixedExportedAt))
        #expect(reExported == original,
                "byte-stable round trip: positions, label order, dates, theme, collapse state all survive")
    }

    // MARK: - Area merge (M-F)

    @Test("M-F: import merges areas by exact name — existing row reused keeping LOCAL collapse; missing row created with the envelope's flag")
    func importMergesAreasByExactNameFindOrCreate() throws {
        let env = TestContainer()
        env.store.ensureLabelsSeeded()
        let local = try #require(env.store.createArea(named: "Home", moving: nil))
        env.store.setAreaCollapsed(local, true)
        let localPID = local.persistentModelID

        var boardA = ExportBoard(name: "A", emoji: nil, position: 0, themeName: "default",
                                 customThemeHex: nil, createdAt: .now, lists: [])
        boardA.area = "Home"
        var boardB = ExportBoard(name: "B", emoji: nil, position: 1, themeName: "default",
                                 customThemeHex: nil, createdAt: .now, lists: [])
        boardB.area = "New"
        var envelope = ExportEnvelope(formatVersion: 5, exportedAt: .now, boards: [boardA, boardB])
        envelope.areas = [ExportArea(name: "Home", isCollapsed: false),
                          ExportArea(name: "New", isCollapsed: true)]

        let imported = try env.store.importBoards(envelope)

        let areas = env.store.fetchAreasForTesting().sorted { $0.position < $1.position }
        #expect(areas.map(\.name) == ["Home", "New"], "one Home row — merged, not duplicated")
        #expect(areas[0].persistentModelID == localPID, "the EXISTING row is reused (find, not create)")
        #expect(areas[0].isCollapsed == true, "local collapse state wins on merge")
        #expect(areas[1].isCollapsed == true, "created areas take the envelope's flag")
        #expect(areas[1].position == 1, "created areas append after the existing max")
        #expect(imported[0].area?.persistentModelID == localPID)
        #expect(imported[1].area?.persistentModelID == areas[1].persistentModelID)
    }

    @Test("M-F: area merge is case-sensitive — 'home' does not merge into 'Home'")
    func importCaseSensitiveAreaMerge() throws {
        let env = TestContainer()
        env.store.ensureLabelsSeeded()
        _ = try #require(env.store.createArea(named: "Home", moving: nil))

        var board = ExportBoard(name: "A", emoji: nil, position: 0, themeName: "default",
                                customThemeHex: nil, createdAt: .now, lists: [])
        board.area = "home"
        var envelope = ExportEnvelope(formatVersion: 5, exportedAt: .now, boards: [board])
        envelope.areas = [ExportArea(name: "home", isCollapsed: false)]

        _ = try env.store.importBoards(envelope)

        #expect(env.store.fetchAreasForTesting().count == 2,
                "the merge key is exact and case-sensitive — the createArea decision, pinned end-to-end")
    }

    @Test("M-F: a dangling board.area ref (absent from areas[]) still creates its area")
    func danglingAreaRefCreatesArea() throws {
        let env = TestContainer()
        env.store.ensureLabelsSeeded()
        var board = ExportBoard(name: "A", emoji: nil, position: 0, themeName: "default",
                                customThemeHex: nil, createdAt: .now, lists: [])
        board.area = "Ghost"
        let envelope = ExportEnvelope(formatVersion: 5, exportedAt: .now, boards: [board])

        let imported = try env.store.importBoards(envelope)

        let areas = env.store.fetchAreasForTesting()
        #expect(areas.map(\.name) == ["Ghost"])
        #expect(areas.first?.isCollapsed == false, "a synthesized area defaults expanded")
        #expect(imported[0].area?.name == "Ghost")
    }

    @Test("M-F review fix: import tolerates two Areas that share the exact same name (convention violated directly, not via createArea)")
    func importToleratesConventionViolatingDuplicateAreaNames() throws {
        let env = TestContainer()
        env.store.ensureLabelsSeeded()
        // Area.name has NO schema-level uniqueness — it's a convention enforced only by
        // createArea's find-or-create. Insert two same-named rows DIRECTLY, bypassing that
        // convention, which is the only way to violate it.
        let first = Area(name: "Home", position: 0, isCollapsed: false)
        let second = Area(name: "Home", position: 1, isCollapsed: true)
        env.context.insert(first)
        env.context.insert(second)
        try env.context.save()
        // resolveArea's dictionary is first-wins over whatever ORDER fetchAreas() returns — and
        // that fetch carries no sort descriptor, so it is not guaranteed to match insertion or
        // position order (confirmed: this flipped between an isolated run and deep into the full
        // suite). Pin against the actual fetch-order winner, not an assumed one.
        let winnerPID = try #require(env.store.fetchAreasForTesting().first { $0.name == "Home" }).persistentModelID

        var board = ExportBoard(name: "A", emoji: nil, position: 0, themeName: "default",
                                customThemeHex: nil, createdAt: .now, lists: [])
        board.area = "Home"
        let envelope = ExportEnvelope(formatVersion: 5, exportedAt: .now, boards: [board])

        let imported = try env.store.importBoards(envelope)

        #expect(imported[0].area?.persistentModelID == winnerPID,
                "first-wins matches the import sanitizer's dedupe-keep-first posture")
        #expect(env.store.fetchAreasForTesting().count == 2, "no third Area created for the duplicate name")
    }

    @Test("M-F: Replace All deletes every existing area — none stranded, even empty ones")
    func replaceAllWipesAreas() throws {
        let env = TestContainer()
        env.store.ensureLabelsSeeded()
        let board = env.store.createBoard(name: "Old", emoji: nil)
        _ = try #require(env.store.createArea(named: "Occupied", moving: board))
        _ = try #require(env.store.createArea(named: "Empty", moving: nil))

        let envelope = ExportEnvelope(
            formatVersion: 5, exportedAt: .now,
            boards: [ExportBoard(name: "Fresh", emoji: nil, position: 0, themeName: "default",
                                 customThemeHex: nil, createdAt: .now, lists: [])])
        _ = try env.store.replaceAllBoards(with: envelope)

        #expect(env.store.fetchAreasForTesting().isEmpty,
                "restore-the-backup-exactly: the backup had no areas, so neither does the store")
        let boards = (try? env.context.fetch(FetchDescriptor<Board>())) ?? []
        #expect(boards.map(\.name) == ["Fresh"])
    }
}
