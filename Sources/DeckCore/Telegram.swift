import Foundation

public struct TelegramSettings: Codable, Equatable, Sendable {
    public var enabled = false
    public var chatId = ""
    public var idleMinutes: Double = 5
    public var kinds: Set<NotificationKind> = [.permission, .turnFinished, .sessionEnded]

    public static let idleRange: ClosedRange<Double> = 0...120
    public static let always: Double = 0

    public init() {}

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        enabled = (try? container.decodeIfPresent(Bool.self, forKey: .enabled)) ?? false
        chatId = (try? container.decodeIfPresent(String.self, forKey: .chatId)) ?? ""
        idleMinutes = Self.clampIdle((try? container.decodeIfPresent(Double.self, forKey: .idleMinutes)) ?? 5)
        let rawKinds = (try? container.decodeIfPresent([String].self, forKey: .kinds)) ?? nil
        kinds = rawKinds.map { Set($0.compactMap(NotificationKind.init(rawValue:))) } ?? [.permission, .turnFinished, .sessionEnded]
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(enabled, forKey: .enabled)
        try container.encode(chatId, forKey: .chatId)
        try container.encode(idleMinutes, forKey: .idleMinutes)
        try container.encode(kinds.map(\.rawValue).sorted(), forKey: .kinds)
    }

    private enum CodingKeys: String, CodingKey {
        case enabled, chatId, idleMinutes, kinds
    }

    public var isConfigured: Bool { !chatId.trimmingCharacters(in: .whitespaces).isEmpty }

    public mutating func setIdleMinutes(_ minutes: Double) {
        idleMinutes = Self.clampIdle(minutes)
    }

    public func shouldSend(_ kind: NotificationKind, idleSeconds: TimeInterval, hasToken: Bool) -> Bool {
        enabled && hasToken && isConfigured && kinds.contains(kind) && idleSeconds >= idleMinutes * 60
    }

    private static func clampIdle(_ minutes: Double) -> Double {
        min(max(minutes, idleRange.lowerBound), idleRange.upperBound)
    }
}

public struct TelegramChat: Equatable, Sendable {
    public let id: String
    public let name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

public enum TelegramAPI {
    public static let base = URL(string: "https://api.telegram.org")!

    public static func sendMessageRequest(token: String, chatId: String, text: String) -> URLRequest {
        var request = URLRequest(url: base.appendingPathComponent("bot\(token)/sendMessage"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "chat_id": chatId,
            "text": text,
            "disable_web_page_preview": true,
        ])
        request.timeoutInterval = 15
        return request
    }

    public static func updatesRequest(token: String) -> URLRequest {
        var request = URLRequest(url: base.appendingPathComponent("bot\(token)/getUpdates"))
        request.timeoutInterval = 15
        return request
    }

    public static func text(for alert: DeckAlert) -> String {
        let header = "\(alert.kind.emoji) \(alert.title)"
        return alert.body.isEmpty ? header : "\(header)\n\(alert.body)"
    }

    public static func chats(fromUpdates data: Data) -> [TelegramChat] {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let updates = object["result"] as? [[String: Any]]
        else { return [] }
        var seen: Set<String> = []
        var chats: [TelegramChat] = []
        for update in updates.reversed() {
            let message = (update["message"] ?? update["edited_message"] ?? update["channel_post"]) as? [String: Any]
            guard let chat = message?["chat"] as? [String: Any],
                  let id = (chat["id"] as? NSNumber)?.stringValue,
                  seen.insert(id).inserted
            else { continue }
            let person = [chat["first_name"] as? String, chat["last_name"] as? String].compactMap { $0 }.joined(separator: " ")
            let name = (chat["title"] as? String) ?? (person.isEmpty ? nil : person) ?? (chat["username"] as? String) ?? id
            chats.append(TelegramChat(id: id, name: name))
        }
        return chats
    }

    public static func failure(from data: Data, status: Int) -> String? {
        let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        if object?["ok"] as? Bool == true, (200..<300).contains(status) { return nil }
        return (object?["description"] as? String) ?? "Telegram respondió \(status)"
    }
}

extension NotificationKind {
    public var emoji: String {
        switch self {
        case .permission: return "🟠"
        case .turnFinished: return "✅"
        case .sessionEnded: return "⏹"
        case .subagentFinished: return "🤝"
        }
    }
}

public final class TelegramTokenStore: @unchecked Sendable {
    public let file: URL

    public init(file: URL) {
        self.file = file
    }

    public static var standard: TelegramTokenStore {
        TelegramTokenStore(file: DeckPaths.standard.deckDirectory.appendingPathComponent("telegram-token"))
    }

    public func load() -> String {
        ((try? String(contentsOf: file, encoding: .utf8)) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public func save(_ token: String) throws {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            try? FileManager.default.removeItem(at: file)
            return
        }
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: file.path, contents: nil, attributes: [.posixPermissions: 0o600])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        try Data(trimmed.utf8).write(to: file)
    }
}
