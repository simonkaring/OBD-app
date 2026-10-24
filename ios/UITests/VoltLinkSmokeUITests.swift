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

        // The demo charging log ships one recorded session, so its row must draw a
        // charge-speed sparkline instead of only the numeric peak.
        app.tabBars.buttons["Log"].tap()
        app.segmentedControls.buttons["Charging"].tap()
        let speedSparkline = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@", "Charging speed over time"))
            .firstMatch
        XCTAssertTrue(speedSparkline.waitForExistence(timeout: 10), "Charging log rows should chart charge speed")

        let rowAverage = app.staticTexts
            .matching(NSPredicate(format: "label BEGINSWITH %@", "Avg: "))
            .firstMatch
        XCTAssertTrue(rowAverage.waitForExistence(timeout: 10), "Charging log rows should report average speed")

        // Starting a simulated DC charge must surface elapsed time and average speed
        // on the Charging tab's headline card.
        app.tabBars.buttons["Charging"].tap()
        app.buttons["Simulate DC Fast Charging (100 kW)"].tap()
        XCTAssertTrue(app.staticTexts["Elapsed"].waitForExistence(timeout: 15), "Charging tab should show elapsed time")
        XCTAssertTrue(app.staticTexts["Avg speed"].waitForExistence(timeout: 15), "Charging tab should show average speed")
    }
}
