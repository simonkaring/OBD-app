import Foundation
import VoltLinkEngine

/// Writes and validates the checked-in Open Knowledge Format (OKF) bundle.
struct OKFCommand {
    static func run(args: [String]) {
        guard let subcommand = args.first else {
            printUsage()
            return
        }

        let options = Array(args.dropFirst())
        switch subcommand.lowercased() {
        case "export":
            export(options: options)
        case "check":
            check(options: options)
        case "help", "-h", "--help":
            printUsage()
        default:
            print("❌ Unknown okf subcommand: '\(subcommand)'")
            printUsage()
            exit(1)
        }
    }

    private static func export(options: [String]) {
        let root = bundleRoot(options: options, flag: "--out")
        do {
            let result = try KnowledgeBundle.write(to: root)
            print("📚 Exported \(result.written.count) files to \(root.path)")
            if !result.removed.isEmpty {
                print("🗑️  Removed \(result.removed.count) stale generated file(s):")
                for path in result.removed {
                    print("   - \(path)")
                }
            }
            let issues = KnowledgeBundle.check(at: root)
            if issues.isEmpty {
                print("✅ Bundle conforms to OKF v\(KnowledgeBundle.okfVersion)")
            } else {
                print("⚠️  Bundle exported but failed validation:")
                for issue in issues { print("   - \(issue)") }
                exit(1)
            }
        } catch {
            print("❌ Export failed: \(error.localizedDescription)")
            exit(1)
        }
    }

    private static func check(options: [String]) {
        let root = bundleRoot(options: options, flag: "--dir")
        let issues = KnowledgeBundle.check(at: root)
        guard issues.isEmpty else {
            print("❌ \(issues.count) OKF issue(s) in \(root.path):")
            for issue in issues { print("   - \(issue)") }
            exit(1)
        }
        print("✅ \(root.path) conforms to OKF v\(KnowledgeBundle.okfVersion) and matches its sources")
    }

    private static func bundleRoot(options: [String], flag: String) -> URL {
        var path = KnowledgeBundle.defaultDirectoryName
        var index = 0
        while index < options.count {
            let option = options[index]
            if option == flag || option == "-o" || option == "-d" {
                guard index + 1 < options.count else {
                    print("❌ \(option) requires a path")
                    exit(1)
                }
                path = options[index + 1]
                index += 2
            } else {
                print("❌ Unknown option: \(option)")
                exit(1)
            }
        }

        if path.hasPrefix("/") {
            return URL(fileURLWithPath: path)
        }
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(path)
    }

    private static func printUsage() {
        print("""
        📚 OKF (Open Knowledge Format) bundle commands

        USAGE:
          voltlink-cli okf export [--out <dir>]   Regenerate concepts and indexes
          voltlink-cli okf check  [--dir <dir>]   Validate conformance and drift

        Defaults to ./\(KnowledgeBundle.defaultDirectoryName). Generated concepts cover
        vehicle profiles, telemetry metrics, and curated DTCs; architecture
        concepts are hand-authored and only indexed.
        """)
    }
}
