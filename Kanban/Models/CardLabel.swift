import Foundation
import SwiftData

@Model
final class CardLabel {
    @Attribute(.unique) var colorName: String  // LabelColor rawValue
    var cards: [Card]

    init(colorName: String, cards: [Card] = []) {
        self.colorName = colorName
        self.cards = cards
    }

    var color: LabelColor? { LabelColor(rawValue: colorName) }
}
