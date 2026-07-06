import SwiftUI

/// Quick-pick buttons (Today / Tomorrow / Next Week), a compact date field, and Clear — all mutate
/// ONLY the caller's staged `Date?` binding (see `CardDetailView`, which commits the whole staged
/// edit through `BoardStore.applyCardEdits` on Save). Shows an explicit "No due date" label when
/// nil, matching the card face's own "no badge at all" convention for the same state.
struct DueDatePicker: View {
    @Binding var dueDate: Date?

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
                    .accessibilityIdentifier(AccessibilityID.dueDatePickerField)

                    Button("Clear", role: .destructive) {
                        dueDate = nil
                    }
                    .accessibilityIdentifier(AccessibilityID.dueClear)
                }
            } else {
                Text("No due date")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func quickButton(_ title: String, option: DueDateQuickOption, id: String) -> some View {
        Button(title) {
            dueDate = DueDateQuickOption.date(for: option, now: .now, calendar: .current)
        }
        .accessibilityIdentifier(id)
    }
}
