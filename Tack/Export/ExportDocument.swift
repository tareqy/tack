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
    // OPTIONAL, defaulted nil — NOT a defaulted non-optional array: synthesized Codable throws
    // keyNotFound on a missing key for a non-optional array (property defaults don't apply to
    // decoding — the ExportCard.checklist finding, verbatim), so this is the ONLY shape that
    // lets every v1–v4 file decode. The exporter always writes the key (empty array when no
    // areas exist, keeping encoding deterministic); importers read `areas ?? []`.
    var areas: [ExportArea]? = nil
}

struct ExportBoard: Codable, Equatable {
    var name: String
    var emoji: String?
    // Defaulted (unlike `emoji`) so pre-v2 call sites that predate this field keep compiling;
    // decoding is unaffected either way — a missing JSON key always decodes an Optional as nil.
    var about: String? = nil
    // M-F: the containing area's name — the import merge key (exact, trimmed), nil = ungrouped.
    // Optional (the `about` shape): the key is omitted for ungrouped boards and a missing key
    // decodes nil, so v1–v4 files and area-less boards are indistinguishable, correctly.
    var area: String? = nil
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
    // Defaulted (the ExportBoard.about precedent) so out-of-scope ExportCard(...) construction
    // sites keep compiling; a missing JSON key always decodes an Optional as nil, so v1/v2
    // files import with no duration.
    var durationMinutes: Int? = nil
    // OPTIONAL, defaulted nil — NOT a defaulted non-optional array: synthesized Codable throws
    // keyNotFound on a missing key for a non-optional array (property defaults don't apply to
    // decoding), so the about/durationMinutes optional shape is the ONLY one that lets v1–v3
    // files decode. The exporter always writes the key (empty array when the card has no items,
    // keeping encoding deterministic); importers read `checklist ?? []`.
    var checklist: [ExportChecklistItem]? = nil
    var createdAt: Date
    var updatedAt: Date
    /// Applied labels as `LabelColor` raw color names, in the fixed palette order
    /// (`LabelColor.allCases`) so the array is deterministic despite the model relationship being
    /// unordered.
    var labels: [String]
}

/// M-E: one exported checklist row. Order in the array IS the order (positions are synthesized
/// from enumeration at materialize time, like every other position in the format).
struct ExportChecklistItem: Codable, Equatable {
    var text: String
    var isDone: Bool
}

/// M-F: one exported sidebar area. Array order IS the area order (positions are synthesized
/// from enumeration at materialize time, like every other position in the format); membership
/// travels on each board's `area` name reference, not as a name list here.
struct ExportArea: Codable, Equatable {
    var name: String
    var isCollapsed: Bool
}

// MARK: - Mapping + coding

enum ExportDocument {
    /// The current export schema version. Bump only alongside an importer migration (E-02).
    /// v2 (M-A): + ExportBoard.about. The import gate accepts 1...formatVersion; older files
    /// decode missing fields as nil.
    /// v3 (M-B): + ExportCard.durationMinutes; includesTime is now user-settable.
    /// v4 (M-E): + ExportCard.checklist (Action Items; array order is the row order).
    /// v5 (M-F): + top-level areas[] (sidebar groups; array order = area order) + ExportBoard.area
    /// (merge-by-exact-trimmed-name reference).
    static let formatVersion = 5

    /// Maps live boards (in position order) and areas (in position order) to the export envelope.
    /// Read-only. `@MainActor` because it reads SwiftData model properties. `exportedAt` is
    /// injectable for deterministic tests; production passes `.now`. `areas:` is deliberately NOT
    /// defaulted — a defaulted `[]` would let a call site silently export area-less backups.
    @MainActor
    static func makeEnvelope(boards: [Board], areas: [Area], exportedAt: Date = .now) -> ExportEnvelope {
        ExportEnvelope(
            formatVersion: formatVersion,
            exportedAt: exportedAt,
            boards: boards.sorted { $0.position < $1.position }.map(exportBoard),
            areas: areas.sorted { $0.position < $1.position }
                .map { ExportArea(name: $0.name, isCollapsed: $0.isCollapsed) }
        )
    }

