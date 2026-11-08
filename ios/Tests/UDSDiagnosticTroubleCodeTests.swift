import XCTest

@testable import VoltLinkEngine

@MainActor
private final class ModuleConnection: OBDConnectionProtocol {
    var state: BLEConnectionState = .disconnected
    weak var delegate: OBDConnectionDelegate?
    private(set) var sentCommands: [String] = []
    var responses: [String: String] = [:]

    func connect(peripheralName: String?) {}
    func disconnect() { state = .disconnected }

    func sendCommand(_ command: String, completion: (@MainActor @Sendable (Result<String, Error>) -> Void)?) {
        sentCommands.append(command)
        completion?(.success(responses[command] ?? "OK\r>"))
    }
}

@MainActor
final class UDSDiagnosticTroubleCodeTests: XCTestCase {
    func testMercedesBytesRenderAsTechnicianIdentifier() {
        let bytes = ISO15765Parser.hexBytes("98 33 01 8F")
        let code = UDSDiagnosticTroubleCode(
            saeCode: UDSDiagnostics.saeCode(first: bytes[0], second: bytes[1]),
            failureType: bytes[2], status: bytes[3])

        XCTAssertEqual(code.code, "B1833-01")
        XCTAssertEqual(UDSDiagnostics.failureTypeDescription(0x01), "General electrical failure")
        XCTAssertEqual(UDSDiagnostics.statusDescriptions(0x8F).first, "Test failed")
        XCTAssertTrue(UDSDiagnostics.statusDescriptions(0x8F).contains("Confirmed"))
    }

    func testPayloadDecodesEveryRecord() {
        let records = UDSDiagnostics.codes(fromPayload: "59 02 09 0D E6 11 2F 15 4B 00 24")
        XCTAssertEqual(records?.map(\.code), ["P0DE6-11", "P154B-00"])
        XCTAssertEqual(records?.first?.status, 0x2F)
    }

    func testPositiveResponseWithoutFaultsIsEmptyAndNegativeIsNil() {
        XCTAssertEqual(UDSDiagnostics.codes(fromPayload: "59 02 09")?.count, 0)
        XCTAssertNil(UDSDiagnostics.codes(fromPayload: "7F 19 31"))
        XCTAssertEqual(UDSDiagnostics.negativeResponseCode(fromPayload: "7F 19 31"), 0x31)
    }

    func testManufacturerFailureSubTypeStaysVisible() {
        XCTAssertTrue(UDSDiagnostics.failureTypeDescription(0xFC).contains("0xFC"))
        XCTAssertEqual(UDSDiagnostics.statusDescriptions(0).first, "No status flags set")
    }

    func testEQACommunityProfileDeclaresModuleAddressing() {
        let modules = MercedesEQAOBDbProfile().diagnosticModules
        XCTAssertEqual(modules.map(\.requestHeader), ["7E5", "7E2", "624"])
        XCTAssertEqual(modules.map(\.responseHeader), ["7ED", "7EA", "5A4"])
    }

    func testModuleScanAddsUDSFaultWithModuleAndStatus() {
        let connection = ModuleConnection()
        connection.responses["03"] = "43 00 00 00 00 00\r>"
        connection.responses["07"] = "47 00\r>"
        connection.responses["1902FF"] = "59 02 09 0D E6 11 2F\r>"
        let scanner = DTCScannerService()
        let module = DiagnosticModule(name: "High-voltage battery", requestHeader: "7E5", responseHeader: "7ED")

        scanner.scanDTCs(connection: connection, modules: [module])

        XCTAssertEqual(scanner.scannedCodes.map(\.code), ["P0DE6-11"])
        XCTAssertEqual(scanner.scannedCodes.first?.moduleName, "High-voltage battery")
        XCTAssertEqual(scanner.scannedCodes.first?.failureTypeDescription, "Circuit short to ground")
        XCTAssertEqual(scanner.scannedCodes.first?.statusDescriptions?.contains("Confirmed"), true)
        XCTAssertTrue(connection.sentCommands.contains("AT CRA 7ED"))
        XCTAssertTrue(connection.sentCommands.contains("AT SH 7E5"))
        XCTAssertTrue(scanner.scanSucceeded)
        XCTAssertNil(scanner.moduleScanNotice)
    }

