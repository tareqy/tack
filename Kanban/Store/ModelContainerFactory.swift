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
}
