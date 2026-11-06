import Foundation
import SwiftData

/// Versioned schema for VoltLink's persistent history.
///
/// Keeping the versions named makes model changes reviewable. Additive changes such as
/// V2's new `ChargingSampleModel` entity and empty-default relationship are handled by
/// SwiftData's inferred lightweight migration: the container opens the current version
/// without an explicit `SchemaMigrationPlan`.
///
/// V3 also drops `SavedDTCModel`, which never received a row. Removing an entity is a
/// lightweight change too, so stores written by earlier versions still open without a plan.
///
/// Do not add a plan whose versions share the same `@Model` classes — Core Data aborts
/// (`NSPersistentStoreCoordinator addPersistentStore`) instead of migrating, which crashes
/// the app before the in-memory fallback can run. A future destructive rename needs
/// distinct legacy model copies and a real migration stage.
public enum VoltLinkSchemaV1: VersionedSchema {
    public static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }

    public static var models: [any PersistentModel.Type] {
        [TripModel.self, TelemetryPointModel.self, ChargingSessionModel.self]
    }
}

/// V2 adds `ChargingSampleModel` for the power-vs-SOC charging curve.
public enum VoltLinkSchemaV2: VersionedSchema {
    public static var versionIdentifier: Schema.Version { Schema.Version(2, 0, 0) }

    public static var models: [any PersistentModel.Type] {
        [TripModel.self, TelemetryPointModel.self, ChargingSessionModel.self, ChargingSampleModel.self]
    }
}

/// V3 adds `BatteryHealthSampleModel` for state-of-health history. A new entity is additive,
/// so V2 stores still open through inferred lightweight migration.
public enum VoltLinkSchemaV3: VersionedSchema {
    public static var versionIdentifier: Schema.Version { Schema.Version(3, 0, 0) }

    public static var models: [any PersistentModel.Type] {
        [
            TripModel.self, TelemetryPointModel.self, ChargingSessionModel.self, ChargingSampleModel.self,
            BatteryHealthSampleModel.self,
        ]
    }
}

/// The schema the app container opens. Bumping this is the single switch that opts the
/// store into a new version.
public enum VoltLinkCurrentSchema {
    public static let versioned = VoltLinkSchemaV3.self
}
