import SwiftUI

/// Shown in the detail pane when there are zero boards. `onCreateBoard` opens the SAME creation
/// sheet as the sidebar's "New Board" toolbar button — the state for it lives in `RootView`.
struct EmptyStateView: View {
    let onCreateBoard: () -> Void

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
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}
