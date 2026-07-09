import SwiftUI

/// The card detail sheet (M6): title, description, labels, and due date are all STAGED as local
/// `@State` copies initialized from `card` — nothing writes to the store while editing. "Save"
/// commits the whole staged edit through ONE `BoardStore.applyCardEdits` call (so one ⌘Z reverses
/// it); "Cancel"/Esc simply dismiss, discarding the local `@State` untouched.
///
/// Presented via `.sheet(item:)` from `BoardView` (bound to its `selectedDetailCard: Card?`), the
/// same pattern `SidebarView` already uses for `EditBoardSheet`/`editingBoard`.
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
    @State private var includesTime: Bool
    @State private var durationMinutes: Int?
    @State private var checklistDrafts: [ChecklistDraft]

    init(card: Card, store: BoardStore, onDelete: @escaping () -> Void) {
        self.card = card
        self.store = store
        self.onDelete = onDelete
        _title = State(initialValue: card.title)
        _details = State(initialValue: card.details ?? "")
        _labels = State(initialValue: Set(card.labels.compactMap { LabelColor(rawValue: $0.colorName) }))
        _dueDate = State(initialValue: card.dueDate)
        _includesTime = State(initialValue: card.includesTime)
        _durationMinutes = State(initialValue: card.durationMinutes)
        _checklistDrafts = State(initialValue: ChecklistDraft.drafts(of: card))
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

                actionItemsSection

                LabelPicker(selected: $labels)
                DueDatePicker(dueDate: $dueDate, includesTime: $includesTime, durationMinutes: $durationMinutes)
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
            // No confirmation (PRD C-05, same as the card row's context-menu delete;
            // NOT undoable since M-E — see BoardStore.deleteCard).
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
            dueDate: dueDate,
            includesTime: includesTime,
            durationMinutes: durationMinutes,
            checklist: checklistDrafts // staged; the store drops whitespace-only drafts
        )
    }

    // MARK: - M-E: Action Items (staged, like every other sheet field)

    private static let checklistRowHeight: CGFloat = 28
    /// Rows visible without scrolling. WHY a bounded scroller at all: the Brief editor is the
    /// sheet's ONE flexible element (maxHeight .infinity + layoutPriority(1), floor 120pt) — an
    /// UNbounded checklist would push Labels/Due Date/footer off the fixed-ideal-height sheet,
    /// the exact bug class M-0's testLongBriefScrollsInsideEditorNotSheet pins for the editor.
    /// A FIXED, content-sized height keeps this section out of the flexible-layout negotiation
    /// entirely, and the CAP is deliberately small (4 rows ≈ 112pt): with an empty Brief the
    /// editor sits well above its floor, so the section compresses the EDITOR, never the pinned
    /// due-date controls (testLongChecklistKeepsDueDateHittable is the regression gate). Long
    /// Brief + long checklist at DEFAULT size is the one accepted squeeze — the sheet is
    /// user-resizable since M-0. With ≤4 rows nothing ever scrolls, so row clicks/typing are
    /// unaffected. NOT a native List (nested-scroll + .onMove pitfalls) — a plain NON-lazy
    /// ForEach in a plain ScrollView (non-lazy so below-the-fold rows still exist for AX queries).
    private static let checklistVisibleRowCap = 4

    private var stagedDoneCount: Int { checklistDrafts.filter(\.isDone).count }

    private var checklistRowsHeight: CGFloat {
        CGFloat(min(checklistDrafts.count, Self.checklistVisibleRowCap)) * Self.checklistRowHeight
    }

    private var actionItemsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            // ONE header line: title + staged count + inline Add — an EMPTY checklist costs the
            // sheet ~20pt total, which is what keeps the pre-M-E layout tests green.
            HStack(spacing: 6) {
                Text("Action Items")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !checklistDrafts.isEmpty {
                    // Staged count — live while editing, matching the face fraction after Save.
                    Text("\(stagedDoneCount)/\(checklistDrafts.count)")
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Button {
                    checklistDrafts.append(ChecklistDraft(id: nil, text: "", isDone: false))
                    // Deliberately NO focus move onto the new row: .focused()/FocusState bindings
                    // are the launch-focus pitfall's surface (they killed the keyboard command
                    // surface once already — see CLAUDE.md). The user clicks into the row.
                    // Accepted v1.
                } label: {
                    Label("Add Item", systemImage: "plus")
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .accessibilityIdentifier(AccessibilityID.checkItemAdd)
            }
            if !checklistDrafts.isEmpty {
                ScrollView {
                    VStack(spacing: 0) {
                        // Index identity — deliberate: new drafts have nil ids (ChecklistDraft is
                        // not Identifiable), and v1 has no reorder UI, so the index is stable for
                        // the sheet's lifetime and doubles as the AX-id key.
                        ForEach(checklistDrafts.indices, id: \.self) { index in
                            checklistRow(index)
                        }
                    }
                }
                .frame(height: checklistRowsHeight)
            }
        }
    }

    private func checklistRow(_ index: Int) -> some View {
        HStack(spacing: 8) {
            Button {
                checklistDrafts[index].isDone.toggle()
            } label: {
                Image(systemName: checklistDrafts[index].isDone ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(checklistDrafts[index].isDone ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.plain)
            .help(checklistDrafts[index].isDone ? "Mark as not done" : "Mark as done")
            .accessibilityLabel(checklistDrafts[index].isDone ? "Done" : "Not Done")
            .accessibilityIdentifier(AccessibilityID.checkItemToggle(index))

            TextField("Action item", text: $checklistDrafts[index].text)
                .textFieldStyle(.plain)
                // MANDATORY (CLAUDE.md text-input pitfall): the first NEW text inputs since M-A.
                // Without this, ⌘⌫/⌘N/every menu shortcut fires while the user types an item.
                .reportsTextInputFocus()
                .accessibilityIdentifier(AccessibilityID.checkItemText(index))

            Button {
                checklistDrafts.remove(at: index)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Remove item")
            .accessibilityLabel("Remove Item")
            .accessibilityIdentifier(AccessibilityID.checkItemDelete(index))
        }
        .frame(height: Self.checklistRowHeight)
    }
}
