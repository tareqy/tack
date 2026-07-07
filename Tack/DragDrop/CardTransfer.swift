import Foundation
import CoreTransferable
import UniformTypeIdentifiers

extension UTType {
    /// Custom drag payload type for Tack cards. Declared in the app's Info.plist
    /// (`UTExportedTypeDeclarations`, conforms to `public.data`) via project.yml.
    static let tackCard = UTType(exportedAs: "com.tareq.tack.card")
}

/// The payload carried by a card drag. Only the card's identity travels through the drag
/// session; the drop side re-resolves the live `Card` from the store by id and routes the
/// mutation through `BoardStore.moveCard(_:to:at:)` — no model objects cross the pasteboard.
struct CardTransfer: Codable, Transferable {
    let cardID: UUID

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .tackCard)
    }
}
