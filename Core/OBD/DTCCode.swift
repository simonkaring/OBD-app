import Foundation

public enum DTCSeverity: String, Codable, Sendable {
    case critical = "Critical"
    case warning = "Warning"
    case advisory = "Advisory"
}

public struct DTCCode: Codable, Sendable, Identifiable, Hashable {
    public var id: String { code }
    public let code: String
    public let title: String
    public let category: String
    public let severity: DTCSeverity
    public let description: String
    public let symptoms: [String]
    public let possibleFixes: [String]
    public var freezeFrameData: [String: String]?
    public var timestamp: Date

    enum CodingKeys: String, CodingKey {
        case code, title, category, severity, description, symptoms, possibleFixes, freezeFrameData, timestamp
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.code = try container.decode(String.self, forKey: .code)
        self.title = try container.decode(String.self, forKey: .title)
        self.category = try container.decode(String.self, forKey: .category)
        self.severity = try container.decode(DTCSeverity.self, forKey: .severity)
        self.description = try container.decode(String.self, forKey: .description)
        self.symptoms = try container.decodeIfPresent([String].self, forKey: .symptoms) ?? []
        self.possibleFixes = try container.decodeIfPresent([String].self, forKey: .possibleFixes) ?? []
        self.freezeFrameData = try container.decodeIfPresent([String: String].self, forKey: .freezeFrameData)
        self.timestamp = try container.decodeIfPresent(Date.self, forKey: .timestamp) ?? Date()
    }

    public init(
        code: String,
        title: String,
        category: String,
        severity: DTCSeverity,
        description: String,
        symptoms: [String] = [],
        possibleFixes: [String] = [],
        freezeFrameData: [String: String]? = nil,
        timestamp: Date = Date()
    ) {
        self.code = code
        self.title = title
        self.category = category
        self.severity = severity
        self.description = description
        self.symptoms = symptoms
        self.possibleFixes = possibleFixes
        self.freezeFrameData = freezeFrameData
        self.timestamp = timestamp
    }
}
