import Foundation

/// M-C: a board's view mode — the column canvas ("board"), the due-date-bucketed flat list
/// ("list"), or (M-D) the month-grid calendar ("calendar"). The raw values are WIRE FORMAT
/// twice over: they appear inside the persisted
/// UserDefaults string (the codec below) and as the `view-mode-value` accessibility marker's
/// exposed value — never rename them.
///
/// The whole per-board map persists as ONE `@AppStorage` string on `RootView` (mirroring the
/// `selectedBoardIDRaw` triad; key = `AppLaunchConfig.viewModeDefaultsKey`), so the codec here
/// is a pure, unit-tested String ↔ map bridge with no UserDefaults dependency of its own.
enum BoardViewMode: String {
    case board
    case list
    /// M-D: the month-grid Calendar View. Raw value "calendar" is wire format like its siblings
    /// (persisted defaults string + view-mode-value marker). Downgrade posture: the M-C decoder
    /// drops unknown modes silently (see `decode`), so a defaults string containing "calendar"
    /// read by an older build falls back to `.board` — tolerated by design, never a crash.
    case calendar

    /// Decodes "uuid=mode,uuid=mode" (any order) into the per-board map. Tolerant by design:
    /// malformed entries, bad UUIDs, and unknown modes are silently dropped (the
    /// `ThemeResolution` unknown-value posture) — the worst outcome of corrupt defaults is a
    /// board falling back to `.board`, never a crash. nil/empty raw → empty map.
    static func decode(_ raw: String?) -> [UUID: BoardViewMode] {
        guard let raw, !raw.isEmpty else { return [:] }
        var map: [UUID: BoardViewMode] = [:]
        for entry in raw.split(separator: ",") {
            let parts = entry.split(separator: "=", maxSplits: 1)
            guard parts.count == 2,
                  let id = UUID(uuidString: String(parts[0])),
                  let mode = BoardViewMode(rawValue: String(parts[1])) else { continue }
            map[id] = mode
        }
        return map
    }

    /// Canonical inverse: "uuid=mode" comma-joined, sorted by uuidString so equal maps always
    /// encode byte-identically (deterministic for tests, and `@AppStorage` writes are stable).
    static func encode(_ map: [UUID: BoardViewMode]) -> String {
        map.sorted { $0.key.uuidString < $1.key.uuidString }
            .map { "\($0.key.uuidString)=\($0.value.rawValue)" }
            .joined(separator: ",")
    }
}
