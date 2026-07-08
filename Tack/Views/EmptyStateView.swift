import SwiftUI

/// Shown in the detail pane when there are zero boards. `onCreateBoard` opens the SAME creation
/// sheet as the sidebar's "New Board" toolbar button; `onImportBoards` presents the SAME import
/// open panel as File ▸ Import Boards… (E-02) — restore-onto-a-fresh-machine lands exactly here.
/// The state for both lives in `RootView`.
struct EmptyStateView: View {
    let onCreateBoard: () -> Void
    let onImportBoards: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "square.grid.2x2")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("No boards yet")
                .font(.title2)
                .bold()
            Text("Create a board to start organizing your work.")
                .foregroundStyle(.secondary)
            Button("Create your first board", action: onCreateBoard)
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier(AccessibilityID.emptyStateCreateBoardButton)
            Button("Import from Backup…", action: onImportBoards)
                .accessibilityIdentifier(AccessibilityID.emptyStateImportButton)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}
