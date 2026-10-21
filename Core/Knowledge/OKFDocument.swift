import Foundation

/// One concept in an Open Knowledge Format (OKF) v0.2 bundle: a markdown document
/// with YAML frontmatter. See https://github.com/GoogleCloudPlatform/open-knowledge-format.
public struct OKFConcept: Sendable, Equatable {
    public struct Source: Sendable, Equatable {
        public let id: String
        public let resource: String
        public let title: String?

        public init(id: String, resource: String, title: String? = nil) {
            self.id = id
            self.resource = resource
            self.title = title
        }
    }

    /// Bundle-relative path including the `.md` suffix, e.g. `vehicles/mercedes-eqa-250.md`.
    public let path: String
    public let type: String
    public let title: String
    public let description: String?
    /// Canonical URI or path of the underlying asset, if the concept describes one.
    public let resource: String?
    public let tags: [String]
    public let sources: [Source]
    public let status: String
    /// Actor in the OKF `<producer>/<version>` form.
    public let generatedBy: String
    public let body: String

    public init(
        path: String,
        type: String,
        title: String,
        description: String? = nil,
        resource: String? = nil,
        tags: [String] = [],
        sources: [Source] = [],
        status: String = "stable",
        generatedBy: String,
        body: String
    ) {
        self.path = path
        self.type = type
        self.title = title
        self.description = description
        self.resource = resource
        self.tags = tags
        self.sources = sources
        self.status = status
        self.generatedBy = generatedBy
        self.body = body
    }

    /// Complete file contents: frontmatter block followed by the markdown body.
    public var markdown: String {
        var lines = ["---"]
        lines.append("type: \(OKFDocument.yamlScalar(type))")
        lines.append("title: \(OKFDocument.yamlScalar(title))")
        if let description {
            lines.append("description: \(OKFDocument.yamlScalar(description))")
        }
        if let resource {
            lines.append("resource: \(OKFDocument.yamlScalar(resource))")
        }
        if !tags.isEmpty {
            lines.append("tags: [\(tags.map(OKFDocument.yamlScalar).joined(separator: ", "))]")
        }
        if !sources.isEmpty {
            lines.append("sources:")
            for source in sources {
                lines.append("- id: \(OKFDocument.yamlScalar(source.id))")
                lines.append("  resource: \(OKFDocument.yamlScalar(source.resource))")
                if let title = source.title {
                    lines.append("  title: \(OKFDocument.yamlScalar(title))")
                }
            }
        }
        lines.append("generated: { by: \(OKFDocument.yamlScalar(generatedBy)) }")
        lines.append("status: \(OKFDocument.yamlScalar(status))")
        lines.append("---")
        lines.append("")
        let trimmedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
        return lines.joined(separator: "\n") + "\n" + trimmedBody + "\n"
    }
}

/// Top-level scalar frontmatter plus the body. Nested maps/lists are intentionally not
/// modeled: consumers only need `type`, `title`, `description`, and `status` for indexing.
public struct OKFFrontmatter: Sendable, Equatable {
    public let fields: [String: String]
    public let body: String

    public init(fields: [String: String], body: String) {
        self.fields = fields
        self.body = body
    }
}

public enum OKFDocument {
    /// Render a string as a double-quoted YAML scalar. Quoting everything keeps titles with
    /// colons, quotes, and leading symbols valid without a full YAML emitter.
    public static func yamlScalar(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: " ")
        return "\"\(escaped)\""
    }

    /// Parse a leading `---` delimited frontmatter block. Returns `nil` when the file does
    /// not start with frontmatter or the block is unterminated.
    public static func frontmatter(of text: String) -> OKFFrontmatter? {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        let lines = normalized.components(separatedBy: "\n")
        guard let first = lines.first, first.trimmingCharacters(in: .whitespaces) == "---" else {
            return nil
        }
        guard let closing = lines.indices.dropFirst().first(where: {
            lines[$0].trimmingCharacters(in: .whitespaces) == "---"
        }) else {
            return nil
        }

        var fields: [String: String] = [:]
        for line in lines[1..<closing] {
            // Only top-level keys; nested `sources:` entries and list items are skipped.
            guard !line.hasPrefix(" "), !line.hasPrefix("\t"), !line.hasPrefix("-"),
                  let colon = line.firstIndex(of: ":") else { continue }
            let key = String(line[..<colon]).trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty else { continue }
            let raw = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            fields[key] = unquote(raw)
        }

        let body = lines[(closing + 1)...].joined(separator: "\n")
        return OKFFrontmatter(fields: fields, body: body)
    }

    /// Bundle-relative link targets in a markdown document, excluding external URLs and
    /// same-document anchors.
    public static func markdownLinks(in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: #"\]\(([^)\s]+)\)"#) else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            guard let target = Range(match.range(at: 1), in: text) else { return nil }
            let link = String(text[target])
            guard !link.hasPrefix("http://"), !link.hasPrefix("https://"),
                  !link.hasPrefix("mailto:"), !link.hasPrefix("#") else { return nil }
            return link
        }
    }

    /// Lowercase kebab-case slug used for concept filenames.
    public static func slug(_ value: String) -> String {
        let characters = Array(value)
        var result = ""
        for (index, character) in characters.enumerated() {
            if character.isUppercase {
                let previous = index > 0 ? characters[index - 1] : nil
                let next = index + 1 < characters.count ? characters[index + 1] : nil
                let previousIsLower = previous?.isLowercase == true
                let acronymBreak = previous?.isUppercase == true && next?.isLowercase == true
                if !result.isEmpty, (previousIsLower || acronymBreak), !result.hasSuffix("-") {
                    result.append("-")
                }
                result.append(contentsOf: character.lowercased())
            } else if character.isLetter || character.isNumber {
                result.append(character)
            } else if !result.isEmpty, !result.hasSuffix("-") {
                result.append("-")
            }
        }
        while result.hasSuffix("-") { result.removeLast() }
        return result
    }

    /// Resolve a markdown link against the bundle-relative path of the document containing it.
    /// Accepts bundle-absolute (`/telemetry/x.md`) and relative (`../telemetry/x.md`) forms.
    public static func resolve(link: String, from path: String) -> String {
        let target = link.split(separator: "#", maxSplits: 1).first.map(String.init) ?? link
        if target.hasPrefix("/") {
            return String(target.dropFirst())
        }
        let directory = (path as NSString).deletingLastPathComponent
        let combined = directory.isEmpty ? target : directory + "/" + target
        var components: [String] = []
        for component in combined.split(separator: "/") {
            switch component {
            case ".":
                continue
            case "..":
                if !components.isEmpty { components.removeLast() }
            default:
                components.append(String(component))
            }
        }
        return components.joined(separator: "/")
    }

    private static func unquote(_ raw: String) -> String {
        guard raw.count >= 2, raw.hasPrefix("\""), raw.hasSuffix("\"") else { return raw }
        let inner = raw.dropFirst().dropLast()
        var result = ""
        var escaping = false
        for character in inner {
            if escaping {
                switch character {
                case "n": result.append("\n")
                case "t": result.append("\t")
                default: result.append(character)
                }
                escaping = false
            } else if character == "\\" {
                escaping = true
            } else {
                result.append(character)
            }
        }
        return result
    }
}
