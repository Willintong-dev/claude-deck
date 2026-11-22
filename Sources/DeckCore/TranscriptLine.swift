import Foundation

public struct TranscriptMessage: Equatable, Sendable, Identifiable {
    public enum Role: String, Sendable {
        case user
        case assistant
    }

    public let id: String
    public let role: Role
    public let text: String
    public let timestamp: Date?

    public init(id: String, role: Role, text: String, timestamp: Date?) {
        self.id = id
        self.role = role
        self.text = text
        self.timestamp = timestamp
    }
}

public struct TranscriptLine: Equatable, Sendable {
    public var type: String
    public var aiTitle: String?
    public var lastPrompt: String?
    public var cwd: String?
    public var gitBranch: String?
    public var timestamp: Date?
    public var message: TranscriptMessage?
    public var contextTokens: Int?

    public static let maximumParsedLineSize = 512 * 1024
    private static let timestampStyle = Date.ISO8601FormatStyle(includingFractionalSeconds: true)

    public static func parse(_ data: Data) -> TranscriptLine? {
        guard data.count <= maximumParsedLineSize,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = object["type"] as? String
        else { return nil }

        var line = TranscriptLine(type: type)
        line.aiTitle = object["aiTitle"] as? String
        line.lastPrompt = object["lastPrompt"] as? String
        line.cwd = object["cwd"] as? String
        line.gitBranch = object["gitBranch"] as? String
        line.timestamp = (object["timestamp"] as? String).flatMap { try? timestampStyle.parse($0) }
        line.message = conversationMessage(from: object, type: type, timestamp: line.timestamp)
        if type == "assistant", object["isSidechain"] as? Bool != true {
            line.contextTokens = contextTokens(from: object["message"])
        }
        return line
    }

    private static func conversationMessage(from object: [String: Any], type: String, timestamp: Date?) -> TranscriptMessage? {
        guard let role = TranscriptMessage.Role(rawValue: type),
              object["isMeta"] as? Bool != true,
              let message = object["message"] as? [String: Any],
              let text = readableText(from: message["content"])
        else { return nil }
        let id = object["uuid"] as? String ?? UUID().uuidString
        return TranscriptMessage(id: id, role: role, text: text, timestamp: timestamp)
    }

    static func contextTokens(from message: Any?) -> Int? {
        guard let usage = (message as? [String: Any])?["usage"] as? [String: Any] else { return nil }
        let keys = ["input_tokens", "cache_creation_input_tokens", "cache_read_input_tokens"]
        let values = keys.compactMap { (usage[$0] as? NSNumber)?.intValue }
        return values.isEmpty ? nil : values.reduce(0, +)
    }

    private static func readableText(from content: Any?) -> String? {
        let text: String
        if let plain = content as? String {
            text = plain
        } else if let blocks = content as? [[String: Any]] {
            text = blocks
                .filter { $0["type"] as? String == "text" }
                .compactMap { $0["text"] as? String }
                .joined(separator: "\n")
        } else {
            return nil
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("<") else { return nil }
        return trimmed
    }

    init(type: String) {
        self.type = type
    }
}