    func testSameCodeFromTwoModulesStaysDistinct() {
        let connection = ModuleConnection()
        connection.responses["03"] = "43 00 00 00 00 00\r>"
        connection.responses["07"] = "47 00\r>"
        connection.responses["1902FF"] = "59 02 09 15 4B 00 24\r>"
        let scanner = DTCScannerService()
        let modules = [
            DiagnosticModule(name: "High-voltage battery", requestHeader: "7E5", responseHeader: "7ED"),
            DiagnosticModule(name: "Drive unit", requestHeader: "624", responseHeader: "5A4"),
        ]

        scanner.scanDTCs(connection: connection, modules: modules)

        XCTAssertEqual(scanner.scannedCodes.count, 2)
        XCTAssertEqual(scanner.scannedCodes.map(\.moduleName), ["High-voltage battery", "Drive unit"])
        XCTAssertEqual(Set(scanner.scannedCodes.map(\.id)).count, 2)
    }

    func testSilentModuleIsReportedNotTreatedAsHealthy() {
        let connection = ModuleConnection()
        connection.responses["03"] = "43 00 00 00 00 00\r>"
        connection.responses["07"] = "47 00\r>"
        connection.responses["1902FF"] = "NO DATA\r>"
        let scanner = DTCScannerService()
        let module = DiagnosticModule(name: "Drive unit", requestHeader: "624", responseHeader: "5A4")

        scanner.scanDTCs(connection: connection, modules: [module])

        XCTAssertTrue(scanner.scannedCodes.isEmpty)
        XCTAssertEqual(scanner.moduleScanNotice, "No fault memory from Drive unit.")
    }

    func testFullMaskRejectionRetriesConfirmedOnly() {
        let connection = ModuleConnection()
        connection.responses["03"] = "43 00 00 00 00 00\r>"
        connection.responses["07"] = "47 00\r>"
        connection.responses["1902FF"] = "7F 19 31\r>"
        connection.responses["190208"] = "59 02 08 15 4B 00 24\r>"
        let scanner = DTCScannerService()
        let module = DiagnosticModule(name: "Drive unit", requestHeader: "624", responseHeader: "5A4")

        scanner.scanDTCs(connection: connection, modules: [module])

        XCTAssertEqual(scanner.scannedCodes.map(\.code), ["P154B-00"])
        XCTAssertTrue(connection.sentCommands.contains("190208"))
        XCTAssertNil(scanner.moduleScanNotice)
    }

    func testCodeWithoutBundledTextKeepsItsExactIdentifier() {
        let database = DTCLocalDatabase.shared
        let unknown = database.lookupUDS(saeCode: "P0FF1", failureType: 0xFC, module: "Test module")

        XCTAssertEqual(unknown.code, "P0FF1-FC")
        XCTAssertTrue(unknown.title.contains("Manufacturer fault"))
        XCTAssertTrue(unknown.description.contains("No description is bundled"))
        XCTAssertEqual(unknown.moduleName, "Test module")
    }

    func testImportedCodePackAddsModuleText() throws {
        let database = DTCLocalDatabase.shared
        let pack = """
            {"schema": 1, "manufacturer": "MERCEDES", "codes": [
              {"code": "P9ABC", "title": "Imported module fault",
               "category": "Powertrain", "severity": "Critical",
               "description": "Imported description.", "possibleFixes": ["Arrange service"]}
            ]}
            """

        XCTAssertEqual(try database.importPack(data: Data(pack.utf8)), 1)

        let imported = database.lookupUDS(saeCode: "p9abc", failureType: 0x00, status: 0x0F, module: "DC charger")
        XCTAssertEqual(imported.code, "P9ABC-00")
        XCTAssertEqual(imported.title, "Imported module fault")
        XCTAssertEqual(imported.possibleFixes, ["Arrange service"])
        XCTAssertEqual(imported.statusDescriptions, ["Test failed", "Failed this operation cycle", "Pending", "Confirmed"])
    }

    func testCodePackSchemaIsChecked() {
        let database = DTCLocalDatabase.shared
        let pack = """
            {"schema": 2, "codes": []}
            """
        XCTAssertThrowsError(try database.importPack(data: Data(pack.utf8)))
    }
}
