import Foundation

public struct HookEvent: Codable, Equatable, Sendable {
    public var event: String
    public var sessionId: String
    public var timestamp: Date
    public var pid: Int32?
    public var cwd: String?
    public var notificationType: String?
    public var message: String?
    public var agentId: String?
    public var source: String?

    public static let maximumMessageLength = 300

    public init(
        event: String,
        sessionId: String,
        timestamp: Date,
        pid: Int32? = nil,
        cwd: String? = nil,
        notificationType: String? = nil,
        message: String? = nil,
        agentId: String? = nil,
        source: String? = nil
    ) {
        self.event = event
        self.sessionId = sessionId
        self.timestamp = timestamp
        self.pid = pid
        self.cwd = cwd
        self.notificationType = notificationType
        self.message = message
        self.agentId = agentId
        self.source = source
    }

    public static func fromHookPayload(_ data: Data, timestamp: Date, pid: Int32?) -> HookEvent? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let event = object["hook_event_name"] as? String,
              let sessionId = object["session_id"] as? String
        else { return nil }
        return HookEvent(
            event: event,
            sessionId: sessionId,
            timestamp: timestamp,
            pid: pid,
            cwd: object["cwd"] as? String,
            notificationType: object["notification_type"] as? String,
            message: (object["message"] as? String).map { String($0.prefix(maximumMessageLength)) },
            agentId: object["agent_id"] as? String,
            source: (object["source"] ?? object["reason"]) as? String
        )
    }

    public func encodedLine() -> Data? {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        guard var data = try? encoder.encode(self) else { return nil }
        data.append(0x0A)
        return data
    }

    public static func decode(line: Data) -> HookEvent? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return try? decoder.decode(HookEvent.self, from: line)
    }
}
