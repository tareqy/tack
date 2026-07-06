import Foundation
import SwiftUI
import UniformTypeIdentifiers

/// JSON export (E-01, PRD §4.6 / §9.6). A versioned, Codable DTO graph that mirrors the model
/// tree (boards → lists → cards, labels as color-name arrays) plus the machinery to encode it to a
/// stable, pretty-printed file and read it back.
///
/// PURE, READ-ONLY: `makeEnvelope` maps live models to value DTOs and touches neither `BoardStore`
/// nor the `ModelContext` — it only reads. The DTOs are `Equatable` so a full round trip
/// (encode → decode) is unit-testable without a `ModelContainer`. Encoding is deterministic
/// (`.sortedKeys` + `.prettyPrinted`, ISO-8601 dates), so the same data always produces byte-stable
/// output — the property the round-trip and ordering tests lean on.

// MARK: - DTO graph

/// The top-level export envelope. `formatVersion` lets a future importer (E-02, roadmap)
/// recognise the schema; `exportedAt` records when the file was produced.
struct ExportEnvelope: Codable, Equatable {
    var formatVersion: Int
    var exportedAt: Date
    var boards: [ExportBoard]
}

struct ExportBoard: Codable, Equatable {
    var name: String
    var emoji: String?
    var position: Int
    var themeName: String
    var customThemeHex: String?
    var createdAt: Date
    var lists: [ExportList]
}

struct ExportList: Codable, Equatable {
    var name: String
    var position: Int
    var isCollapsed: Bool
    var cards: [ExportCard]
}

struct ExportCard: Codable, Equatable {
    var title: String
    var details: String?
    var position: Int
    var dueDate: Date?
    var includesTime: Bool
    var createdAt: Date
    var updatedAt: Date
    /// Applied labels as `LabelColor` raw color names, in the fixed palette order
    /// (`LabelColor.allCases`) so the array is deterministic despite the model relationship being
    /// unordered.
    var labels: [String]
}

// MARK: - Mapping + coding

enum ExportDocument {
    /// The current export schema version. Bump only alongside an importer migration (E-02).
    static let formatVersion = 1

    /// Maps live boards (in position order) to the export envelope. Read-only. `@MainActor`
    /// because it reads SwiftData model properties. `exportedAt` is injectable for deterministic
    /// tests; production passes `.now`.
    @MainActor
    static func makeEnvelope(boards: [Board], exportedAt: Date = .now) -> ExportEnvelope {
        ExportEnvelope(
            formatVersion: formatVersion,
            exportedAt: exportedAt,
            boards: boards.sorted { $0.position < $1.position }.map(exportBoard)
        )
    }

    @MainActor
    private static func exportBoard(_ board: Board) -> ExportBoard {
        ExportBoard(
            name: board.name,
            emoji: board.emoji,
            position: board.position,
            themeName: board.themeName,
            customThemeHex: board.customThemeHex,
            createdAt: board.createdAt,
            lists: board.sortedLists.map(exportList)
        )
    }

    @MainActor
    private static func exportList(_ list: BoardList) -> ExportList {
        ExportList(
            name: list.name,
            position: list.position,
            isCollapsed: list.isCollapsed,
            cards: list.sortedCards.map(exportCard)
        )
    }

    @MainActor
    private static func exportCard(_ card: Card) -> ExportCard {
        let owned = Set(card.labels.compactMap(\.color))
        return ExportCard(
            title: card.title,
            details: card.details,
            position: card.position,
            dueDate: card.dueDate,
            includesTime: card.includesTime,
            createdAt: card.createdAt,
            updatedAt: card.updatedAt,
            labels: LabelColor.allCases.filter { owned.contains($0) }.map(\.rawValue)
        )
    }

    /// Deterministic encoding: sorted keys + pretty printing + ISO-8601 dates, so identical data
    /// always yields identical bytes.
    static func encode(_ envelope: ExportEnvelope) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(envelope)
    }

    static func decode(_ data: Data) throws -> ExportEnvelope {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(ExportEnvelope.self, from: data)
    }

    /// A dated, human-readable default filename ("Kanban Export 2026-07-06"). The `.json`
    /// extension is added by the exporter from the declared content type.
    static func suggestedFilename(date: Date = .now) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return "Kanban Export \(formatter.string(from: date))"
    }
}

// MARK: - FileDocument (drives SwiftUI `fileExporter`)

/// A minimal `FileDocument` wrapping already-encoded JSON bytes so `RootView`'s `.fileExporter`
/// can write them through the sandbox-friendly save panel (entitlement
/// `files.user-selected.read-write`). The document is built once, at the moment Export is invoked,
/// from `ExportDocument.encode`.
struct ExportJSONDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    let data: Data

    init(data: Data) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        // Import is roadmap (E-02); reading is only implemented so the type is a complete
        // `FileDocument`. Export never round-trips through this initializer.
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
