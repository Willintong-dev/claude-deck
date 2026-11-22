import Foundation

public enum SessionAttention: Equatable, Sendable {
    case needsYou
    case working
    case unread
    case seen
}

public struct ReadState: Codable, Equatable, Sendable {
    public private(set) var baseline: Date
    public private(set) var seen: [String: Date] = [:]

    public init(baseline: Date = Date()) {
        self.baseline = baseline
    }

    public func lastSeen(_ sessionId: String) -> Date {
        seen[sessionId] ?? baseline
    }

    public func attention(for session: SessionState) -> SessionAttention {
        switch session.live.status {
        case .waiting:
            return .needsYou
        case .working:
            return .working
        case .idle, .ended:
            guard let since = session.live.since else { return .seen }
            return since > lastSeen(session.id) ? .unread : .seen
        case .open, .unknown:
            return .seen
        }
    }

    public func unreadCount(in sessions: [SessionState]) -> Int {
        sessions.filter { attention(for: $0) == .unread }.count
    }

    @discardableResult
    public mutating func markSeen(_ session: SessionState, at date: Date) -> Bool {
        guard attention(for: session) == .unread || seen[session.id] == nil else { return false }
        seen[session.id] = max(date, session.live.since ?? date)
        return true
    }

    public mutating func markUnread(_ sessionId: String) {
        seen[sessionId] = .distantPast
    }

    public mutating func forget(_ sessionId: String) {
        seen[sessionId] = nil
    }
}

public final class ReadStateStore: @unchecked Sendable {
    public let file: URL

    public init(file: URL) {
        self.file = file
    }

    public static var standard: ReadStateStore {
        ReadStateStore(file: DeckPaths.standard.deckDirectory.appendingPathComponent("read.json"))
    }

    public func load(now: Date = Date()) -> ReadState {
        guard let data = try? Data(contentsOf: file),
              let state = try? Self.decoder.decode(ReadState.self, from: data) else {
            return ReadState(baseline: now)
        }
        return state
    }

    public func save(_ state: ReadState) throws {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Self.encoder.encode(state).write(to: file, options: .atomic)
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
