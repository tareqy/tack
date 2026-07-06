import Foundation

/// Pure quick-pick date math for the M6 due-date picker's Today/Tomorrow/Next Week buttons. No
/// SwiftData/SwiftUI imports (same rationale as `DropMath`/`DueDateStatus`: this is the one bit of
/// date arithmetic worth unit-testing in isolation with a fixed clock).
enum DueDateQuickOption {
    case today
    case tomorrow
    case nextWeek

    /// Resolves `option` against `now`, always returning a calendar start-of-day (matching
    /// `BoardStore.setDueDate`/`applyCardEdits`'s normalization, so staging one of these values and
    /// later committing it through the store is idempotent).
    static func date(for option: DueDateQuickOption, now: Date, calendar: Calendar) -> Date {
        let today = calendar.startOfDay(for: now)
        switch option {
        case .today:
            return today
        case .tomorrow:
            return calendar.date(byAdding: .day, value: 1, to: today) ?? today
        case .nextWeek:
            return calendar.date(byAdding: .day, value: 7, to: today) ?? today
        }
    }
}
