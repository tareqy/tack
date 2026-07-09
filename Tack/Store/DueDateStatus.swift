import Foundation

/// Pure due-date urgency classification (PRD §4.5 / D-03). No SwiftData/SwiftUI imports.
enum DueDateStatus {
    case none
    case overdue
    case today
    case tomorrow
    case upcoming

    /// Classifies `dueDate` relative to `now`. Date-only cards (`includesTime == false` — the
    /// default, matching every pre-M-B call site) compare by calendar day exactly as before.
    /// Timed cards (M-B) go `.overdue` the moment `now` is STRICTLY past the end of the slot —
    /// `dueDate + (durationMinutes ?? 0) minutes` — and otherwise fall through to the same
    /// day-based bucketing (a 2 PM slot later today is `.today`, not some "due soon" state).
    /// Non-positive durations are treated as nil: a zero-length slot ends at its start.
    static func classify(dueDate: Date?, includesTime: Bool = false, durationMinutes: Int? = nil,
                         now: Date, calendar: Calendar) -> DueDateStatus {
        guard let dueDate else { return .none }
        if includesTime {
            let minutes = max(durationMinutes ?? 0, 0)
            let slotEnd = calendar.date(byAdding: .minute, value: minutes, to: dueDate) ?? dueDate
            if now > slotEnd { return .overdue }
        }
        let today = calendar.startOfDay(for: now)
        let due = calendar.startOfDay(for: dueDate)
        let dayDelta = calendar.dateComponents([.day], from: today, to: due).day ?? 0
        switch dayDelta {
        case ..<0:
            return .overdue
        case 0:
            return .today
        case 1:
            return .tomorrow
        default:
            return .upcoming
        }
    }
}
