import SwiftUI

/// Detail-pane placeholder for a selected board. M4 replaces this with the real lists UI.
struct BoardPlaceholderView: View {
    let board: Board

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("\(board.emoji ?? "🗂️") \(board.name)")
                .font(.largeTitle)
            Text("Lists arrive in M4")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding()
        // `.combine` (not `.contain`): a single element whose accessibility label concatenates
        // both texts, so a test can assert "board-detail shows <name>" by checking this element's
        // label — and, per the M2 finding, `.combine` leaves don't inherit an ancestor's
        // identifier the way `.contain` containers do (root-view sits above this in RootView).
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(AccessibilityID.boardDetail)
    }
}
