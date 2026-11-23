import Foundation

public struct StatusLineInput: Equatable, Sendable {
    public var sessionId: String
    public var model: String?
    public var cwd: String?
    public var transcriptPath: String?
    public var usedPercentage: Double?

    public init(sessionId: String, model: String? = nil, cwd: String? = nil, transcriptPath: String? = nil, usedPercentage: Double? = nil) {
        self.sessionId = sessionId
        self.model = model
        self.cwd = cwd
        self.transcriptPath = transcriptPath
        self.usedPercentage = usedPercentage
    }

    public static func parse(_ data: Data) -> StatusLineInput? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sessionId = object["session_id"] as? String
        else { return nil }
        let model = object["model"] as? [String: Any]
        let workspace = object["workspace"] as? [String: Any]
        let context = object["context_window"] as? [String: Any]
        return StatusLineInput(
            sessionId: sessionId,
            model: (model?["display_name"] as? String) ?? (model?["id"] as? String),
            cwd: (workspace?["current_dir"] as? String) ?? (object["cwd"] as? String),
            transcriptPath: object["transcript_path"] as? String,
            usedPercentage: (context?["used_percentage"] as? NSNumber)?.doubleValue
        )
    }
}

public struct StatusLineParts: Equatable, Sendable {
    public var name: String
    public var model: String?
    public var context: String?
    public var contextLevel: ContextLevel
    public var branch: String?

    public enum ContextLevel: Equatable, Sendable {
        case low
        case medium
        case high
    }
}

public enum StatusLine {
    public static let transcriptWindow: UInt64 = 256 * 1024
    private static let separator = " \u{1B}[2m·\u{1B}[22m "

    public static func parts(for input: StatusLineInput, catalog: SessionCatalog, transcript: [TranscriptLine]) -> StatusLineParts {
        let folder = input.cwd.map { URL(fileURLWithPath: $0).lastPathComponent }
        let name = catalog.name(of: input.sessionId) ?? transcript.last(where: { $0.aiTitle?.isEmpty == false })?.aiTitle ?? folder ?? "Sesión"
        let tokens = transcript.last(where: { $0.contextTokens != nil })?.contextTokens
        let branch = transcript.last(where: { $0.gitBranch?.isEmpty == false })?.gitBranch
        let context: String?
        let level: StatusLineParts.ContextLevel
        if let percentage = input.usedPercentage {
            context = "ctx \(Int(percentage.rounded()))%"
            level = percentage >= 80 ? .high : percentage >= 50 ? .medium : .low
        } else if let tokens {
            context = SessionSummary.formatTokens(tokens) + " ctx"
            level = tokens >= BrainPrompt.contextThreshold ? .high : tokens >= BrainPrompt.contextThreshold / 2 ? .medium : .low
        } else {
            context = nil
            level = .low
        }
        return StatusLineParts(name: name, model: input.model, context: context, contextLevel: level, branch: branch)
    }

    public static func render(_ parts: StatusLineParts) -> String {
        var segments = ["\u{1B}[1;34m◆ \(parts.name)\u{1B}[0m"]
        if let model = parts.model { segments.append("\u{1B}[36m\(model)\u{1B}[0m") }
        if let context = parts.context {
            let color: String
            switch parts.contextLevel {
            case .low: color = "32"
            case .medium: color = "33"
            case .high: color = "31"
            }
            segments.append("\u{1B}[\(color)m\(context)\u{1B}[0m")
        }
        if let branch = parts.branch { segments.append("\u{1B}[35m⎇ \(branch)\u{1B}[0m") }
        return segments.joined(separator: separator)
    }

    public static func line(for payload: Data, catalog: SessionCatalog) -> String? {
        guard let input = StatusLineInput.parse(payload) else { return nil }
        let transcript = input.transcriptPath
            .map { TailReader(url: URL(fileURLWithPath: $0), initialWindow: transcriptWindow).readNewLines() }?
            .compactMap(TranscriptLine.parse) ?? []
        return render(parts(for: input, catalog: catalog, transcript: transcript))
    }
}
