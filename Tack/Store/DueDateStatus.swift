import Foundation

/// Pure due-date urgency classification (PRD §4.5 / D-03). No SwiftData/SwiftUI imports.
enum DueDateStatus {
    case none
    case overdue
    case today
    case tomorrow
    case upcoming

    /// Classifies `dueDate` relative to `now`, comparing by calendar day (not raw time).
    static func classify(dueDate: Date?, now: Date, calendar: Calendar) -> DueDateStatus {
        guard let dueDate else { return .none }
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
