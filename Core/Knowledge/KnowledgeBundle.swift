import Foundation

/// Builds and validates the checked-in `knowledge/` Open Knowledge Format bundle.
/// Vehicle profiles, telemetry metrics, and curated DTCs are generated from the same
/// Swift and seed data the app uses, so the bundle cannot silently describe stale behavior.
public enum KnowledgeBundle {
    public static let okfVersion = "0.2"
    public static let generatedBy = "voltlink-okf/1.0"
    public static let defaultDirectoryName = "knowledge"

    /// Directories owned entirely by the generator; files here that no longer have a
    /// concept are removed on export. Hand-authored concepts live in `architecture/`.
    private static let generatedDirectories = ["vehicles", "telemetry", "diagnostics"]
    private static let rootSections: [(directory: String, heading: String)] = [
        ("architecture", "Architecture"),
        ("vehicles", "Vehicle Profiles"),
        ("telemetry", "Telemetry Metrics"),
        ("diagnostics", "Diagnostic Trouble Codes"),
    ]

    public struct ExportResult: Sendable {
        public let written: [String]
        public let removed: [String]
    }

    // MARK: - Generated concepts

    /// Every generated concept rendered as `bundle-relative path -> file contents`.
    public static func conceptFiles() -> [String: String] {
        var files: [String: String] = [:]
        for concept in profileConcepts() + metricConcepts() + dtcConcepts() {
            files[concept.path] = concept.markdown
        }
        return files
    }

    private static func profileConcepts() -> [OKFConcept] {
        let titles = profileTitles()
        let modelsByProfile = Dictionary(grouping: VehicleCatalog.allModels, by: \.profileID)
        let orderedIDs = VehicleProfileID.allCases.sorted { lhs, rhs in
            let left = titles[lhs] ?? lhs.rawValue
            let right = titles[rhs] ?? rhs.rawValue
            let comparison = left.localizedStandardCompare(right)
            return comparison == .orderedSame ? lhs.rawValue < rhs.rawValue : comparison == .orderedAscending
        }

        return orderedIDs.map { id in
            let profile = id.makeProfile()
            let models = modelsByProfile[id] ?? []
            let metrics = sortedMetrics(profile.supportedMetrics)
            let title = titles[id] ?? id.displayName
            let polling = profile.pollingCommands
            let initialization = profile.initializationCommands

            var body = [
                "# Profile",
                "",
                "| Attribute | Value |",
                "| --- | --- |",
                "| Registry ID | `\(id.rawValue)` |",
                "| Display name | \(title) |",
                "| Electric vehicle | \(profile.isElectricVehicle ? "Yes" : "No") |",
                "| Usable battery capacity | \(number(profile.batteryUsableCapacityKWh)) kWh |",
                "| Catalog models | \(models.count) |",
                "| Polling commands | \(polling.count) |",
            ]

            if !metrics.isEmpty {
                body.append("")
                body.append("# Supported Metrics")
                body.append("")
                for metric in metrics {
                    body.append("- [\(metric.displayName)](/telemetry/\(metric.rawValue).md) — `\(metric.rawValue)` (\(metric.unitSymbol))")
                }
            }

            body.append("")
            body.append("# Polling Commands")
            body.append("")
            if polling.isEmpty {
                body.append("This profile has no polling commands.")
            } else {
                body.append("```text")
                body.append(contentsOf: polling)
                body.append("```")
            }

            if !initialization.isEmpty {
                body.append("")
                body.append("# Initialization Commands")
                body.append("")
                body.append("```text")
                body.append(contentsOf: initialization)
                body.append("```")
            }

            if !models.isEmpty {
                body.append("")
                body.append("# Catalog Coverage")
                body.append("")
                for model in models.prefix(8) {
                    body.append("- \(model.brandName) \(model.modelName) · \(model.years) · \(model.telemetrySupport.displayName)")
                }
                if models.count > 8 {
                    body.append("- …and \(models.count - 8) more catalog entries")
                }
            }

            return OKFConcept(
                path: "vehicles/\(id.rawValue).md",
                type: "Vehicle Profile",
                title: title,
                description: "\(title) vehicle profile with \(polling.count) polling commands and \(metrics.count) telemetry metrics.",
                tags: ["vehicle-profile", profile.isElectricVehicle ? "ev" : "ice"],
                sources: [
                    .init(id: "registry", resource: "../Core/Vehicles/VehicleProfileRegistry.swift", title: "Vehicle profile registry"),
                    .init(id: "catalog", resource: "../Data/Seed/vehicle_catalog.json", title: "Bundled vehicle catalog"),
                ],
                generatedBy: generatedBy,
                body: body.joined(separator: "\n")
            )
        }
    }

