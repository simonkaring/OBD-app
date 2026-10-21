import Foundation
import SwiftData

/// Versioned schema for VoltLink's persistent history.
///
/// Every persisted model belongs to a `VersionedSchema` so future field or relationship
/// changes can ship with a `SchemaMigrationPlan` stage instead of failing container
/// creation (which previously dropped the user into the in-memory fallback and lost
/// their recorded trips).
public enum VoltLinkSchemaV1: VersionedSchema {
    public static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }

    public static var models: [any PersistentModel.Type] {
        [TripModel.self, TelemetryPointModel.self, ChargingSessionModel.self, SavedDTCModel.self]
    }
}

public enum VoltLinkMigrationPlan: SchemaMigrationPlan {
    public static var schemas: [any VersionedSchema.Type] { [VoltLinkSchemaV1.self] }

    /// Nothing to migrate between V1 and itself. When V2 lands, add its schema here and
    /// append a `.lightweight` or `.custom` stage that maps V1 -> V2.
    public static var stages: [MigrationStage] { [] }
}
