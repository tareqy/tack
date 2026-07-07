import SwiftUI

/// Maps the pure `LabelColor` model enum onto a concrete SwiftUI `Color` for chips/dots. Kept as an
/// extension in `Views/` (not on the enum's own declaration in `Models/`) so `LabelColor.swift`
/// itself stays SwiftUI-free, matching `DueDateStatus`'s "no SwiftData/SwiftUI imports" convention.
extension LabelColor {
    var swatchColor: Color {
        switch self {
        case .red: .red
        case .orange: .orange
        case .yellow: .yellow
        case .green: .green
        case .blue: .blue
        case .indigo: .indigo
        case .purple: .purple
        case .pink: .pink
        }
    }
}
