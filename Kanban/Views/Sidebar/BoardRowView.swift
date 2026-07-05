import SwiftUI

/// A single sidebar row: emoji (or a default glyph) + name, combined into one queryable element.
struct BoardRowView: View {
    let board: Board

    var body: some View {
        HStack(spacing: 8) {
            Text(board.emoji ?? "🗂️")
            Text(board.name)
        }
        // Fill the full row width (not just the tight text glyphs) BEFORE combining: this keeps
        // the combined accessibility element's frame matching the actual clickable row bounds, so
        // an XCUITest `.click()` (which taps the element's reported frame center) lands on the row.
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        // `.combine`, not `.contain`: see BoardPlaceholderView / RootView for why this matters —
        // `.combine` leaves don't inherit `root-view`'s identifier from their ancestor.
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(AccessibilityID.board(board.name))
    }
}
