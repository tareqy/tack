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
            VStack(alignment: .leading, spacing: 20) {
                TextField("Title", text: $title)
                    .textFieldStyle(.plain)
                    .font(.title2)
                    .reportsTextInputFocus()
                    .accessibilityIdentifier(AccessibilityID.cardDetailTitleField)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Brief")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    // Native editable-text-area dressing (an NSTextView look: text background
                    // + separator hairline) — the old secondary wash read as a disabled
                    // control, especially in dark mode. NO `.scrollContentBackground(.hidden)`:
                    // SwiftUI's macOS TextEditor is already transparent (the old wash showed
                    // through without it), and adding it made the whole editor report
                    // AX-Disabled under XCUITest, killing keyboard-focus synthesis (caught by
                    // testEditDescriptionSavesAndPersists).
                    // The editor is the ONE flexible element in the sheet: bounded frame +
                    // layoutPriority means long text scrolls INSIDE the editor (NSTextView's
                    // own scrolling) while Labels/Due Date stay pinned below — there is
                    // deliberately no outer ScrollView (caught by
                    // testLongBriefScrollsInsideEditorNotSheet).
                    TextEditor(text: $details)
                        .font(.body)
                        .reportsTextInputFocus()
                        .frame(minHeight: 120, maxHeight: .infinity)
                        .layoutPriority(1)
                        .padding(4)
                        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                        // Hairline must NOT hit-test: a SwiftUI overlay above an AppKit-backed
                        // editor intercepts the click that gives the NSTextView keyboard focus
                        // (caught by testEditDescriptionSavesAndPersists).
                        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color(nsColor: .separatorColor)).allowsHitTesting(false))
                        .accessibilityIdentifier(AccessibilityID.cardDetailDescriptionField)
                }

                LabelPicker(selected: $labels)
                DueDatePicker(dueDate: $dueDate)
            }
            .padding(20)

            Divider()

            footer
                .padding(20)
        }
        // Resizable sheet: flexible max + pinned ideal makes the macOS sheet user-resizable
        // while opening at (and never shrinking below) the classic 460×560.
        .frame(minWidth: 460, idealWidth: 460, maxWidth: .infinity,
               minHeight: 560, idealHeight: 560, maxHeight: .infinity)
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
            // `.borderedProminent` restores the accent-filled primary-action look that skipping
            // `.defaultAction` otherwise forfeits (HIG: one clearly-marked default button).
            .keyboardShortcut(.return, modifiers: .command)
            .buttonStyle(.borderedProminent)
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