    @MainActor
    private static func exportBoard(_ board: Board) -> ExportBoard {
        ExportBoard(
            name: board.name,
            emoji: board.emoji,
            about: board.about,
            area: board.area?.name,
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
            durationMinutes: card.durationMinutes,
            checklist: card.sortedChecklistItems.map { ExportChecklistItem(text: $0.text, isDone: $0.isDone) },
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

    /// E-02 import: decode → explicit `formatVersion` gate (plain `decode` ignores it) → pure
    /// gray-zone sanitization (spec: hard-reject only structural failure; sanitize the rest).
    /// `calendar` is injectable so the start-of-day rule is table-testable under a pinned time
    /// zone; production uses `.current`. Idempotent: re-running on its own output is the identity
    /// (pinned by ImportDecodeTests).
    static func decodeForImport(_ data: Data, calendar: Calendar = .current) throws -> ExportEnvelope {
        let envelope: ExportEnvelope
        do {
            envelope = try decode(data)
        } catch {
            throw ImportError.unreadable(detail: String(describing: error))
        }
        guard (1...formatVersion).contains(envelope.formatVersion) else {
            throw ImportError.unsupportedVersion(envelope.formatVersion)
        }
        return sanitized(envelope, calendar: calendar)
    }

    /// Gray-zone sanitization (all pure, all idempotent):
    ///   - card labels filtered to known `LabelColor` rawValues, deduped, reordered to palette order;
    ///   - `dueDate` → `calendar.startOfDay` when `includesTime == false` (the Card invariant);
    ///   - `durationMinutes` → nil unless includesTime && > 0 (the Card invariant M-B adds);
    ///   - `customThemeHex` canonicalized via HexColor parse→format, or nil when unparsable (the
    ///     store's "never persists unparsable hex" invariant).
    /// Deliberately NOT rewritten: `themeName` (unknowns resolve to `.default` at render — that IS
    /// the fallback) and every `position` field (the materializer never reads them).
    private static func sanitized(_ envelope: ExportEnvelope, calendar: Calendar) -> ExportEnvelope {
        var result = envelope
        result.boards = envelope.boards.map { board in
            var board = board
            board.customThemeHex = board.customThemeHex
                .flatMap(HexColor.parse)
                .map { HexColor.format(r: $0.r, g: $0.g, b: $0.b) }
            // M-F: the board's area ref is trimmed to the merge key; whitespace-only → nil.
            // A dangling ref (no matching areas[] row) is KEPT — materialize find-or-creates it.
            board.area = board.area
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .flatMap { $0.isEmpty ? nil : $0 }
            board.lists = board.lists.map { list in
                var list = list
                list.cards = list.cards.map { card in
                    var card = card
                    let owned = Set(card.labels.compactMap(LabelColor.init(rawValue:)))
                    card.labels = LabelColor.allCases.filter { owned.contains($0) }.map(\.rawValue)
                    if let dueDate = card.dueDate, !card.includesTime {
                        card.dueDate = calendar.startOfDay(for: dueDate)
                    }
                    if !card.includesTime || (card.durationMinutes ?? 0) <= 0 {
                        card.durationMinutes = nil
                    }
                    // M-E: drop whitespace-only checklist items, keep order, pass text through
                    // verbatim (the labels-filter posture); nil stays nil (idempotent — a v≤3
                    // file's absent checklist is not rewritten into an empty one).
                    card.checklist = card.checklist.map { items in
                        items.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                    }
                    return card
                }
                return list
            }
            return board
        }
        // M-F area hygiene (pure, idempotent): names trimmed; whitespace-only areas dropped;
        // duplicates (by the exact trimmed merge key) deduped keeping the FIRST occurrence —
        // merge-by-name needs one row per key. nil stays nil (a v≤4 file's absent areas are
        // not rewritten into an empty array — idempotence).
        result.areas = envelope.areas.map { areas in
            var seen = Set<String>()
            return areas.compactMap { area -> ExportArea? in
                var area = area
                area.name = area.name.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !area.name.isEmpty, seen.insert(area.name).inserted else { return nil }
                return area
            }
        }
        return result
    }

    /// A dated, human-readable default filename ("Tack Export 2026-07-06"). The `.json`
    /// extension is added by the exporter from the declared content type.
    static func suggestedFilename(date: Date = .now) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return "Tack Export \(formatter.string(from: date))"
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
        // E-02 shipped via URL-based `.fileImporter` (see RootView.handlePickedImportFile), so this
        // ReadConfiguration path remains unused by design; it exists only so the type is a complete
        // FileDocument. Export never round-trips through this initializer.
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

// MARK: - Import errors (E-02)

/// Every failure the import surface can produce — file-read/decode failures, the version gate, the
/// empty-replace guard, and save failures wrapped at the store boundary — so RootView's alert and
/// the e2e marker only ever handle `ImportError` (no generic-`Error` path exists).
enum ImportError: Error, Equatable, LocalizedError {
    /// File-read failure (missing/unreadable file — wrapped by the read step in both the
    /// fileImporter completion and the launch hook), malformed JSON, a missing required field, or
    /// an undecodable date (Foundation's `.iso8601` rejects fractional seconds).
    case unreadable(detail: String)
    /// `formatVersion` outside `1...ExportDocument.formatVersion` (older versions import
    /// tolerantly; only unknown NEWER versions reject).
    case unsupportedVersion(Int)
    /// Replace-all requested with a zero-board envelope. The mode dialog omits the Replace button
    /// for empty backups; this is the store-level backstop (and what the test hook publishes if a
    /// test forces the combination).
    case emptyReplace
    /// `context.save()` threw during import; wrapped after rollback — nothing was persisted.
    case saveFailed(detail: String)

    var errorDescription: String? {
        switch self {
        case .unreadable:
            return "This file couldn't be read as a Tack export. It may be damaged or not a Tack export file."
        case .unsupportedVersion(let version):
            return "This file uses export format version \(version). This version of Tack can import versions 1 through \(ExportDocument.formatVersion)."
        case .emptyReplace:
            return "This backup contains no boards, so it can't replace your existing boards."
        case .saveFailed(let detail):
            return "Tack couldn't save the imported boards. \(detail)"
        }
    }

    /// Second alert line. Truthful because import is single-save atomic (rollback on failure).
    var recoverySuggestion: String? {
        "Nothing was imported. Your existing boards are unchanged."
    }

    /// Stable machine token for the e2e marker ("error|<caseName>") — never localized copy.
    var caseName: String {
        switch self {
        case .unreadable: "unreadable"
        case .unsupportedVersion: "unsupportedVersion"
        case .emptyReplace: "emptyReplace"
        case .saveFailed: "saveFailed"
        }
    }
}
