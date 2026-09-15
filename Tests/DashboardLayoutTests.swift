import XCTest
@testable import VoltLinkEngine

final class DashboardLayoutTests: XCTestCase {

    func testSavedLayoutUsesContentSizedRowsWithoutChangingWidgets() throws {
        let saved = DashboardLayout(widgets: [
            DashboardWidgetConfig(kind: .metric(.speed), style: .dial, size: .medium),
            DashboardWidgetConfig(kind: .metric(.soc), style: .bar, size: .large),
            DashboardWidgetConfig(kind: .metric(.aux12V), style: .numeric, size: .medium),
            DashboardWidgetConfig(kind: .chart(series: [.power]), style: .numeric, size: .large)
        ])
        let restored = try XCTUnwrap(DashboardLayout(rawValue: saved.rawValue))
        XCTAssertEqual(restored.widgets, saved.widgets)
        let heights = restored.widgets.map(\.preferredHeight)
        XCTAssertLessThan(heights[1], heights[0], "A bar must not reserve a dial-sized row")
        XCTAssertLessThan(heights[2], heights[0], "A number must not reserve a dial-sized row")
        XCTAssertGreaterThanOrEqual(heights[3], 190, "Keep enough room for chart axes and header")
    }

    func testRawValueRoundTrip() {
        let layout = DashboardLayout.default
        let encoded = layout.rawValue
        let decoded = DashboardLayout(rawValue: encoded)
        XCTAssertEqual(decoded, layout)
    }

    func testDefaultLayoutUsesPackVoltageInsteadOfAuxiliary12V() {
        let metrics = DashboardLayout.default.widgets.compactMap { config -> TelemetryMetric? in
            guard case .metric(let metric) = config.kind else { return nil }
            return metric
        }

        XCTAssertTrue(metrics.contains(.packVoltage))
        XCTAssertFalse(metrics.contains(.aux12V))
    }

    func testChartWidgetRoundTrip() {
        let fixedID = UUID()
        let layout = DashboardLayout(widgets: [
            DashboardWidgetConfig(id: fixedID, kind: .chart(series: [.speed, .power]), style: .numeric, size: .large)
        ])
        let decoded = DashboardLayout(rawValue: layout.rawValue)
        XCTAssertNotNil(decoded)
        if let widget = decoded?.widgets.first {
            XCTAssertEqual(widget.id, fixedID)
            XCTAssertEqual(widget.style, .numeric)
            XCTAssertEqual(widget.size, .large)
            if case .chart(let series) = widget.kind {
                XCTAssertEqual(series, [.speed, .power])
            } else {
                XCTFail("Expected chart kind to round-trip")
            }
        }
    }

    func testInvalidRawValueReturnsNil() {
        XCTAssertNil(DashboardLayout(rawValue: "not json"))
    }

    func testRowPackingPairsAdjacentMediumWidgets() {
        let widgets = [
            DashboardWidgetConfig(kind: .metric(.speed), style: .dial, size: .medium),
            DashboardWidgetConfig(kind: .metric(.power), style: .dial, size: .medium),
            DashboardWidgetConfig(kind: .metric(.soc), style: .dial, size: .large)
        ]
        let rows = packDashboardWidgetsIntoRows(widgets)
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows[0].count, 2) // Speed and Power paired side-by-side
        XCTAssertEqual(rows[1].count, 1) // SoC on second row
    }

    func testRowPackingFlushesTrailingSoloMediumWidget() {
        let widgets = [
            DashboardWidgetConfig(kind: .metric(.power), style: .dial, size: .large),
            DashboardWidgetConfig(kind: .metric(.speed), style: .numeric, size: .medium)
        ]
        let rows = packDashboardWidgetsIntoRows(widgets)
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows[1].count, 1)
    }
}
