import Foundation

public enum DTCSeverity: String, Codable, Sendable {
    case critical = "Critical"
    case warning = "Warning"
    case advisory = "Advisory"
    case unknown = "Unknown"
}

public struct DTCCode: Codable, Sendable, Identifiable, Hashable {
    /// Module fault memories can report the same code, so the module is part of the
    /// identity. Emission codes keep their plain code, which is also the persisted key.
    public var id: String { moduleName.map { "\($0)|\(code)" } ?? code }

    public let code: String
    public let title: String
    public let category: String
    public let severity: DTCSeverity
    public let description: String
    public let symptoms: [String]
    public let possibleFixes: [String]
    public var freezeFrameData: [String: String]?
    public var timestamp: Date
    public var definitionSource: String?
    /// Set for codes read from a module's UDS fault memory, e.g. "Drive unit".
    public var moduleName: String?
    /// Text for the UDS failure-type byte, e.g. "Circuit short to ground".
    public var failureTypeDescription: String?
    /// ISO 14229 status bits that were set when the module reported the code.
    public var statusDescriptions: [String]?

    enum CodingKeys: String, CodingKey {
        case code, title, category, severity, description, symptoms, possibleFixes, freezeFrameData, timestamp, definitionSource
        case moduleName, failureTypeDescription, statusDescriptions
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
        self.definitionSource = try container.decodeIfPresent(String.self, forKey: .definitionSource)
        self.moduleName = try container.decodeIfPresent(String.self, forKey: .moduleName)
        self.failureTypeDescription = try container.decodeIfPresent(String.self, forKey: .failureTypeDescription)
        self.statusDescriptions = try container.decodeIfPresent([String].self, forKey: .statusDescriptions)
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
        timestamp: Date = Date(),
        definitionSource: String? = nil,
        moduleName: String? = nil,
        failureTypeDescription: String? = nil,
        statusDescriptions: [String]? = nil
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
        self.definitionSource = definitionSource
        self.moduleName = moduleName
        self.failureTypeDescription = failureTypeDescription
        self.statusDescriptions = statusDescriptions
    }
}
