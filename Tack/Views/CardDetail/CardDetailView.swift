import SwiftUI

/// The shared card editor used by both the modal sheet and the trailing inspector. Title, brief,
/// labels, due date, and action items are STAGED as local `@State` copies initialized from `card` —
/// nothing writes to the store while editing. "Save" commits through ONE
/// `BoardStore.applyCardEdits` call (so one ⌘Z reverses it); "Cancel"/Esc close and discard.
struct CardDetailView: View {
    let card: Card
    let store: BoardStore
    let presentation: CardDetailPresentation
    /// Deletion is delegated to the RootView presenter, NOT performed here, for a specific
    /// ordering reason: `store.deleteCard` before clearing presentation state would re-render while its
    /// presentation state still holds the now-DELETED card. The presenter instead clears the card
    /// ID FIRST, then deletes — so no re-render ever touches the dead object.
    let onDelete: () -> Void
    let onClose: () -> Void
    /// RootView uses this signal to guard inspector-only context changes. The editor keeps the
    /// canonical staged values; RootView never attempts to mirror or reconstruct drafts.
    let onDirtyChange: (Bool) -> Void

    @State private var title: String
    @State private var details: String
    @State private var labels: Set<LabelColor>
    @State private var dueDate: Date?
    @State private var includesTime: Bool
    @State private var durationMinutes: Int?
    @State private var checklistDrafts: [ChecklistDraft]
    @State private var initialDraft: EditorDraft

    init(
        card: Card,
        store: BoardStore,
        presentation: CardDetailPresentation,
        onDelete: @escaping () -> Void,
        onClose: @escaping () -> Void,
        onDirtyChange: @escaping (Bool) -> Void
    ) {
        let draft = EditorDraft(
            title: card.title,
            details: card.details ?? "",
            labels: Set(card.labels.compactMap { LabelColor(rawValue: $0.colorName) }),
            dueDate: card.dueDate,
            includesTime: card.includesTime,
            durationMinutes: card.durationMinutes,
            checklistDrafts: ChecklistDraft.drafts(of: card)
        )
        self.card = card
        self.store = store
        self.presentation = presentation
        self.onDelete = onDelete
        self.onClose = onClose
        self.onDirtyChange = onDirtyChange
        _title = State(initialValue: draft.title)
        _details = State(initialValue: draft.details)
        _labels = State(initialValue: draft.labels)
        _dueDate = State(initialValue: draft.dueDate)
        _includesTime = State(initialValue: draft.includesTime)
        _durationMinutes = State(initialValue: draft.durationMinutes)
        _checklistDrafts = State(initialValue: draft.checklistDrafts)
        _initialDraft = State(initialValue: draft)
    }

    var body: some View {
        Group {
            switch presentation {
            case .sheet:
                sheetLayout
            case .sidePanel:
                inspectorLayout
            }
        }
        .accessibilityElement(children: .contain)
        // Keep the established `card-detail` wire value on BOTH surfaces. Surface-specific
        // assertions use sibling markers instead of changing this editor-root id.
        .accessibilityIdentifier(AccessibilityID.cardDetailSheet)
        .overlay(alignment: .topLeading) { presentationMarker }
        .onAppear(perform: reportDirtyState)
        .onChange(of: currentDraft) { _, _ in reportDirtyState() }
        .onChange(of: persistedDraft) { _, newDraft in
            reconcilePersistedChanges(newDraft)
        }
        // Belt-and-suspenders with Cancel's own `.cancelAction` shortcut below: this fires Esc
        // regardless of which staged-edit control currently holds focus.
        .onExitCommand(perform: cancel)
    }

    private var sheetLayout: some View {
        VStack(alignment: .leading, spacing: 0) {
            formContent
                .padding(20)

            Divider()

            footer
                .padding(20)
        }
        // Resizable sheet: flexible max + pinned ideal makes the macOS sheet user-resizable
        // while opening at (and never shrinking below) the classic 460×560.
        .frame(minWidth: 460, idealWidth: 460, maxWidth: .infinity,
               minHeight: 560, idealHeight: 560, maxHeight: .infinity)
    }

    /// Native inspector chrome supplies the trailing divider; this compact header gives the
    /// working rail a stable title and an explicit close affordance. Only the form body scrolls,
    /// so destructive/Cancel/Save actions remain pinned at the bottom.
    private var inspectorLayout: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text("Card Details")
                    .font(.headline)
                    .accessibilityIdentifier(AccessibilityID.cardDetailInspector)
                Spacer()
                Button(action: cancel) {
                    Image(systemName: "xmark")
                }
                .buttonStyle(HoverHighlightButtonStyle())
                .help("Close card details")
                .accessibilityLabel("Close Card Details")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            ScrollView {
                formContent
                    .padding(16)
            }

            Divider()

            footer
                .padding(16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    /// A detached sibling of the established `card-detail` editor root. Keeping the marker in the
    /// presentation subtree (rather than RootView's marker stack) prevents SwiftUI from merging it
    /// with the independent `view-mode-value` accessibility representation.
    private var presentationMarker: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .allowsHitTesting(false)
            .accessibilityRepresentation {
                Text(presentation.rawValue)
                    .accessibilityIdentifier(AccessibilityID.cardDetailPresentationValue)
            }
    }

