import Testing
import Foundation
@testable import Tack

/// E-02 pure codec leg: decode + formatVersion gate + gray-zone sanitization. No ModelContainer.
@Suite("ExportDocument.decodeForImport")
struct ImportDecodeTests {

    /// A UTC-pinned calendar so start-of-day assertions are deterministic regardless of the
    /// machine's time zone (the production default `Calendar.current` is injectable by design).
    private var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func json(_ boards: String, formatVersion: Int = 1) -> Data {
        Data("""
        {"boards":[\(boards)],"exportedAt":"2026-07-08T00:00:00Z","formatVersion":\(formatVersion)}
        """.utf8)
    }

    private func cardJSON(labels: String = "[]", dueDate: String? = nil, includesTime: Bool = false,
                          durationMinutes: Int? = nil) -> String {
        let due = dueDate.map { "\"dueDate\":\"\($0)\"," } ?? ""
        let duration = durationMinutes.map { "\"durationMinutes\":\($0)," } ?? ""
        return """
        {"createdAt":"2026-01-01T00:00:00Z","details":null,\(due)\(duration)"includesTime":\(includesTime),
         "labels":\(labels),"position":0,"title":"C","updatedAt":"2026-01-01T00:00:00Z"}
        """
    }

    private func boardJSON(cards: String, customThemeHex: String = "null") -> String {
        """
        {"createdAt":"2026-01-01T00:00:00Z","customThemeHex":\(customThemeHex),"lists":[
          {"cards":[\(cards)],"isCollapsed":false,"name":"L","position":0}
        ],"name":"B","position":0,"themeName":"default"}
        """
    }

    // MARK: - Hard rejects

    @Test("malformed JSON throws .unreadable")
    func malformedJSONUnreadable() {
        #expect(throws: ImportError.self) {
            try ExportDocument.decodeForImport(Data("not json {".utf8))
        }
        do { _ = try ExportDocument.decodeForImport(Data("not json {".utf8)) }
        catch let error as ImportError { #expect(error.caseName == "unreadable") }
        catch { Issue.record("expected ImportError, got \(error)") }
    }

