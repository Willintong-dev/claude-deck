import Foundation

public struct SessionGroup: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var createdAt: Date
    public var collapsed: Bool

    public init(id: String, name: String, createdAt: Date, collapsed: Bool = false) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.collapsed = collapsed
    }
}

public struct SessionCatalog: Codable, Equatable, Sendable {
    public private(set) var names: [String: String] = [:]
    public private(set) var groups: [SessionGroup] = []
    public private(set) var membership: [String: String] = [:]
    public private(set) var deleted: [String: Date] = [:]

    public init() {}

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        names = try container.decodeIfPresent([String: String].self, forKey: .names) ?? [:]
        groups = try container.decodeIfPresent([SessionGroup].self, forKey: .groups) ?? []
        membership = try container.decodeIfPresent([String: String].self, forKey: .membership) ?? [:]
        deleted = try container.decodeIfPresent([String: Date].self, forKey: .deleted) ?? [:]
    }

    public func name(of sessionId: String) -> String? {
        names[sessionId]
    }

    public func group(of sessionId: String) -> SessionGroup? {
        membership[sessionId].flatMap(group(withId:))
    }

    public func group(withId id: String) -> SessionGroup? {
        groups.first { $0.id == id }
    }

    public func members(of groupId: String) -> Set<String> {
        Set(membership.filter { $0.value == groupId }.keys)
    }

    public var retainedSessionIds: Set<String> {
        Set(names.keys).union(membership.keys)
    }

    public mutating func rename(_ sessionId: String, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        names[sessionId] = trimmed.isEmpty ? nil : trimmed
    }

    @discardableResult
    public mutating func createGroup(named name: String, id: String = UUID().uuidString, at date: Date = Date()) -> SessionGroup? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let group = SessionGroup(id: id, name: trimmed, createdAt: date)
        groups.append(group)
        return group
    }

    public mutating func renameGroup(_ id: String, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let position = groups.firstIndex(where: { $0.id == id }) else { return }
        groups[position].name = trimmed
    }

    public mutating func setCollapsed(_ id: String, _ collapsed: Bool) {
        guard let position = groups.firstIndex(where: { $0.id == id }) else { return }
        groups[position].collapsed = collapsed
    }

    public mutating func deleteGroup(_ id: String) {
        groups.removeAll { $0.id == id }
        membership = membership.filter { $0.value != id }
    }

    public mutating func assign(_ sessionId: String, to groupId: String?) {
        guard let groupId else {
            membership[sessionId] = nil
            return
        }
        guard group(withId: groupId) != nil else { return }
        membership[sessionId] = groupId
    }

    public mutating func markDeleted(_ sessionId: String, at date: Date) {
        names[sessionId] = nil
        membership[sessionId] = nil
        deleted[sessionId] = date
    }
}

public final class SessionCatalogStore: @unchecked Sendable {
    public let file: URL

    public init(file: URL) {
        self.file = file
    }

    public static var standard: SessionCatalogStore {
        SessionCatalogStore(file: DeckPaths.standard.deckDirectory.appendingPathComponent("catalog.json"))
    }

    public func load() -> SessionCatalog {
        guard let data = try? Data(contentsOf: file) else { return SessionCatalog() }
        return (try? Self.decoder.decode(SessionCatalog.self, from: data)) ?? SessionCatalog()
    }

    public func save(_ catalog: SessionCatalog) throws {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Self.encoder.encode(catalog).write(to: file, options: .atomic)
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

public struct SessionEraser {
    public let claudeDirectory: URL
    private let remove: (URL) throws -> Void

    public init(claudeDirectory: URL, remove: @escaping (URL) throws -> Void) {
        self.claudeDirectory = claudeDirectory
        self.remove = remove
    }

    public static func permanent(
        claudeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude")
    ) -> SessionEraser {
        SessionEraser(claudeDirectory: claudeDirectory) {
            try FileManager.default.removeItem(at: $0)
        }
    }

    public static func isValidSessionId(_ id: String) -> Bool {
        UUID(uuidString: id) != nil
    }

    public func artifacts(of sessionId: String) -> [URL] {
        guard Self.isValidSessionId(sessionId) else { return [] }
        let fileManager = FileManager.default
        let projects = claudeDirectory.appendingPathComponent("projects")
        let projectDirectories = (try? fileManager.contentsOfDirectory(at: projects, includingPropertiesForKeys: nil)) ?? []
        let transcripts = projectDirectories.flatMap { project in
            [project.appendingPathComponent("\(sessionId).jsonl"), project.appendingPathComponent(sessionId)]
        }
        let extras = ["file-history", "session-env"].map {
            claudeDirectory.appendingPathComponent($0).appendingPathComponent(sessionId)
        }
        return (transcripts + extras).filter { fileManager.fileExists(atPath: $0.path) }
    }

    @discardableResult
    public func erase(_ sessionId: String) throws -> [URL] {
        let found = artifacts(of: sessionId)
        for url in found {
            try remove(url)
        }
        return found
    }
}
