import Foundation
import CoreTransferable
import UniformTypeIdentifiers

extension UTType {
    /// Custom drag payload type for Kanban list columns. Declared in the app's Info.plist
    /// (`UTExportedTypeDeclarations`, conforms to `public.data`) via project.yml — same mechanism
    /// as `UTType.kanbanCard`.
    static let kanbanList = UTType(exportedAs: "com.tareq.kanban.list")
}

/// The payload carried by a list-column drag (M4 reordering). Only the list's identity travels
/// through the drag session, mirroring `CardTransfer`: the drop side re-resolves the live
/// `BoardList` from the board by id and routes the mutation through `BoardStore.moveList(_:to:)`.
struct ListTransfer: Codable, Transferable {
    let listID: UUID

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .kanbanList)
    }
}
