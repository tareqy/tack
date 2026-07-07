import SwiftUI

/// A thin accent-colored bar previewing where a dragged card will land, shown while a
/// `.dropDestination` reports `isTargeted`. Extracted from the M2 spike's inline indicator so the
/// production card rows and the list-body footer append zone share one definition.
///
/// Horizontal (a 3pt-tall bar), matching the vertical card stack. The list-reorder indicator in
/// `ListColumnView` is its vertical twin (a 3pt-wide bar between columns) and stays inline there —
/// the two orientations don't share enough to be worth a single parameterized view.
struct InsertionIndicator: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 1.5)
            .fill(Color.accentColor)
            .frame(height: 3)
    }
}