    private static func metricConcepts() -> [OKFConcept] {
        let titles = profileTitles()
        let coverage: [(id: VehicleProfileID, metrics: Set<TelemetryMetric>)] = VehicleProfileID.allCases.map { id in
            (id, expandedMetrics(id.makeProfile().supportedMetrics))
        }

        return TelemetryMetric.allCases.sorted { $0.rawValue < $1.rawValue }.map { metric in
            let supporters =
                coverage
                .filter { $0.metrics.contains(metric) }
                .map(\.id)
                .sorted { lhs, rhs in
                    (titles[lhs] ?? lhs.rawValue) < (titles[rhs] ?? rhs.rawValue)
                }

            var body = [
                "# Definition",
                "",
                "`\(metric.displayName)` (`\(metric.rawValue)`) is a telemetry metric reported in `\(metric.unitSymbol)`.",
                "",
                "# Range",
                "",
                "| Attribute | Value |",
                "| --- | --- |",
                "| Unit | `\(metric.unitSymbol)` |",
                "| Typical range | \(range(metric.defaultRange)) |",
                "| Decimal places | \(metric.decimalPlaces) |",
            ]

            let notes = metricNotes(metric)
            if !notes.isEmpty {
                body.append("")
                body.append("# Notes")
                body.append("")
                body.append(contentsOf: notes.map { "- \($0)" })
            }

            body.append("")
            body.append("# Produced By")
            body.append("")
            if supporters.isEmpty {
                body.append("No vehicle profile currently advertises this metric.")
            } else {
                for id in supporters {
                    body.append("- [\(titles[id] ?? id.displayName)](/vehicles/\(id.rawValue).md)")
                }
            }

            return OKFConcept(
                path: "telemetry/\(metric.rawValue).md",
                type: "Telemetry Metric",
                title: metric.displayName,
                description: "\(metric.displayName) telemetry metric in \(metric.unitSymbol), "
                    + (supporters.isEmpty
                        ? "not produced by any current profile." : "produced by \(supporters.count) vehicle profile\(supporters.count == 1 ? "" : "s")."),
                tags: ["telemetry-metric", TelemetryMetric.eqaCommunityMetrics.contains(metric) ? "experimental" : "core"],
                sources: [
                    .init(id: "metric-catalog", resource: "../Core/Telemetry/TelemetryMetric.swift", title: "Telemetry metric catalog")
                ],
                generatedBy: generatedBy,
                body: body.joined(separator: "\n")
            )
        }
    }

    private static func dtcConcepts() -> [OKFConcept] {
        loadCuratedDTCs().sorted { $0.code < $1.code }.map { dtc in
            var body = ["# Meaning", "", dtc.description]

            if !dtc.symptoms.isEmpty {
                body.append("")
                body.append("# Symptoms")
                body.append("")
                body.append(contentsOf: dtc.symptoms.map { "- \($0)" })
            }

            if !dtc.possibleFixes.isEmpty {
                body.append("")
                body.append("# Possible Fixes")
                body.append("")
                body.append(contentsOf: dtc.possibleFixes.map { "- \($0)" })
            }

            body.append("")
            body.append("# Classification")
            body.append("")
            body.append("| Attribute | Value |")
            body.append("| --- | --- |")
            body.append("| Category | \(dtc.category) |")
            body.append("| Severity | \(dtc.severity.rawValue) |")

            return OKFConcept(
                path: "diagnostics/\(dtc.code).md",
                type: "DTC Definition",
                title: dtc.code,
                description: "\(dtc.category) trouble code \(dtc.code): \(dtc.title).",
                tags: ["dtc", OKFDocument.slug(dtc.category)],
                sources: [
                    .init(id: "curated-dtc", resource: "../Data/Seed/dtc_definitions.json", title: "Curated VoltLink DTC definitions")
                ],
                generatedBy: generatedBy,
                body: body.joined(separator: "\n")
            )
        }
    }

    // MARK: - Indexes

