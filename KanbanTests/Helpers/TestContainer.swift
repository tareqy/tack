import Foundation
import SwiftData
@testable import Kanban

/// Builds an in-memory ModelContainer + ModelContext + BoardStore for tests.
/// Pass `withUndo: true` to attach an UndoManager to the context for undo/redo tests.
@MainActor
struct TestContainer {
    let container: ModelContainer
    let context: ModelContext
    let store: BoardStore
    let undoManager: UndoManager?

    init(withUndo: Bool = false) {
        container = try! ModelContainerFactory.inMemory()
        context = container.mainContext
        if withUndo {
            let manager = UndoManager()
            // We manage grouping boundaries explicitly per BoardStore operation, so disable
            // the run-loop/event based auto-grouping (there is no NSApplication event loop
            // driving it in a headless unit test host anyway).
            manager.groupsByEvent = false
            context.undoManager = manager
            undoManager = manager
        } else {
            undoManager = nil
        }
        store = BoardStore(context: context)
    }
}
