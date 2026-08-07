import XCTest
@testable import VoltLinkEngine

final class DashboardLayoutTests: XCTestCase {

    func testRawValueRoundTrip() {
        let layout = DashboardLayout.default
        let encoded = layout.rawValue
        let decoded = DashboardLayout(rawValue: encoded)
        XCTAssertEqual(decoded, layout)
    }

    func testChartWidgetRoundTrip() {
        let layout = DashboardLayout(widgets: [
            DashboardWidgetConfig(kind: .chart(series: [.speed, .power]), style: .numeric, size: .large)
        ])
        let decoded = DashboardLayout(rawValue: layout.rawValue)
        XCTAssertEqual(decoded, layout)
        if case .chart(let series) = decoded?.widgets.first?.kind {
            XCTAssertEqual(series, [.speed, .power])
        } else {
            XCTFail("Expected chart kind to round-trip")
        }
    }

    func testInvalidRawValueReturnsNil() {
        XCTAssertNil(DashboardLayout(rawValue: "not json"))
    }

    func testRowPackingPairsAdjacentSmallWidgets() {
        let widgets = [
            DashboardWidgetConfig(kind: .metric(.speed), style: .numeric, size: .small),
            DashboardWidgetConfig(kind: .metric(.aux12V), style: .numeric, size: .small),
            DashboardWidgetConfig(kind: .metric(.power), style: .dial, size: .large)
        ]
        let rows = packDashboardWidgetsIntoRows(widgets)
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows[0].count, 2)
        XCTAssertEqual(rows[1].count, 1)
    }

    func testRowPackingFlushesTrailingSoloSmallWidget() {
        let widgets = [
            DashboardWidgetConfig(kind: .metric(.power), style: .dial, size: .large),
            DashboardWidgetConfig(kind: .metric(.speed), style: .numeric, size: .small)
        ]
        let rows = packDashboardWidgetsIntoRows(widgets)
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows[1].count, 1)
    }
}
