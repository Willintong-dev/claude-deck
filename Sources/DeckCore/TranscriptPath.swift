import Foundation

public enum TranscriptPath: Equatable, Sendable {
    case session(sessionId: String, project: String)
    case subagent(sessionId: String, agentId: String, project: String)
    case subagentMeta(sessionId: String, agentId: String, project: String)

    private static let agentPrefix = "agent-"
    private static let metaSuffix = ".meta.json"

    public static func classify(_ url: URL, projectsDirectory: URL) -> TranscriptPath? {
        let root = projectsDirectory.standardizedFileURL.pathComponents
        let parts = url.standardizedFileURL.pathComponents
        guard parts.count > root.count, Array(parts.prefix(root.count)) == root else { return nil }
        let relative = Array(parts.dropFirst(root.count))

        switch relative.count {
        case 2 where relative[1].hasSuffix(".jsonl"):
            return .session(sessionId: String(relative[1].dropLast(6)), project: relative[0])
        case 4 where relative[2] == "subagents" && relative[3].hasPrefix(agentPrefix):
            let file = relative[3]
            if file.hasSuffix(metaSuffix) {
                let agentId = String(file.dropFirst(agentPrefix.count).dropLast(metaSuffix.count))
                return .subagentMeta(sessionId: relative[1], agentId: agentId, project: relative[0])
            }
            if file.hasSuffix(".jsonl") {
                let agentId = String(file.dropFirst(agentPrefix.count).dropLast(6))
                return .subagent(sessionId: relative[1], agentId: agentId, project: relative[0])
            }
            return nil
        default:
            return nil
        }
    }
}
