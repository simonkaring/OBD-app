import SwiftData
import XCTest

@testable import VoltLinkEngine

/// CloudKit refuses a container whose models it cannot mirror. These assertions encode the
/// two rules that are easy to break while editing a model — every attribute needs a default
/// (or optionality), and every relationship must be optional — without needing an iCloud
/// entitlement in the test host.
final class CloudSyncSchemaTests: XCTestCase {
    func testCurrentSchemaShipsEveryModel() {
        let names = Set(Schema(versionedSchema: VoltLinkCurrentSchema.versioned).entities.map(\.name))
        XCTAssertTrue(names.contains("TripModel"))
        XCTAssertTrue(names.contains("TelemetryPointModel"))
        XCTAssertTrue(names.contains("ChargingSessionModel"))
        XCTAssertTrue(names.contains("ChargingSampleModel"))
        XCTAssertFalse(names.contains("SavedDTCModel"), "The never-written DTC entity was dropped from the active schema")
        XCTAssertTrue(names.contains("BatteryHealthSampleModel"))
    }

    func testEveryAttributeHasADefaultOrIsOptional() {
        let schema = Schema(versionedSchema: VoltLinkCurrentSchema.versioned)
        for entity in schema.entities {
            for attribute in entity.attributes {
                XCTAssertTrue(
                    attribute.isOptional || attribute.defaultValue != nil,
                    "\(entity.name).\(attribute.name) needs a default value or optional type before the store can sync with CloudKit")
            }
        }
    }

    func testEveryRelationshipIsOptional() {
        let schema = Schema(versionedSchema: VoltLinkCurrentSchema.versioned)
        for entity in schema.entities {
            for relationship in entity.relationships {
                XCTAssertTrue(
                    relationship.isOptional,
                    "\(entity.name).\(relationship.name) must be optional before the store can sync with CloudKit")
                XCTAssertNotNil(
                    relationship.inverseName,
                    "\(entity.name).\(relationship.name) needs an inverse relationship for CloudKit")
            }
        }
    }
}
