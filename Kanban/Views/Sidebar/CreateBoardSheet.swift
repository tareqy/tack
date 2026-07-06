import SwiftUI

/// Presented both from the sidebar's "New Board" toolbar button and from `EmptyStateView`'s
/// "Create your first board" button — same sheet, same behavior, either entry point.
struct CreateBoardSheet: View {
    let store: BoardStore
    /// Called with the newly created board right before the sheet dismisses, so the caller can
    /// select it.
    let onCreated: (Board) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var emoji = ""

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("New Board")
                .font(.headline)

            TextField("Board name", text: $name)
                .textFieldStyle(.roundedBorder)
                .reportsTextInputFocus()
                .accessibilityIdentifier(AccessibilityID.boardNameField)

            TextField("Emoji (optional)", text: $emoji)
                .textFieldStyle(.roundedBorder)
                .reportsTextInputFocus()
                .accessibilityIdentifier(AccessibilityID.boardEmojiField)
                .onChange(of: emoji) { _, newValue in
                    if newValue.count > 1 {
                        emoji = String(newValue.prefix(1))
                    }
                }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                Button("Create") {
                    let created = store.createBoard(name: trimmedName, emoji: emoji.isEmpty ? nil : emoji)
                    onCreated(created)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(trimmedName.isEmpty)
                .accessibilityIdentifier(AccessibilityID.createBoardConfirm)
            }
        }
        .padding(20)
        .frame(width: 320)
    }
}
