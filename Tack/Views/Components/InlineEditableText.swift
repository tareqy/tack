import SwiftUI

/// A piece of text that becomes an inline-editable `TextField` on a configurable trigger (single
/// or double click), committing the trimmed result via a closure rather than a two-way binding —
/// callers own what "commit" means (`store.renameList`, `store.updateTitle`, ...), this view only
/// owns the click-to-edit / Enter-commits / Esc-cancels machinery.
///
/// Introduced in M4 for list-header rename (double-click); M5 reuses it as-is for card-title edit
/// (single-click) — keep this file's API generic to both call sites, not list-specific.
///
/// A single `accessibilityID` covers BOTH the display `Text` and the edit `TextField`: exactly one
/// of the two exists in the view tree at any moment (an `if/else`, not an overlay), so there is no
/// ambiguity — callers/tests can query the one identifier regardless of editing state.
struct InlineEditableText: View {
    enum EditTrigger {
        case click
        case doubleClick
    }

    private let text: String
    private let beginEditOn: EditTrigger
    private let font: Font
    private let accessibilityID: String
    private let onCommit: (String) -> Void

    /// Optional external "please begin editing now" trigger, for callers that start the edit from
    /// somewhere other than the click gesture — M5's card context-menu "Rename Card". The caller
    /// flips it to `true`; this view begins editing and immediately flips it back to `false` so the
    /// next flip is observed. Defaults to a constant `false` binding, so the M4 list-header call
    /// site (which only ever edits via double-click) is unchanged.
    @Binding private var beginEditSignal: Bool

    @State private var isEditing = false
    @State private var draft = ""
    @FocusState private var isFocused: Bool

    init(
        _ text: String,
        beginEditOn: EditTrigger = .doubleClick,
        font: Font = .body,
        accessibilityID: String,
        beginEditSignal: Binding<Bool> = .constant(false),
        onCommit: @escaping (String) -> Void
    ) {
        self.text = text
        self.beginEditOn = beginEditOn
        self.font = font
        self.accessibilityID = accessibilityID
        self._beginEditSignal = beginEditSignal
        self.onCommit = onCommit
    }

    var body: some View {
        Group {
            if isEditing {
                // A visible "you are editing" treatment: soft well + accent hairline. Horizontal
                // only (no vertical padding, negative outer compensation) so the text doesn't
                // shift and the row height feeding DropMath's measurement doesn't change.
                TextField("", text: $draft)
                    .textFieldStyle(.plain)
                    .font(font)
                    .focused($isFocused)
                    .reportsTextInputFocus()
                    .onSubmit(commit)
                    .onExitCommand(perform: cancel)
                    .onAppear { isFocused = true }
                    .padding(.horizontal, 4)
                    .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 4))
                    // Non-hit-testing so caret clicks reach the field (see CardDetailView's hairline).
                    .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Color.accentColor.opacity(0.6)).allowsHitTesting(false))
                    .padding(.horizontal, -4)
                    .accessibilityIdentifier(accessibilityID)
            } else {
                Text(text)
                    .font(font)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .contentShape(Rectangle())
                    .onTapGesture(count: beginEditOn == .doubleClick ? 2 : 1, perform: beginEditing)
                    .accessibilityIdentifier(accessibilityID)
            }
        }
        .onChange(of: beginEditSignal) { _, shouldBegin in
            if shouldBegin {
                beginEditing()
                beginEditSignal = false
            }
        }
    }

    private func beginEditing() {
        // Re-entrancy guard: a stray trigger (e.g. a second Rename click, or a click landing inside
        // the field) must not reset an in-progress `draft` back to the original text.
        guard !isEditing else { return }
        draft = text
        isEditing = true
    }

    /// Trims and commits via `onCommit`, UNLESS the result is empty/whitespace-only — that case is
    /// a no-op that stays in edit mode (mirrors `AddListButton`'s "empty Enter keeps editing open").
    private func commit() {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        isEditing = false
        onCommit(trimmed)
    }

    private func cancel() {
        isEditing = false
    }
}
