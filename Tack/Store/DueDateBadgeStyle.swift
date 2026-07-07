/// Urgency "role" a due-date badge should render with (PRD §4.5 / D-03) — a pure projection of
/// `DueDateStatus`, kept in exactly the same SwiftUI/SwiftData-free style as that type (no imports
/// at all here) so the status→role mapping is unit-testable without spinning up any view.
/// `Views/Components/DueDateBadgeStyle+Color.swift` is the SwiftUI-flavored extension that maps
/// each role onto concrete colors for `DueDateBadge` — the same "pure model here, `Color` extension
/// in Views/" split `LabelColor`/`LabelColor+Swatch` already establishes.
enum BadgeRole: Hashable {
    /// Overdue — red.
    case alert
    /// Due today — orange.
    case warn
    /// Due tomorrow — a dedicated amber, distinct from both `.warn`'s orange and plain yellow.
    case notice
    /// Due later than tomorrow — neutral gray. Deliberately never green: the app has no explicit
    /// done/complete state in MVP, so green would misleadingly read as "done" (PRD D-03).
    case neutral
    /// No due date. `DueDateBadge` never actually renders this role in practice — callers gate the
    /// badge's presence on `card.dueDate != nil` before ever constructing one (PRD D-02: no badge
    /// at all) — but it completes the mapping so `DueDateStatus.classify`'s full case set (which
    /// includes `.none` for a nil due date) has a total, testable counterpart here.
    case hidden
}

/// Pure `DueDateStatus` → `BadgeRole` classification. No SwiftUI/SwiftData imports — see `BadgeRole`.
enum DueDateBadgeStyle {
    static func role(for status: DueDateStatus) -> BadgeRole {
        switch status {
        case .none: .hidden
        case .overdue: .alert
        case .today: .warn
        case .tomorrow: .notice
        case .upcoming: .neutral
        }
    }
}
