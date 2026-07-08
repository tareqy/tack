import SwiftUI

/// The unified board-edit sheet (M-A): name + emoji + about, opened from the sidebar row's
/// context menu. Grew out of RenameBoardSheet; commits everything through ONE
/// `store.editBoard` call = one "Edit Board" undo step.
struct EditBoardSheet: View {
    let board: Board
    let store: BoardStore

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var emoji: String
    @State private var about: String

    init(board: Board, store: BoardStore) {
        self.board = board
        self.store = store
        _name = State(initialValue: board.name)
        _emoji = State(initialValue: board.emoji ?? "")
        _about = State(initialValue: board.about ?? "")
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Edit Board")
                .font(.headline)

            TextField("Board name", text: $name)
                .textFieldStyle(.roundedBorder)
                .reportsTextInputFocus()
                .accessibilityIdentifier(AccessibilityID.editBoardNameField)

            TextField("Emoji (optional)", text: $emoji)
                .textFieldStyle(.roundedBorder)
                .reportsTextInputFocus()
                .accessibilityIdentifier(AccessibilityID.editBoardEmojiField)
                .onChange(of: emoji) { _, newValue in
                    // Keep the LAST grapheme: a picked/typed replacement wins over the old
                    // emoji (prefix(1) silently discarded palette insertions — M-A fix).
                    if newValue.count > 1 {
                        emoji = String(newValue.suffix(1))
                    }
                }

            TextField("About (optional)", text: $about)
                .textFieldStyle(.roundedBorder)
                .reportsTextInputFocus()
                .accessibilityIdentifier(AccessibilityID.editBoardAboutField)

            HStack {
                Spacer()
                // Esc must cancel any sheet (HIG) — same one-liner as CreateBoardSheet.
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    let trimmedAbout = about.trimmingCharacters(in: .whitespacesAndNewlines)
                    store.editBoard(board,
                                    name: trimmedName,
                                    emoji: emoji.isEmpty ? nil : emoji,
                                    about: trimmedAbout.isEmpty ? nil : trimmedAbout)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(trimmedName.isEmpty)
                .accessibilityIdentifier(AccessibilityID.editBoardConfirm)
            }
        }
        .padding(20)
        .frame(width: 320)
    }
}
