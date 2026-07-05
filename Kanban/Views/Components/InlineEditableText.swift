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

    @State private var isEditing = false
    @State private var draft = ""
    @FocusState private var isFocused: Bool

    init(
        _ text: String,
        beginEditOn: EditTrigger = .doubleClick,
        font: Font = .body,
        accessibilityID: String,
        onCommit: @escaping (String) -> Void
    ) {
        self.text = text
        self.beginEditOn = beginEditOn
        self.font = font
        self.accessibilityID = accessibilityID
        self.onCommit = onCommit
    }

    var body: some View {
        Group {
            if isEditing {
                TextField("", text: $draft)
                    .textFieldStyle(.plain)
                    .font(font)
                    .focused($isFocused)
                    .onSubmit(commit)
                    .onExitCommand(perform: cancel)
                    .onAppear { isFocused = true }
                    .accessibilityIdentifier(accessibilityID)
            } else {
                Text(text)
                    .font(font)
                    .contentShape(Rectangle())
                    .onTapGesture(count: beginEditOn == .doubleClick ? 2 : 1, perform: beginEditing)
                    .accessibilityIdentifier(accessibilityID)
            }
        }
    }

    private func beginEditing() {
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
