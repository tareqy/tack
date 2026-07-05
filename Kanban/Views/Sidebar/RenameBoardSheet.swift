import SwiftUI

/// Small sheet for renaming a board, opened from its sidebar row's context menu.
struct RenameBoardSheet: View {
    let board: Board
    let store: BoardStore

    @Environment(\.dismiss) private var dismiss
    @State private var name: String

    init(board: Board, store: BoardStore) {
        self.board = board
        self.store = store
        _name = State(initialValue: board.name)
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Rename Board")
                .font(.headline)

            TextField("Board name", text: $name)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier(AccessibilityID.renameBoardField)

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                Button("Rename") {
                    store.renameBoard(board, to: trimmedName)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(trimmedName.isEmpty)
                .accessibilityIdentifier(AccessibilityID.renameBoardConfirm)
            }
        }
        .padding(20)
        .frame(width: 320)
    }
}
