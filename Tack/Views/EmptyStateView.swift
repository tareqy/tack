import SwiftUI

/// Shown in the detail pane when there are zero boards. `onCreateBoard` opens the SAME creation
/// sheet as the sidebar's "New Board" toolbar button; `onImportBoards` presents the SAME import
/// open panel as File ▸ Import Boards… (E-02) — restore-onto-a-fresh-machine lands exactly here.
/// The state for both lives in `RootView`.
struct EmptyStateView: View {
    let onCreateBoard: () -> Void
    let onImportBoards: () -> Void

    var body: some View {
        // The system empty-state component (macOS 14+): standard typography, spacing, and
        // dark-mode behavior for free, with the actions grouped apart from the text block.
        ContentUnavailableView {
            Label("No Boards", systemImage: "square.grid.2x2")
        } description: {
            Text("Create a board to start organizing your work.")
        } actions: {
            Button("Create Board…", action: onCreateBoard)
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier(AccessibilityID.emptyStateCreateBoardButton)
            Button("Import from Backup…", action: onImportBoards)
                .accessibilityIdentifier(AccessibilityID.emptyStateImportButton)
        }
    }
}
