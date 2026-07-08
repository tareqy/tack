import SwiftUI

/// The right-edge, column-shaped "add list" affordance at the end of `BoardView`'s scroll of
/// columns. A click reveals an inline text field (a ghost column) to name the new list; Enter
/// creates it via `store.addList(to:name:)` (empty/whitespace input is a no-op that keeps the
/// field open) and returns to the plain button; Esc cancels back to the plain button without
/// creating anything.
struct AddListButton: View {
    let board: Board
    let store: BoardStore
    let columnWidth: CGFloat
    /// Command trigger from BoardView (⌥⌘N): a change to this monotonic token opens the inline
    /// editor. Passed by value (not a binding) because the button only reacts to changes, never
    /// writes it back.
    var openEditorToken: Int = 0

    @State private var isEditing = false
    @State private var draft = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if isEditing {
                // Same "the field looks like what it creates" treatment as the add-card row.
                TextField("List name", text: $draft)
                    .textFieldStyle(.plain)
                    .font(.headline)
                    .focused($isFocused)
                    .reportsTextInputFocus()
                    .onSubmit(commit)
                    .onExitCommand(perform: cancel)
                    .onAppear { isFocused = true }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(Color.cardSurface, in: RoundedRectangle(cornerRadius: 6))
                    // Non-hit-testing so caret clicks reach the field (see CardDetailView's hairline).
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.surfaceHairline).allowsHitTesting(false))
                    .accessibilityIdentifier(AccessibilityID.newListField)
            } else {
                Button {
                    draft = ""
                    isEditing = true
                } label: {
                    Label("Add List", systemImage: "plus")
                        .font(.callout)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(HoverHighlightButtonStyle())
                .accessibilityIdentifier(AccessibilityID.addListButton)
            }
        }
        .padding(8)
        .frame(width: columnWidth, alignment: .topLeading)
        // `.top`, not the default `.center`: the ghost column's affordance must sit on the same
        // line as the real columns' headers, not float mid-column.
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color.columnSurface.opacity(0.55), in: RoundedRectangle(cornerRadius: 10))
        .onChange(of: openEditorToken) { _, _ in
            draft = ""
            isEditing = true
            isFocused = true
        }
    }

    /// Empty/whitespace-only input is a no-op that stays in edit mode (so a stray Enter doesn't
    /// silently dismiss the field the user is about to type into).
    private func commit() {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        store.addList(to: board, name: trimmed)
        draft = ""
        isEditing = false
    }

    private func cancel() {
        isEditing = false
        draft = ""
    }
}
