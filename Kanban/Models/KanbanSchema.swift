import SwiftData

enum KanbanSchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version = Schema.Version(1, 0, 0)

    static var models: [any PersistentModel.Type] {
        [Board.self, BoardList.self, Card.self, CardLabel.self]
    }
}

enum KanbanMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [KanbanSchemaV1.self]
    }

    static var stages: [MigrationStage] {
        []
    }
}
