import Foundation

/// M-C: the List View's five due-date sections, in display order (`allCases` IS the section
/// order). Pure Foundation — bucketing is a thin refinement ON TOP of `DueDateStatus.classify`
/// (the single source of truth for overdue/today semantics, including the M-B timed-slot rule:
/// a timed card whose slot has ended is Overdue TODAY), never a parallel re-derivation:
/// `.none`→No Date, `.overdue`→Overdue, `.today`→Today, `.tomorrow`→This Week, and `.upcoming`
/// splits on calendar-day delta — 2...7 days → This Week (the `DueDateQuickOption.nextWeek`
/// +7 anchor), 8+ → Later.
enum ListBucket: CaseIterable {
    case overdue
    case today
    case thisWeek
    case later
    case noDate

    /// Maps one card's due-date state to its section. The defaulted time params mirror
    /// `classify`'s exactly, so date-only call sites read identically in both APIs.
    static func bucket(dueDate: Date?, includesTime: Bool = false, durationMinutes: Int? = nil,
                       now: Date, calendar: Calendar) -> ListBucket {
        switch DueDateStatus.classify(dueDate: dueDate, includesTime: includesTime,
                                      durationMinutes: durationMinutes, now: now, calendar: calendar) {
        case .none:
            return .noDate
        case .overdue:
            return .overdue
        case .today:
            return .today
        case .tomorrow:
            return .thisWeek
        case .upcoming:
            // The This Week / Later split — the ONE piece of date math classify doesn't already
            // answer. Day delta computed exactly like classify computes it (startOfDay to
            // startOfDay, `.day` components), so the two layers can never disagree on "a day".
            guard let dueDate else { return .noDate } // unreachable: .upcoming implies non-nil
            let today = calendar.startOfDay(for: now)
            let due = calendar.startOfDay(for: dueDate)
            let dayDelta = calendar.dateComponents([.day], from: today, to: due).day ?? 0
            return dayDelta <= 7 ? .thisWeek : .later
        }
    }

    /// Section header text.
    var title: String {
        switch self {
        case .overdue: "Overdue"
        case .today: "Today"
        case .thisWeek: "This Week"
        case .later: "Later"
        case .noDate: "No Date"
        }
    }

    /// The slug inside the section header's accessibility id ("list-section-<slug>" — see
    /// `AccessibilityID.listSection`).
    var sectionSlug: String {
        switch self {
        case .overdue: "overdue"
        case .today: "today"
        case .thisWeek: "this-week"
        case .later: "later"
        case .noDate: "no-date"
        }
    }

    /// STABLE synthetic identity for the bucket when it stands in as a `ListSnapshot.id` in a
    /// `BoardSnapshot` (see `ListBucketSnapshot.build`, Task 2) — which is what lets
    /// `SelectionNavigation` drive arrow-key movement across bucket sections with zero changes.
    /// Fixed literals, NOT `UUID()`: a fresh id per access would break snapshot equality and any
    /// caller that correlates buckets across two builds. ("4C" = "L" for List.)
    var snapshotID: UUID {
        switch self {
        case .overdue: UUID(uuidString: "00000000-0000-4000-8000-4C0000000001")!
        case .today: UUID(uuidString: "00000000-0000-4000-8000-4C0000000002")!
        case .thisWeek: UUID(uuidString: "00000000-0000-4000-8000-4C0000000003")!
        case .later: UUID(uuidString: "00000000-0000-4000-8000-4C0000000004")!
        case .noDate: UUID(uuidString: "00000000-0000-4000-8000-4C0000000005")!
        }
    }
}
