import Foundation

public struct SubagentMeta: Decodable, Equatable, Sendable {
    public var agentType: String?
    public var description: String?
    public var finished: Bool?
    public var spawnDepth: Int?

    public static func load(from url: URL) -> SubagentMeta? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(SubagentMeta.self, from: data)
    }
}
