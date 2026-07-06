import SwiftUI

/// The card detail sheet (M6): title, description, labels, and due date are all STAGED as local
/// `@State` copies initialized from `card` — nothing writes to the store while editing. "Save"
/// commits the whole staged edit through ONE `BoardStore.applyCardEdits` call (so one ⌘Z reverses
/// it); "Cancel"/Esc simply dismiss, discarding the local `@State` untouched.
///
/// Presented via `.sheet(item:)` from `BoardView` (bound to its `selectedDetailCard: Card?`), the
/// same pattern `SidebarView` already uses for `RenameBoardSheet`/`renamingBoard`.
struct CardDetailView: View {
    let card: Card
    let store: BoardStore
    /// Deletion is delegated to the presenter (BoardView), NOT performed here, for a specific
    /// ordering reason: `store.deleteCard` before `dismiss()` would re-render BoardView while its
    /// `.sheet(item:)` binding still holds the now-DELETED card, re-invoking this view's `init`
    /// (which reads `card.title` etc.) against a destroyed SwiftData model. The presenter instead
    /// nils the sheet item FIRST, then deletes — so no re-render ever touches the dead object.
    let onDelete: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var title: String
    @State private var details: String
    @State private var labels: Set<LabelColor>
    @State private var dueDate: Date?

    init(card: Card, store: BoardStore, onDelete: @escaping () -> Void) {
        self.card = card
        self.store = store
        self.onDelete = onDelete
        _title = State(initialValue: card.title)
        _details = State(initialValue: card.details ?? "")
        _labels = State(initialValue: Set(card.labels.compactMap { LabelColor(rawValue: $0.colorName) }))
        _dueDate = State(initialValue: card.dueDate)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    TextField("Title", text: $title)
                        .textFieldStyle(.plain)
                        .font(.title2)
                        .accessibilityIdentifier(AccessibilityID.cardDetailTitleField)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Description")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextEditor(text: $details)
                            .font(.body)
                            .frame(minHeight: 120)
                            .padding(4)
                            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                            .accessibilityIdentifier(AccessibilityID.cardDetailDescriptionField)
                    }

                    LabelPicker(selected: $labels)
                    DueDatePicker(dueDate: $dueDate)
                }
                .padding(20)
            }

            Divider()

            footer
                .padding(20)
        }
        .frame(width: 460, height: 560)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AccessibilityID.cardDetailSheet)
        // Belt-and-suspenders with Cancel's own `.cancelAction` shortcut below: this fires Esc
        // regardless of which staged-edit control (title field / description editor / label chip)
        // currently holds focus.
        .onExitCommand { dismiss() }
    }

    private var footer: some View {
        HStack {
            // No confirmation (PRD v1.1 C-05, same as the card row's context-menu delete).
            Button("Delete Card", role: .destructive) {
                onDelete()
            }

            Spacer()

            Button("Cancel", role: .cancel) { dismiss() }
                .keyboardShortcut(.cancelAction)

            Button("Save") {
                save()
                dismiss()
            }
            // Deliberately NOT `.defaultAction` (plain Return): the description `TextEditor` must
            // keep plain Return as "insert a newline", so only ⌘⏎ commits (PRD convention).
            .keyboardShortcut(.return, modifiers: .command)
        }
    }

    private func save() {
        let trimmedDetails = details.trimmingCharacters(in: .whitespacesAndNewlines)
        store.applyCardEdits(
            card,
            title: title,
            details: trimmedDetails.isEmpty ? nil : trimmedDetails,
            labels: labels,
            dueDate: dueDate
        )
    }
}
