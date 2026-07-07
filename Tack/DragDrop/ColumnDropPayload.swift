import Foundation
import CoreTransferable
import UniformTypeIdentifiers

/// The drop-side payload for a list column's body/footer zone, which must accept BOTH card drags
/// (append to that list) and list drags (column reorder) through ONE `.dropDestination`.
///
/// Why one dual-type destination instead of two typed ones — both alternatives were disproven
/// EMPIRICALLY against real XCUITest drags during M5 (see ListColumnView's coexistence doc):
/// 1. A child `.dropDestination(for: CardTransfer.self)` on the footer consumes every drop landing
///    on its region regardless of drag type, but only handles its own — ListTransfer drops on the
///    column body were silently swallowed (list reorder regressed).
/// 2. Stacking `.dropDestination(for: ListTransfer.self)` + `.dropDestination(for:
///    CardTransfer.self)` on one view does not dispatch by payload type — the first-applied
///    modifier shadows the second, which never fires (cross-list card drops regressed).
///
/// Import-only: drag SOURCES still export plain `CardTransfer` / `ListTransfer` (their
/// `CodableRepresentation` encodes JSON via `JSONEncoder` by default); this type decodes those
/// same bytes back on the drop side, keyed by which UTType arrived.
enum ColumnDropPayload: Transferable {
    case card(CardTransfer)
    case list(ListTransfer)

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(importedContentType: .tackCard) { data in
            ColumnDropPayload.card(try JSONDecoder().decode(CardTransfer.self, from: data))
        }
        DataRepresentation(importedContentType: .tackList) { data in
            ColumnDropPayload.list(try JSONDecoder().decode(ListTransfer.self, from: data))
        }
    }
}
