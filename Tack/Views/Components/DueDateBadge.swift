import SwiftUI

/// A capsule showing a card's due date as a short "Jul 12" string, colored by urgency (PRD §4.5 /
/// D-03), on the card face. Callers gate presence themselves (hidden entirely when the card has no
/// due date — PRD v1.1: no badge at all in that case, so this view always assumes a non-nil
/// `dueDate`).
///
/// M6 computed the classification via `DueDateStatus.classify` and switched on every case already;
/// M10 adds the actual urgency colors via the pure `DueDateBadgeStyle.role(for:)` helper (unit
/// tested in isolation — see `DueDateBadgeStyleTests`) plus its `BadgeRole` → `Color` extension
/// (`DueDateBadgeStyle+Color.swift`, SwiftUI-flavored so it stays out of the pure/testable helper).
///
/// M-B feeds the card's time state into `classify` (a timed card goes overdue the moment its slot
/// ends) and extends BOTH representations for TIMED cards only: visible "Jul 12, 2:00 PM", a11y
/// "<isoFullDate>T<HH:mm>|<status>". Date-only cards keep the exact M10 forms — the a11y value is
/// pinned byte-for-byte by CardDetailUITests.testDueDateQuickOptionAndClear, and `|status` stays
/// the LAST segment either way (BadgeUITests asserts by suffix).
struct DueDateBadge: View {
    let card: Card
    let dueDate: Date

    private var status: DueDateStatus {
        DueDateStatus.classify(dueDate: dueDate, includesTime: card.includesTime,
                               durationMinutes: card.durationMinutes, now: .now, calendar: .current)
    }

    private var role: BadgeRole {
        DueDateBadgeStyle.role(for: status)
    }

    var body: some View {
        Text(visibleText)
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(role.backgroundColor, in: Capsule())
            .foregroundStyle(role.foregroundColor)
            // NOT `.accessibilityElement(children:.ignore)` + `.accessibilityValue`: that shape
            // was verified EMPTY under XCUITest on macOS (an `Other` element with no label and no
            // value — see the M6 report's diagnostic dump). A representation Text makes this a
            // StaticText whose text is machine-readable, which XCUITest reliably surfaces; the
            // visible capsule keeps the human "Jul 12" form.
            //
            // M10 extends the exposed value from a bare ISO date to "<iso>|<status>" (e.g.
            // "2026-07-07|tomorrow") so e2e tests can assert urgency SEMANTICS (which bucket a date
            // landed in) without resorting to pixel/color inspection — colors stay verified by
            // screenshot inspection instead (see the task-12 report's audit table).
            .accessibilityRepresentation {
                Text("\(wireDateValue)|\(Self.wireValue(for: status))")
                    .accessibilityIdentifier(AccessibilityID.dueDateBadge(card: card.title))
            }
    }

    /// "Jul 12" for date-only cards (unchanged); "Jul 12, 2:00 PM" for timed cards (M-B).
    private var visibleText: String {
        let day = Self.shortDateFormatter.string(from: dueDate)
        guard card.includesTime else { return day }
        return "\(day), \(Self.shortTimeFormatter.string(from: dueDate))"
    }

    /// The date leg of the a11y value: "<isoFullDate>" for date-only cards — EXACTLY the M10
    /// form — and "<isoFullDate>T<HH:mm>" for timed cards.
    private var wireDateValue: String {
        let iso = Self.isoDateFormatter.string(from: dueDate)
        guard card.includesTime else { return iso }
        return "\(iso)T\(Self.wireTimeFormatter.string(from: dueDate))"
    }

    /// The machine-readable status suffix for the a11y value — deliberately separate from
    /// `BadgeRole` (whose case names describe VISUAL weight — alert/warn/notice — not the
    /// underlying due-date bucket), so tests assert against the same vocabulary
    /// `DueDateStatus`/the PRD already use (overdue/today/tomorrow/upcoming).
    private static func wireValue(for status: DueDateStatus) -> String {
        switch status {
        case .none: "none"
        case .overdue: "overdue"
        case .today: "today"
        case .tomorrow: "tomorrow"
        case .upcoming: "upcoming"
        }
    }

    private static let shortDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter
    }()

    /// Locale-appropriate short time for the VISIBLE capsule ("2:00 PM" or "14:00" per locale).
    private static let shortTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()

    /// Machine-readable 24-hour "HH:mm" for the a11y value. POSIX-pinned: without it, the user's
    /// 12/24-hour system preference can rewrite even an explicit dateFormat (HH → hh), which
    /// would flake the e2e "T09:00" assertion per-host. Local time zone, matching
    /// `isoDateFormatter`'s explicitly-local rationale.
    private static let wireTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm"
        formatter.timeZone = .current
        return formatter
    }()

    private static let isoDateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        // Explicitly LOCAL, not the type's UTC default: dueDate is stored as LOCAL start-of-day,
        // and formatting local midnight in UTC would print the PREVIOUS day for any timezone east
        // of UTC. Tests compute their expected string with the same local full-date settings.
        formatter.timeZone = .current
        return formatter
    }()
}
