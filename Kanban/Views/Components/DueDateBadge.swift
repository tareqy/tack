import SwiftUI

/// Neutral gray capsule showing a card's due date as a short "Jul 12" string, on the card face.
/// Callers gate presence themselves (hidden entirely when the card has no due date — PRD v1.1: no
/// badge at all in that case, so this view always assumes a non-nil `dueDate`).
///
/// M10 will color this by urgency. M6 computes the classification via `DueDateStatus.classify` and
/// switches on every case already (so M10 only has to change the returned colors), but every case
/// maps to the SAME neutral style for now.
struct DueDateBadge: View {
    let card: Card
    let dueDate: Date

    private var status: DueDateStatus {
        DueDateStatus.classify(dueDate: dueDate, now: .now, calendar: .current)
    }

    /// All neutral today (M6); the exhaustive switch is the hook M10 recolors.
    private var backgroundColor: Color {
        switch status {
        case .none, .overdue, .today, .tomorrow, .upcoming:
            Color.secondary.opacity(0.2)
        }
    }

    var body: some View {
        Text(Self.shortDateFormatter.string(from: dueDate))
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(backgroundColor, in: Capsule())
            .foregroundStyle(.secondary)
            // NOT `.accessibilityElement(children:.ignore)` + `.accessibilityValue`: that shape
            // was verified EMPTY under XCUITest on macOS (an `Other` element with no label and no
            // value — see the M6 report's diagnostic dump). A representation Text makes this a
            // StaticText whose text is the machine-readable ISO date, which XCUITest reliably
            // surfaces; the visible capsule keeps the human "Jul 12" form.
            .accessibilityRepresentation {
                Text(Self.isoDateFormatter.string(from: dueDate))
                    .accessibilityIdentifier(AccessibilityID.dueDateBadge(card: card.title))
            }
    }

    private static let shortDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
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
