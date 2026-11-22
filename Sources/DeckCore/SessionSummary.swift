import Foundation

public struct SessionSummary: Equatable, Sendable {
    public var title: String?
    public var lastPrompt: String?
    public var cwd: String?
    public var gitBranch: String?
    public var lastActivity: Date?
    public var lastConversationActivity: Date?
    public var preview: String?
    public var contextTokens: Int?

    public static let previewLength = 160

    public init() {}

    public mutating func apply(_ line: TranscriptLine) {
        if let title = line.aiTitle, !title.isEmpty { self.title = title }
        if let prompt = line.lastPrompt, !prompt.isEmpty { lastPrompt = prompt }
        if let cwd = line.cwd { self.cwd = cwd }
        if let branch = line.gitBranch, !branch.isEmpty { gitBranch = branch }
        if let timestamp = line.timestamp, timestamp > (lastActivity ?? .distantPast) {
            lastActivity = timestamp
        }
        if TranscriptMessage.Role(rawValue: line.type) != nil,
           let timestamp = line.timestamp,
           timestamp > (lastConversationActivity ?? .distantPast) {
            lastConversationActivity = timestamp
        }
        if let tokens = line.contextTokens {
            contextTokens = tokens
        }
        if let message = line.message {
            preview = String(message.text.prefix(Self.previewLength))
        }
    }

    public var needsContextRelief: Bool {
        (contextTokens ?? 0) >= BrainPrompt.contextThreshold
    }

    public static func formatTokens(_ tokens: Int) -> String {
        tokens >= 1000 ? "\(tokens / 1000)k" : "\(tokens)"
    }

    public var displayTitle: String {
        if let title, !title.isEmpty { return title }
        if let lastPrompt, !lastPrompt.isEmpty { return String(lastPrompt.prefix(60)) }
        if let cwd { return URL(fileURLWithPath: cwd).lastPathComponent }
        return "Sesión sin título"
    }
}
