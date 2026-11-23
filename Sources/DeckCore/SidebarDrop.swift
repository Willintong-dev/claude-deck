import Foundation

public enum SidebarDrop {
    public static let prefix = "claude-deck-session:"

    public static func payload(for sessionId: String) -> String {
        prefix + sessionId
    }

    public static func sessionIds(in payloads: [String], known: (String) -> Bool) -> [String] {
        var seen: Set<String> = []
        return payloads.compactMap { payload in
            guard payload.hasPrefix(prefix) else { return nil }
            let id = String(payload.dropFirst(prefix.count))
            guard known(id), seen.insert(id).inserted else { return nil }
            return id
        }
    }
}