    private var formContent: some View {
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
                // + separator hairline). NO `.scrollContentBackground(.hidden)`: on macOS that
                // makes this editor report AX-Disabled under XCUITest.
                TextEditor(text: $details)
                    .font(.body)
                    .reportsTextInputFocus()
                    // In the sheet this remains the ONE flexible element, preserving its exact
                    // established geometry. In the inspector it gets a bounded working height;
                    // the enclosing form is what scrolls as the panel gets shorter.
                    .frame(minHeight: 120,
                           idealHeight: presentation == .sidePanel ? 180 : nil,
                           maxHeight: presentation == .sidePanel ? 240 : .infinity)
                    .layoutPriority(presentation == .sheet ? 1 : 0)
                    .padding(4)
                    .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                    // Hairline must NOT hit-test: a SwiftUI overlay above an AppKit-backed
                    // editor intercepts the click that gives the NSTextView keyboard focus.
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color(nsColor: .separatorColor)).allowsHitTesting(false))
                    .accessibilityIdentifier(AccessibilityID.cardDetailDescriptionField)
            }

            actionItemsSection

            LabelPicker(selected: $labels)
            DueDatePicker(dueDate: $dueDate, includesTime: $includesTime, durationMinutes: $durationMinutes)
        }
    }

    private var footer: some View {
        HStack {
            // No confirmation (PRD C-05, same as the card row's context-menu delete;
            // NOT undoable since M-E — see BoardStore.deleteCard).
            Button("Delete Card", role: .destructive) {
                onDirtyChange(false)
                onDelete()
            }

            Spacer()

            Button("Cancel", role: .cancel, action: cancel)
                .keyboardShortcut(.cancelAction)

            Button("Save") {
                save()
                onDirtyChange(false)
                onClose()
            }
            // Deliberately NOT `.defaultAction` (plain Return): the description `TextEditor` must
            // keep plain Return as "insert a newline", so only ⌘⏎ commits (PRD convention).
            // `.borderedProminent` restores the accent-filled primary-action look that skipping
            // `.defaultAction` otherwise forfeits (HIG: one clearly-marked default button).
            .keyboardShortcut(.return, modifiers: .command)
            .buttonStyle(.borderedProminent)
        }
    }

    private struct EditorDraft: Equatable {
        var title: String
        var details: String
        var labels: Set<LabelColor>
        var dueDate: Date?
        var includesTime: Bool
        var durationMinutes: Int?
        var checklistDrafts: [ChecklistDraft]
    }

    private var currentDraft: EditorDraft {
        EditorDraft(
            title: title,
            details: details,
            labels: labels,
            dueDate: dueDate,
            includesTime: includesTime,
            durationMinutes: durationMinutes,
            checklistDrafts: checklistDrafts
        )
    }

    /// The live model snapshot. While the nonmodal inspector is open, board actions and undo can
    /// legitimately edit this card outside the editor. Observing this value lets clean staged
    /// fields follow those writes instead of saving an old full-card snapshot over them.
    private var persistedDraft: EditorDraft {
        EditorDraft(
            title: card.title,
            details: card.details ?? "",
            labels: Set(card.labels.compactMap { LabelColor(rawValue: $0.colorName) }),
            dueDate: card.dueDate,
            includesTime: card.includesTime,
            durationMinutes: card.durationMinutes,
            checklistDrafts: ChecklistDraft.drafts(of: card)
        )
    }

    /// Three-way merge an external model write into the staged editor. A field that still equals
    /// the previous persisted baseline is clean and adopts the external value; a locally changed
    /// field remains staged and wins. Date, time inclusion, and duration are one semantic unit, so
    /// any local change in that group protects the whole group from a partial merge.
    private func reconcilePersistedChanges(_ newPersistedDraft: EditorDraft) {
        let previousPersistedDraft = initialDraft
        var reconciledDraft = currentDraft

        if reconciledDraft.title == previousPersistedDraft.title {
            reconciledDraft.title = newPersistedDraft.title
        }
        if reconciledDraft.details == previousPersistedDraft.details {
            reconciledDraft.details = newPersistedDraft.details
        }
        if reconciledDraft.labels == previousPersistedDraft.labels {
            reconciledDraft.labels = newPersistedDraft.labels
        }

        let dueDateGroupIsClean = reconciledDraft.dueDate == previousPersistedDraft.dueDate
            && reconciledDraft.includesTime == previousPersistedDraft.includesTime
            && reconciledDraft.durationMinutes == previousPersistedDraft.durationMinutes
        if dueDateGroupIsClean {
            reconciledDraft.dueDate = newPersistedDraft.dueDate
            reconciledDraft.includesTime = newPersistedDraft.includesTime
            reconciledDraft.durationMinutes = newPersistedDraft.durationMinutes
        }

        if reconciledDraft.checklistDrafts == previousPersistedDraft.checklistDrafts {
            reconciledDraft.checklistDrafts = newPersistedDraft.checklistDrafts
        }

        title = reconciledDraft.title
        details = reconciledDraft.details
        labels = reconciledDraft.labels
        dueDate = reconciledDraft.dueDate
        includesTime = reconciledDraft.includesTime
        durationMinutes = reconciledDraft.durationMinutes
        checklistDrafts = reconciledDraft.checklistDrafts
        initialDraft = newPersistedDraft

        // The baseline can change without any staged value changing, so the currentDraft observer
        // alone cannot reliably publish this transition.
        onDirtyChange(reconciledDraft != newPersistedDraft)
    }

    private func reportDirtyState() {
        onDirtyChange(currentDraft != initialDraft)
    }

    private func cancel() {
        onDirtyChange(false)
        onClose()
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
