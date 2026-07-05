/// Fixed 8-color label palette (PRD §4.4, LB-01). Backed by CardLabel.colorName.
enum LabelColor: String, CaseIterable, Codable {
    case red
    case orange
    case yellow
    case green
    case blue
    case indigo
    case purple
    case pink
}