    /// Render `index.md` files for the bundle root and every directory that holds concepts.
    /// Hand-authored concepts are indexed from their frontmatter, so adding one does not
    /// require editing an index by hand.
    public static func indexFiles(in files: [String: String]) -> [String: String] {
        struct Entry {
            let path: String
            let title: String
            let description: String?
            let type: String
        }

        var entriesByDirectory: [String: [Entry]] = [:]
        for (path, text) in files where path.hasSuffix(".md") {
            let name = (path as NSString).lastPathComponent
            guard name != "index.md", name != "log.md",
                let frontmatter = OKFDocument.frontmatter(of: text),
                let type = frontmatter.fields["type"], !type.isEmpty
            else { continue }

            let directory = (path as NSString).deletingLastPathComponent
            let title =
                frontmatter.fields["title"].flatMap { $0.isEmpty ? nil : $0 }
                ?? name.replacingOccurrences(of: ".md", with: "")
            let description = frontmatter.fields["description"].flatMap { $0.isEmpty ? nil : $0 }
            entriesByDirectory[directory, default: []].append(
                Entry(path: path, title: title, description: description, type: type)
            )
        }

        func sortedEntries(_ directory: String) -> [Entry] {
            (entriesByDirectory[directory] ?? []).sorted { lhs, rhs in
                let left = lhs.title.lowercased()
                let right = rhs.title.lowercased()
                return left == right ? lhs.path < rhs.path : left < right
            }
        }

        func line(for entry: Entry, link: String) -> String {
            if let description = entry.description {
                return "* [\(entry.title)](\(link)) - \(description)"
            }
            return "* [\(entry.title)](\(link))"
        }

        var indexes: [String: String] = [:]

        // Directory indexes group by concept type.
        for (directory, entries) in entriesByDirectory where !directory.isEmpty {
            var lines: [String] = []
            let grouped = Dictionary(grouping: entries, by: \.type)
            for type in grouped.keys.sorted() {
                lines.append("# \(type)")
                for entry in sortedEntries(directory).filter({ $0.type == type }) {
                    let prefix = directory + "/"
                    let link = entry.path.hasPrefix(prefix) ? String(entry.path.dropFirst(prefix.count)) : entry.path
                    lines.append(line(for: entry, link: link))
                }
                lines.append("")
            }
            indexes["\(directory)/index.md"] = lines.joined(separator: "\n")
        }

        // Root index: frontmatter carries only the OKF version; body lists known sections.
        var rootLines = ["---", "okf_version: \(OKFDocument.yamlScalar(okfVersion))", "---", ""]
        for section in rootSections {
            let entries = sortedEntries(section.directory)
            guard !entries.isEmpty else { continue }
            rootLines.append("# \(section.heading)")
            for entry in entries {
                rootLines.append(line(for: entry, link: entry.path))
            }
            rootLines.append("")
        }
        let knownDirectories = Set(rootSections.map(\.directory))
        for directory in entriesByDirectory.keys.filter({ !$0.isEmpty && !knownDirectories.contains($0) }).sorted() {
            rootLines.append("# \(directory.capitalized)")
            for entry in sortedEntries(directory) {
                rootLines.append(line(for: entry, link: entry.path))
            }
            rootLines.append("")
        }
        indexes["index.md"] = rootLines.joined(separator: "\n")

        return indexes
    }

    // MARK: - Export and conformance

    /// Write generated concepts and all indexes. Concepts in the fully generated
    /// directories that no longer exist in code are removed.
    @discardableResult
    public static func write(to root: URL, fileManager: FileManager = .default) throws -> ExportResult {
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        let concepts = conceptFiles()

        var removed: [String] = []
        for directory in generatedDirectories {
            let directoryURL = root.appendingPathComponent(directory)
            let existing = (try? fileManager.contentsOfDirectory(atPath: directoryURL.path)) ?? []
            for name in existing.sorted() where name.hasSuffix(".md") && name != "index.md" {
                let relative = "\(directory)/\(name)"
                if concepts[relative] == nil {
                    try fileManager.removeItem(at: directoryURL.appendingPathComponent(name))
                    removed.append(relative)
                }
            }
        }

        for (path, content) in concepts {
            let url = root.appendingPathComponent(path)
            try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try content.write(to: url, atomically: true, encoding: .utf8)
        }

        var allFiles = readMarkdownFiles(at: root, fileManager: fileManager)
        allFiles.merge(concepts) { _, written in written }

        var written = concepts.keys.sorted()
        for (path, content) in indexFiles(in: allFiles) {
            let url = root.appendingPathComponent(path)
            try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try content.write(to: url, atomically: true, encoding: .utf8)
            written.append(path)
        }

        return ExportResult(written: written.sorted(), removed: removed)
    }

