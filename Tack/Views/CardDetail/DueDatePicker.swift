import SwiftUI

/// Quick-pick buttons (Today / Tomorrow / Next Week), a compact date field, an optional time slot
/// (M-B: Time toggle → hour-and-minute field + duration menu), and Clear — all mutate ONLY the
/// caller's staged bindings (see `CardDetailView`, which commits the whole staged edit through
/// `BoardStore.applyCardEdits` on Save). Shows an explicit "No due date" label when nil, matching
/// the card face's own "no badge at all" convention for the same state.
///
/// Time-state contract (M-B):
///   - Quick buttons are DATE-ONLY by contract (`DueDateQuickOption` always returns start-of-day,
///     per its doc), so they ALSO reset `includesTime`/`durationMinutes` — the stage always
///     matches what the store persists for that pick; re-enabling time goes through the toggle.
///   - Toggle ON with a bare-midnight staged date sets the slot to 9:00 AM of that day —
///     deterministic (UI-testable) and a sane working-hours default. A date that already carries
///     a time (a previously timed card) is left alone.
///   - Toggle OFF re-normalizes the staged date to start-of-day and drops the duration, so the
///     stage never carries a hidden time on a card the user just made date-only.
///   - Clear resets all three (date, flag, duration).
struct DueDatePicker: View {
    @Binding var dueDate: Date?
    @Binding var includesTime: Bool
    @Binding var durationMinutes: Int?

    /// The duration menu's fixed options, in minutes; nil renders as "None".
    private static let durationOptions: [Int] = [15, 30, 45, 60, 90, 120]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Due Date")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                quickButton("Today", option: .today, id: AccessibilityID.dueQuickToday)
                quickButton("Tomorrow", option: .tomorrow, id: AccessibilityID.dueQuickTomorrow)
                quickButton("Next Week", option: .nextWeek, id: AccessibilityID.dueQuickNextWeek)
            }

            if let resolvedDueDate = dueDate {
                HStack(spacing: 12) {
                    DatePicker(
                        "",
                        selection: Binding(get: { resolvedDueDate }, set: { dueDate = $0 }),
                        displayedComponents: .date
                    )
                    .datePickerStyle(.field)
                    .labelsHidden()
                    .reportsTextInputFocus()
                    .accessibilityIdentifier(AccessibilityID.dueDatePickerField)

                    Button("Clear", role: .destructive) {
                        dueDate = nil
                        includesTime = false
                        durationMinutes = nil
                    }
                    .accessibilityIdentifier(AccessibilityID.dueClear)
                }

                Toggle("Time", isOn: timeToggleBinding)
                    .accessibilityIdentifier(AccessibilityID.dueTimeToggle)

                if includesTime {
                    HStack(spacing: 12) {
                        DatePicker(
                            "",
                            selection: Binding(get: { resolvedDueDate }, set: { dueDate = $0 }),
                            displayedComponents: .hourAndMinute
                        )
                        .datePickerStyle(.field)
                        .labelsHidden()
                        .reportsTextInputFocus()
                        .accessibilityIdentifier(AccessibilityID.dueTimeField)

                        Picker("Duration", selection: $durationMinutes) {
                            Text("None").tag(Int?.none)
                            ForEach(Self.durationOptions, id: \.self) { minutes in
                                Text("\(minutes) min").tag(Int?.some(minutes))
                            }
                        }
                        .pickerStyle(.menu)
                        .fixedSize()
                        .accessibilityIdentifier(AccessibilityID.dueDurationField)
                    }
                }
            } else {
                Text("No due date")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// Routes the toggle through the M-B time-state contract (see the type doc comment). A custom
    /// Binding (not `.onChange`) so the date/duration adjustments land in the same mutation as the
    /// flag flip — no intermediate render with inconsistent staged state.
    private var timeToggleBinding: Binding<Bool> {
        Binding(
            get: { includesTime },
            set: { turnedOn in
                includesTime = turnedOn
                let calendar = Calendar.current
                if turnedOn {
                    if let current = dueDate, calendar.startOfDay(for: current) == current {
                        dueDate = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: current) ?? current
                    }
                } else {
                    dueDate = dueDate.map { calendar.startOfDay(for: $0) }
                    durationMinutes = nil
                }
            }
        )
    }

    private func quickButton(_ title: String, option: DueDateQuickOption, id: String) -> some View {
        Button(title) {
            dueDate = DueDateQuickOption.date(for: option, now: .now, calendar: .current)
            // Date-only by contract — see the time-state contract in the type doc comment.
            includesTime = false
            durationMinutes = nil
        }
        .accessibilityIdentifier(id)
    }
}
