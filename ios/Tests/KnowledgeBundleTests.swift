import XCTest
@testable import VoltLinkEngine

@MainActor
final class KnowledgeBundleTests: XCTestCase {
    /// The checked-in bundle must be current: this is what stops an agent from changing
    /// profiles, metrics, or DTC seeds without regenerating the AI reference.
    func testCheckedInBundleConformsAndMatchesSources() {
        let issues = KnowledgeBundle.check(at: bundleURL)
        XCTAssertTrue(issues.isEmpty, issues.joined(separator: "\n"))
    }

    func testGeneratedConceptsCoverRegistryMetricsAndDTCs() {
        let files = KnowledgeBundle.conceptFiles()

        XCTAssertEqual(
            files.keys.filter { $0.hasPrefix("vehicles/") }.count,
            VehicleProfileID.allCases.count,
            "Every registry profile needs exactly one concept"
        )
        XCTAssertEqual(
            files.keys.filter { $0.hasPrefix("telemetry/") }.count,
            TelemetryMetric.allCases.count,
            "Every telemetry metric needs exactly one concept"
        )
        for id in VehicleProfileID.allCases {
            XCTAssertNotNil(files["vehicles/\(id.rawValue).md"], "Missing concept for \(id.rawValue)")
        }
        XCTAssertNotNil(files["telemetry/soc.md"])
        XCTAssertNotNil(files["telemetry/batteryTempMin.md"])
        XCTAssertNotNil(files["diagnostics/P0A80.md"])
    }

    func testEveryGeneratedConceptHasRequiredFrontmatter() {
        for (path, text) in KnowledgeBundle.conceptFiles() {
            let frontmatter = OKFDocument.frontmatter(of: text)
            XCTAssertNotNil(frontmatter, "\(path) is missing frontmatter")
            XCTAssertFalse(frontmatter?.fields["type"]?.isEmpty ?? true, "\(path) has no type")
            XCTAssertFalse(frontmatter?.fields["title"]?.isEmpty ?? true, "\(path) has no title")
            XCTAssertFalse(frontmatter?.fields["description"]?.isEmpty ?? true, "\(path) has no description")
        }
    }

    func testBundleRootDeclaresVersionAndIndexesEveryConcept() throws {
        let files = KnowledgeBundle.conceptFiles()
        let indexes = KnowledgeBundle.indexFiles(in: files)
        let root = try XCTUnwrap(indexes["index.md"])
        let frontmatter = try XCTUnwrap(OKFDocument.frontmatter(of: root))
        XCTAssertEqual(frontmatter.fields["okf_version"], "0.2")

        for path in files.keys {
            XCTAssertTrue(root.contains("(\(path))"), "Root index does not link \(path)")
        }
    }

    func testExportRoundTripsAndDetectsDrift() throws {
        let fileManager = FileManager.default
        let directory = fileManager.temporaryDirectory
            .appendingPathComponent("okf-\(UUID().uuidString)", isDirectory: true)
        defer { try? fileManager.removeItem(at: directory) }

        let result = try KnowledgeBundle.write(to: directory)
        XCTAssertFalse(result.written.isEmpty)
        XCTAssertTrue(KnowledgeBundle.check(at: directory).isEmpty)

        // An edited concept must be reported instead of silently accepted.
        let concept = directory.appendingPathComponent("telemetry/soc.md")
        let original = try String(contentsOf: concept, encoding: .utf8)
        try (original + "\nHand edit that was not regenerated.\n").write(to: concept, atomically: true, encoding: .utf8)

        let issues = KnowledgeBundle.check(at: directory)
        XCTAssertTrue(issues.contains { $0.contains("telemetry/soc.md") }, issues.joined(separator: "\n"))
    }

    func testSlugAndLinkResolution() {
        XCTAssertEqual(OKFDocument.slug("packCurrent"), "pack-current")
        XCTAssertEqual(OKFDocument.slug("batteryTempMin"), "battery-temp-min")
        XCTAssertEqual(OKFDocument.slug("Mini_MiniCooperSE"), "mini-mini-cooper-se")
        XCTAssertEqual(OKFDocument.slug("hkmc_Ioniq5"), "hkmc-ioniq5")

        XCTAssertEqual(OKFDocument.resolve(link: "/telemetry/soc.md", from: "vehicles/mercedesEQA250.md"), "telemetry/soc.md")
        XCTAssertEqual(OKFDocument.resolve(link: "../telemetry/soc.md", from: "vehicles/mercedesEQA250.md"), "telemetry/soc.md")
        XCTAssertEqual(OKFDocument.resolve(link: "soc.md", from: "telemetry/index.md"), "telemetry/soc.md")
    }

    private var bundleURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(KnowledgeBundle.defaultDirectoryName)
    }
}
