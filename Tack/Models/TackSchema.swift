import SwiftData

enum TackSchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version = Schema.Version(1, 0, 0)

    static var models: [any PersistentModel.Type] {
        [Board.self, BoardList.self, Card.self, CardLabel.self, ChecklistItem.self, Area.self]
    }
}

enum TackMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [TackSchemaV1.self]
    }

    static var stages: [MigrationStage] {
        []
    }
}
