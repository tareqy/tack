import Foundation
import SwiftData

enum ModelContainerFactory {
    /// Default on-disk store used by the running app.
    static func production() throws -> ModelContainer {
        let schema = Schema(versionedSchema: KanbanSchemaV1.self)
        let configuration = ModelConfiguration(schema: schema)
        return try ModelContainer(
            for: schema,
            migrationPlan: KanbanMigrationPlan.self,
            configurations: [configuration]
        )
    }

    /// In-memory store used by unit tests (and, later, --uitest launches wired up in M3).
    static func inMemory() throws -> ModelContainer {
        let schema = Schema(versionedSchema: KanbanSchemaV1.self)
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(
            for: schema,
            migrationPlan: KanbanMigrationPlan.self,
            configurations: [configuration]
        )
    }

    /// On-disk store for UI-test launches: `Application Support/UITest/<storeName>.sqlite`
    /// inside the app sandbox container. When `reset` is true the store (and its `-wal`/`-shm`
    /// sidecars) is deleted first so the launch starts from a clean, freshly-seeded state; when
    /// false the existing store is reopened so mutations survive a relaunch. Same schema and
    /// migration plan as `production()`.
    static func uiTest(storeName: String, reset: Bool) throws -> ModelContainer {
        let fileManager = FileManager.default
        let appSupport = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = appSupport.appendingPathComponent("UITest", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let storeURL = directory.appendingPathComponent("\(storeName).sqlite")

        if reset {
            for suffix in ["", "-wal", "-shm"] {
                try? fileManager.removeItem(at: directory.appendingPathComponent("\(storeName).sqlite\(suffix)"))
            }
        }

        let schema = Schema(versionedSchema: KanbanSchemaV1.self)
        let configuration = ModelConfiguration(schema: schema, url: storeURL)
        return try ModelContainer(
            for: schema,
            migrationPlan: KanbanMigrationPlan.self,
            configurations: [configuration]
        )
    }
}
