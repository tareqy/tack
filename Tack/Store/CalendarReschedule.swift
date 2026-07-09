import Foundation

/// M-D: pure calendar-view math — this file hosts TWO related pure enums (the `ListBucket.swift`
/// precedent: bucket + snapshot builder share a file), both Foundation-only and clock-injected
/// for exhaustive unit testing.

/// The drop-to-reschedule date math: what `dueDate` a card should get when dropped on a day cell.
enum CalendarReschedule {
    /// Retargets `original` onto the calendar day containing `day` (normalized to start-of-day
    /// first — a cell's date is always a start-of-day, but the function doesn't rely on it).
    ///
    /// - Date-only cards (`includesTime == false`) and nil originals (a No-Date rail drag, or the
    ///   degenerate timed-with-no-date combination) land on the target's start-of-day — which is
    ///   exactly what `BoardStore.setDueDate`'s date-only normalization would produce anyway, so
    ///   the store's same-value guard sees a byte-identical trio for a same-day drop.
    /// - Timed cards keep their wall-clock hour/minute on the new day (dropping a 14:00 card on
    ///   Thursday means 14:00 Thursday), via `bySettingHour` on the target's start-of-day.
    ///   Seconds are normalized to :00 — every UI-creatable slot is minute-precision (the M-B
    ///   time field), so a same-day drop of any real card is still an exact identity.
    /// - DST spring-forward gap: if the original wall-clock time does not exist on the target
    ///   day (e.g. 02:30 dropped on a US transition day), `bySettingHour` does NOT return nil —
    ///   Foundation's `.nextTime` matching policy rolls forward to the first valid instant
    ///   (03:00). That roll-forward is the pinned, tested behavior (see
    ///   `dstSpringForwardGapRollsForward`) — deliberately accepted as-is for v1. The
    ///   `?? targetDay` start-of-day fallback below is therefore a defensive last resort for a
    ///   nil that no real calendar/time-zone input has been observed to produce, NOT the DST
    ///   path; if it ever did fire, the time-of-day would be silently dropped.
    static func retargetedDueDate(original: Date?, includesTime: Bool, onto day: Date,
                                  calendar: Calendar) -> Date {
        let targetDay = calendar.startOfDay(for: day)
        guard includesTime, let original else { return targetDay }
        let time = calendar.dateComponents([.hour, .minute], from: original)
        return calendar.date(bySettingHour: time.hour ?? 0, minute: time.minute ?? 0,
                             second: 0, of: targetDay) ?? targetDay
    }
}

/// The month grid's cell math. Day cells are DATE-keyed (`Day.id` is the start-of-day `Date`) —
/// deliberately NOT the M-C synthetic-UUID trick: that existed solely to feed SelectionNavigation
/// a BoardSnapshot, and calendar v1 doesn't use SelectionNavigation at all (bare-arrow selection
/// is honestly disabled via `BoardActions.canNavigateSelection`; see `CalendarBoardView`).
enum CalendarMonthGrid {
    /// One grid cell. `isInDisplayedMonth == false` marks the leading/trailing filler days from
    /// adjacent months — rendered dimmed, NON-interactive (no id, no chips, no drop destination).
    struct Day: Equatable, Identifiable {
        let date: Date
        let isInDisplayedMonth: Bool
        var id: Date { date }
    }

    /// The first instant of the month containing `date` — the ONLY shape a month anchor is ever
    /// stored in (`CalendarBoardView.monthAnchor`), so prev/next navigation (`byAdding: .month`)
    /// can never hit the Jan-31 clamping drift.
    static func monthStart(containing date: Date, calendar: Calendar) -> Date {
        calendar.dateInterval(of: .month, for: date)?.start ?? calendar.startOfDay(for: date)
    }

    /// Every cell of the displayed month's grid, in row order: whole weeks from the calendar's
    /// `firstWeekday`, spanning the week containing the 1st through the week containing the last
    /// day of the month. Always a multiple of 7 (28–42 cells).
    static func days(anchoredAt anchor: Date, calendar: Calendar) -> [Day] {
        let start = monthStart(containing: anchor, calendar: calendar)
        guard let dayCount = calendar.range(of: .day, in: .month, for: start)?.count,
              let monthEnd = calendar.date(byAdding: .day, value: dayCount - 1, to: start),
              let gridStart = calendar.dateInterval(of: .weekOfYear, for: start)?.start,
              let gridEnd = calendar.dateInterval(of: .weekOfYear, for: monthEnd)?.end else {
            return []
        }
        var days: [Day] = []
        var cursor = gridStart
        while cursor < gridEnd {
            days.append(Day(date: cursor,
                            isInDisplayedMonth: calendar.isDate(cursor, equalTo: start,
                                                                toGranularity: .month)))
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        return days
    }

    /// The 7 column headers (very-short weekday symbols), rotated so index 0 is the calendar's
    /// `firstWeekday` — `veryShortWeekdaySymbols` is ALWAYS Sunday-first regardless of locale.
    static func weekdayHeaders(calendar: Calendar) -> [String] {
        let symbols = calendar.veryShortWeekdaySymbols
        let shift = (calendar.firstWeekday - 1) % symbols.count
        return Array(symbols[shift...] + symbols[..<shift])
    }
}
