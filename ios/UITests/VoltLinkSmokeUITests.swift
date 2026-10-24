import XCTest

/// End-to-end smoke test for the flows that cannot run under `swift test` (SwiftUI
/// launch, first-run vehicle selection, demo mode, and tab navigation).
final class VoltLinkSmokeUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testDemoModeDashboardAndDiagnosticsLoad() {
        let app = XCUIApplication()
        // Force the first-run path even if a previous run selected a vehicle.
        app.launchArguments += ["-selectedVehicleID", "__ui_test_no_selection__"]
        app.launch()

        let startDemo = app.buttons["Start Demo Mode"]
        XCTAssertTrue(startDemo.waitForExistence(timeout: 15), "First-run picker should offer demo mode")
        startDemo.tap()

        XCTAssertTrue(app.staticTexts["Demo mode"].waitForExistence(timeout: 15), "Dashboard header should report demo mode")
        XCTAssertTrue(app.tabBars.buttons["Telemetry"].exists)

        app.tabBars.buttons["Diagnostics"].tap()
        XCTAssertTrue(app.buttons["Scan DTCs"].waitForExistence(timeout: 10), "Diagnostics tab should expose a scan action")
        XCTAssertTrue(app.tabBars.buttons["Settings"].exists)
    }
}