    @Test("a missing required field (board without name) throws .unreadable")
    func missingRequiredFieldUnreadable() {
        let noName = json("""
        {"createdAt":"2026-01-01T00:00:00Z","lists":[],"position":0,"themeName":"default"}
        """)
        do { _ = try ExportDocument.decodeForImport(noName) }
        catch let error as ImportError { #expect(error.caseName == "unreadable") }
        catch { Issue.record("expected ImportError, got \(error)") }
    }

    @Test("missing formatVersion key throws .unreadable")
    func missingVersionKeyUnreadable() {
        let data = Data(#"{"boards":[],"exportedAt":"2026-07-08T00:00:00Z"}"#.utf8)
        do { _ = try ExportDocument.decodeForImport(data) }
        catch let error as ImportError { #expect(error.caseName == "unreadable") }
        catch { Issue.record("expected ImportError, got \(error)") }
    }

    @Test("formatVersion 4 and 0 throw .unsupportedVersion carrying the file's version")
    func versionGate() {
        for version in [4, 0] {
            do { _ = try ExportDocument.decodeForImport(json("", formatVersion: version)) }
            catch let error as ImportError { #expect(error == .unsupportedVersion(version)) }
            catch { Issue.record("expected ImportError, got \(error)") }
        }
    }

    @Test("a version-1 file (no `about` key) still imports; about decodes nil")
    func v1FileStillImports() throws {
        // A version-1 file (no `about` keys) must decode under the tolerant gate with about == nil.
        let data = json(boardJSON(cards: ""), formatVersion: 1)
        let envelope = try ExportDocument.decodeForImport(data)
        #expect(envelope.formatVersion == 1)
        #expect(envelope.boards.first?.about == nil)
    }

    @Test("a version-2 file (no durationMinutes key) still imports; duration decodes nil")
    func v2FileStillImports() throws {
        let data = json(boardJSON(cards: cardJSON(dueDate: "2026-07-08T15:30:00Z", includesTime: true)),
                        formatVersion: 2)
        let envelope = try ExportDocument.decodeForImport(data)
        #expect(envelope.formatVersion == 2)
        #expect(envelope.boards[0].lists[0].cards[0].durationMinutes == nil)
    }

    @Test("fractional-second ISO dates throw .unreadable (Foundation .iso8601 rejects them)")
    func fractionalSecondsUnreadable() {
        let data = json(boardJSON(cards: cardJSON(dueDate: "2026-07-08T10:00:00.123Z")))
        do { _ = try ExportDocument.decodeForImport(data) }
        catch let error as ImportError { #expect(error.caseName == "unreadable") }
        catch { Issue.record("expected ImportError, got \(error)") }
    }

    // MARK: - Valid decodes

    @Test("a zero-board envelope decodes successfully")
    func emptyEnvelopeDecodes() throws {
        let envelope = try ExportDocument.decodeForImport(json(""))
        #expect(envelope.boards.isEmpty)
        #expect(envelope.formatVersion == 1)
    }

    // MARK: - Gray-zone sanitization

    @Test("unknown label names are dropped; known ones kept")
    func unknownLabelsDropped() throws {
        let envelope = try ExportDocument.decodeForImport(
            json(boardJSON(cards: cardJSON(labels: #"["green","neon"]"#))))
        #expect(envelope.boards[0].lists[0].cards[0].labels == ["green"])
    }

    @Test("duplicate labels are deduped and reordered to palette order")
    func labelsDedupedAndPaletteOrdered() throws {
        let envelope = try ExportDocument.decodeForImport(
            json(boardJSON(cards: cardJSON(labels: #"["blue","red","blue"]"#))))
        #expect(envelope.boards[0].lists[0].cards[0].labels == ["red", "blue"],
                "LabelColor.allCases order: red before blue, duplicates collapsed")
    }

    @Test("dueDate is normalized to the calendar's start of day when includesTime is false")
    func dueDateNormalizedWhenDateOnly() throws {
        let envelope = try ExportDocument.decodeForImport(
            json(boardJSON(cards: cardJSON(dueDate: "2026-07-08T15:30:00Z"))), calendar: utcCalendar)
        let expected = ISO8601DateFormatter().date(from: "2026-07-08T00:00:00Z")!
        #expect(envelope.boards[0].lists[0].cards[0].dueDate == expected)
    }

    @Test("dueDate is untouched when includesTime is true")
    func dueDateUntouchedWhenIncludesTime() throws {
        let envelope = try ExportDocument.decodeForImport(
            json(boardJSON(cards: cardJSON(dueDate: "2026-07-08T15:30:00Z", includesTime: true))),
            calendar: utcCalendar)
        let expected = ISO8601DateFormatter().date(from: "2026-07-08T15:30:00Z")!
        #expect(envelope.boards[0].lists[0].cards[0].dueDate == expected)
    }

    @Test("durationMinutes is nilled when the card is date-only")
    func durationNilledWhenDateOnly() throws {
        let envelope = try ExportDocument.decodeForImport(
            json(boardJSON(cards: cardJSON(dueDate: "2026-07-08T15:30:00Z", includesTime: false,
                                           durationMinutes: 60))), calendar: utcCalendar)
        #expect(envelope.boards[0].lists[0].cards[0].durationMinutes == nil)
    }

    @Test("non-positive durationMinutes is nilled; a positive timed duration passes through")
    func durationClampedWhenNonPositive() throws {
        for bad in [0, -15] {
            let envelope = try ExportDocument.decodeForImport(
                json(boardJSON(cards: cardJSON(dueDate: "2026-07-08T15:30:00Z", includesTime: true,
                                               durationMinutes: bad))), calendar: utcCalendar)
            #expect(envelope.boards[0].lists[0].cards[0].durationMinutes == nil)
        }
        let kept = try ExportDocument.decodeForImport(
            json(boardJSON(cards: cardJSON(dueDate: "2026-07-08T15:30:00Z", includesTime: true,
                                           durationMinutes: 45))), calendar: utcCalendar)
        #expect(kept.boards[0].lists[0].cards[0].durationMinutes == 45)
    }

    @Test("customThemeHex is canonicalized ('#ff0000' → 'FF0000'); garbage becomes nil")
    func hexCanonicalized() throws {
        let canonical = try ExportDocument.decodeForImport(
            json(boardJSON(cards: cardJSON(), customThemeHex: "\"#ff0000\"")))
        #expect(canonical.boards[0].customThemeHex == "FF0000")

        let garbage = try ExportDocument.decodeForImport(
            json(boardJSON(cards: cardJSON(), customThemeHex: "\"nothex\"")))
        #expect(garbage.boards[0].customThemeHex == nil)
    }

    @Test("themeName and position fields pass through unrewritten")
    func themeAndPositionsUntouched() throws {
        let data = json("""
        {"createdAt":"2026-01-01T00:00:00Z","lists":[],"name":"B","position":42,
         "themeName":"definitely-not-a-preset"}
        """)
        let envelope = try ExportDocument.decodeForImport(data)
        #expect(envelope.boards[0].themeName == "definitely-not-a-preset",
                "unknown themes resolve at render (ThemeResolution.resolve → .default); not sanitize's job")
        #expect(envelope.boards[0].position == 42,
                "DTO positions are never read by the materializer — rewriting them would be dead code")
    }

    @Test("sanitization is idempotent: decode(encode(decoded)) == decoded")
    func sanitizeIdempotent() throws {
        let data = json(boardJSON(cards: cardJSON(labels: #"["blue","red","neon"]"#,
                                                  dueDate: "2026-07-08T15:30:00Z") + "," +
                                         cardJSON(dueDate: "2026-07-08T15:30:00Z",
                                                  includesTime: true, durationMinutes: 45),
                          customThemeHex: "\"#ff0000\""))
        let once = try ExportDocument.decodeForImport(data, calendar: utcCalendar)
        let twice = try ExportDocument.decodeForImport(try ExportDocument.encode(once), calendar: utcCalendar)
        #expect(once == twice)
    }
}