    /// OKF v0.2 conformance plus drift checks against the generated concepts and indexes.
    /// Returns human-readable issues; an empty array means the bundle is current.
    public static func check(at root: URL, fileManager: FileManager = .default) -> [String] {
        guard fileManager.fileExists(atPath: root.path) else {
            return ["Bundle directory is missing: \(root.path). Run `swift run VoltLinkCLI okf export`."]
        }

        let files = readMarkdownFiles(at: root, fileManager: fileManager)
        guard !files.isEmpty else {
            return ["No markdown files found in \(root.path). Run `swift run VoltLinkCLI okf export`."]
        }

        var issues: [String] = []
        for (path, text) in files.sorted(by: { $0.key < $1.key }) {
            let name = (path as NSString).lastPathComponent
            if name == "index.md" || name == "log.md" {
                if path == "index.md" {
                    let version = OKFDocument.frontmatter(of: text)?.fields["okf_version"]
                    if version != okfVersion {
                        issues.append("index.md: expected okf_version \"\(okfVersion)\", found \(version ?? "none")")
                    }
                }
                continue
            }

            guard let frontmatter = OKFDocument.frontmatter(of: text) else {
                issues.append("\(path): missing YAML frontmatter")
                continue
            }
            if (frontmatter.fields["type"] ?? "").isEmpty {
                issues.append("\(path): frontmatter has no type")
            }

            for link in OKFDocument.markdownLinks(in: text) where link.hasSuffix(".md") {
                let resolved = OKFDocument.resolve(link: link, from: path)
                if !files.keys.contains(resolved) {
                    issues.append("\(path): link target \(link) does not exist in the bundle")
                }
            }
        }

        for (path, expected) in conceptFiles() where files[path] != expected {
            issues.append("\(path): \(files[path] == nil ? "missing" : "out of date"); run `swift run VoltLinkCLI okf export`")
        }

        for (path, expected) in indexFiles(in: files) where files[path] != expected {
            issues.append("\(path): index out of date; run `swift run VoltLinkCLI okf export`")
        }

        return issues
    }

    // MARK: - Helpers

    private static func profileTitles() -> [VehicleProfileID: String] {
        let counts = Dictionary(grouping: VehicleProfileID.allCases, by: \.displayName)
        var titles: [VehicleProfileID: String] = [:]
        for id in VehicleProfileID.allCases {
            let name = id.displayName
            titles[id] = (counts[name]?.count ?? 0) > 1 ? "\(name) (\(id.rawValue))" : name
        }
        return titles
    }

    private static func sortedMetrics(_ metrics: Set<TelemetryMetric>) -> [TelemetryMetric] {
        metrics.sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
    }

    /// Metrics the manager publishes as a side effect of another metric (battery temp
    /// min/max come from the same update) plus the derived metrics. Keeps the reference
    /// from claiming a value has no producer when it is actually available.
    private static func expandedMetrics(_ metrics: Set<TelemetryMetric>) -> Set<TelemetryMetric> {
        var result = TelemetryMetric.includingDerivedMetrics(metrics)
        if result.contains(.batteryTemp) {
            result.formUnion([.batteryTempMin, .batteryTempMax])
        }
        if result.contains(.power) {
            result.insert(.tripAverageConsumption)
        }
        return result
    }

    private static func metricNotes(_ metric: TelemetryMetric) -> [String] {
        var notes: [String] = []
        switch metric {
        case .instantEfficiency, .regenPower:
            notes.append("Derived from speed and power; `VehicleDataManager` adds it to the live metric set only while both inputs are available.")
        case .tripAverageConsumption:
            notes.append("Derived by `VehicleDataManager` from power when the profile supports pack power.")
        default:
            break
        }
        if TelemetryMetric.eqaCommunityMetrics.contains(metric) {
            notes.append("Experimental Mercedes-Benz EQA community metric; decoded by `MercedesEQAOBDbProfile`.")
        }
        return notes
    }

    private static func range(_ range: ClosedRange<Double>) -> String {
        "\(number(range.lowerBound))–\(number(range.upperBound))"
    }

    private static func number(_ value: Double) -> String {
        if value == value.rounded() {
            return String(Int(value))
        }
        return String(format: "%.1f", value)
    }

    private static func loadCuratedDTCs() -> [DTCCode] {
        guard
            let url = resourceBundle.url(forResource: "dtc_definitions", withExtension: "json")
                ?? resourceBundle.url(forResource: "dtc_definitions", withExtension: "json", subdirectory: "Seed"),
            let data = try? Data(contentsOf: url),
            let codes = try? JSONDecoder().decode([DTCCode].self, from: data)
        else {
            return []
        }
        return codes
    }

    private static var resourceBundle: Bundle {
        #if SWIFT_PACKAGE
        Bundle.module
        #else
        Bundle.main
        #endif
    }

    private static func readMarkdownFiles(at root: URL, fileManager: FileManager) -> [String: String] {
        guard let enumerator = fileManager.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey]) else {
            return [:]
        }
        let prefix = root.standardizedFileURL.path + "/"
        var files: [String: String] = [:]
        for case let url as URL in enumerator where url.pathExtension == "md" {
            let path = url.standardizedFileURL.path
            guard path.hasPrefix(prefix),
                let text = try? String(contentsOf: url, encoding: .utf8)
            else { continue }
            files[String(path.dropFirst(prefix.count))] = text
        }
        return files
    }
}
