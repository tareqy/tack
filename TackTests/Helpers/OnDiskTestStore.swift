import Foundation
import SwiftData
@testable import Tack

/// On-disk equivalent of `TestContainer(withUndo: true)` — promoted from the private per-file
/// copies in ImportUndoOnDiskTests/ChecklistUndoOnDiskTests at the THIRD user
/// (AreaUndoOnDiskTests), per those files' own "promotion can wait for a third user" note:
/// sqlite under a unique temp dir, UndoManager with `groupsByEvent = false` (headless — no run
/// loop to open event groups).
@MainActor
struct OnDiskTestStore {
    let directory: URL
    let container: ModelContainer
    let context: ModelContext
    let store: BoardStore
    let undoManager: UndoManager

    init(directoryPrefix: String) throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(directoryPrefix)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let schema = Schema(versionedSchema: TackSchemaV1.self)
        let configuration = ModelConfiguration(schema: schema, url: directory.appendingPathComponent("spike.sqlite"))
        container = try ModelContainer(for: schema, migrationPlan: TackMigrationPlan.self,
                                       configurations: [configuration])
        context = container.mainContext
        let manager = UndoManager()
        manager.groupsByEvent = false
        context.undoManager = manager
        undoManager = manager
        store = BoardStore(context: context)
    }

    /// Best-effort (the original files' caveat verbatim): no public close API, so the sqlite
    /// file is unlinked while open — a harmless stderr line, assertions already ran.
    func tearDown() {
        try? FileManager.default.removeItem(at: directory)
    }
}
