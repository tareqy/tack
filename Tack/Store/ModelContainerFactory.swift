import Foundation
import SwiftData

enum ModelContainerFactory {
    /// Default on-disk store used by the running app.
    static func production() throws -> ModelContainer {
        let schema = Schema(versionedSchema: TackSchemaV1.self)
        let configuration = ModelConfiguration(schema: schema)
        return try ModelContainer(
            for: schema,
            migrationPlan: TackMigrationPlan.self,
            configurations: [configuration]
        )
    }

    /// In-memory store used by unit tests (and, later, --uitest launches wired up in M3).
    static func inMemory() throws -> ModelContainer {
        let schema = Schema(versionedSchema: TackSchemaV1.self)
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(
            for: schema,
            migrationPlan: TackMigrationPlan.self,
            configurations: [configuration]
        )
    }

    /// On-disk store for UI-test launches: `Application Support/UITest/<storeName>.sqlite`
    /// inside the app sandbox container. When `reset` is true the store (and its `-wal`/`-shm`
    /// sidecars) is deleted first so the launch starts from a clean, freshly-seeded state; when
    /// false the existing store is reopened so mutations survive a relaunch. Same schema and
    /// migration plan as `production()`.
    /// `Application Support/UITest/` inside the sandbox container — created if needed. Home to
    /// every `--uitest` on-disk store AND the `--export-to` export file (see `TackApp`), so both
    /// resolve the same directory the same way.
    static func uiTestDirectory() throws -> URL {
        let fileManager = FileManager.default
        let appSupport = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = appSupport.appendingPathComponent("UITest", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    static func uiTest(storeName: String, reset: Bool) throws -> ModelContainer {
        let fileManager = FileManager.default
        let directory = try uiTestDirectory()
        let storeURL = directory.appendingPathComponent("\(storeName).sqlite")

        if reset {
            for suffix in ["", "-wal", "-shm"] {
                try? fileManager.removeItem(at: directory.appendingPathComponent("\(storeName).sqlite\(suffix)"))
            }
        }

        let schema = Schema(versionedSchema: TackSchemaV1.self)
        let configuration = ModelConfiguration(schema: schema, url: storeURL)
        return try ModelContainer(
            for: schema,
            migrationPlan: TackMigrationPlan.self,
            configurations: [configuration]
        )
    }
}
