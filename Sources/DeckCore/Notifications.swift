import Foundation

public enum NotificationKind: String, Codable, CaseIterable, Sendable, Identifiable {
    case permission
    case turnFinished
    case sessionEnded
    case subagentFinished

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .permission: return "Espera tu permiso"
        case .turnFinished: return "Terminó su turno"
        case .sessionEnded: return "Sesión cerrada"
        case .subagentFinished: return "Subagente terminó"
        }
    }

    public var defaultRule: NotificationRule {
        switch self {
        case .permission:
            return NotificationRule(enabled: true, sound: "Hero", title: "{sesion}", body: "Necesita tu permiso: {mensaje}")
        case .turnFinished:
            return NotificationRule(enabled: true, sound: "Purr", title: "{sesion}", body: "Terminó y espera tu respuesta")
        case .sessionEnded:
            return NotificationRule(enabled: true, sound: "Bottle", title: "{sesion}", body: "La sesión se cerró")
        case .subagentFinished:
            return NotificationRule(enabled: false, sound: "Tink", title: "{sesion}", body: "Subagente listo: {subagente}")
        }
    }

    public var placeholders: [String] {
        switch self {
        case .permission: return ["sesion", "proyecto", "mensaje"]
        case .turnFinished, .sessionEnded: return ["sesion", "proyecto"]
        case .subagentFinished: return ["sesion", "proyecto", "subagente"]
        }
    }
}

public enum NotificationPosition: String, Codable, CaseIterable, Sendable {
    case topLeft
    case topCenter
    case topRight
    case bottomLeft
    case bottomCenter
    case bottomRight

    public var label: String {
        switch self {
        case .topLeft: return "Arriba a la izquierda"
        case .topCenter: return "Arriba al centro"
        case .topRight: return "Arriba a la derecha"
        case .bottomLeft: return "Abajo a la izquierda"
        case .bottomCenter: return "Abajo al centro"
        case .bottomRight: return "Abajo a la derecha"
        }
    }

    public var isTop: Bool {
        switch self {
        case .topLeft, .topCenter, .topRight: return true
        case .bottomLeft, .bottomCenter, .bottomRight: return false
        }
    }
}

public enum NotificationScreen: String, Codable, CaseIterable, Sendable {
    case main
    case pointer

    public var label: String {
        switch self {
        case .main: return "Pantalla principal"
        case .pointer: return "Donde esté el puntero"
        }
    }
}

public struct NotificationRule: Codable, Equatable, Sendable {
    public var enabled: Bool
    public var sound: String
    public var title: String
    public var body: String

    public static let silent = ""

    public init(enabled: Bool, sound: String, title: String, body: String) {
        self.enabled = enabled
        self.sound = sound
        self.title = title
        self.body = body
    }
}

public struct NotificationSettings: Codable, Equatable, Sendable {
    public var enabled = true
    public var position: NotificationPosition = .topRight
    public var screen: NotificationScreen = .main
    public var duration: Double = 6
    public var volume: Double = 0.7
    public var quietWhenViewing = true
    public var telegram = TelegramSettings()
    private var rules: [String: NotificationRule] = [:]

    public static let durationRange: ClosedRange<Double> = 0...30
    public static let untilDismissed: Double = 0

    public init() {}

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        enabled = (try? container.decodeIfPresent(Bool.self, forKey: .enabled)) ?? true
        position = (try? container.decodeIfPresent(NotificationPosition.self, forKey: .position)) ?? .topRight
        screen = (try? container.decodeIfPresent(NotificationScreen.self, forKey: .screen)) ?? .main
        duration = Self.clampDuration((try? container.decodeIfPresent(Double.self, forKey: .duration)) ?? 6)
        volume = Self.clampVolume((try? container.decodeIfPresent(Double.self, forKey: .volume)) ?? 0.7)
        quietWhenViewing = (try? container.decodeIfPresent(Bool.self, forKey: .quietWhenViewing)) ?? true
        rules = (try? container.decodeIfPresent([String: NotificationRule].self, forKey: .rules)) ?? [:]
        telegram = (try? container.decodeIfPresent(TelegramSettings.self, forKey: .telegram)) ?? TelegramSettings()
    }

    public func rule(for kind: NotificationKind) -> NotificationRule {
        rules[kind.rawValue] ?? kind.defaultRule
    }

    public mutating func update(_ kind: NotificationKind, _ change: (inout NotificationRule) -> Void) {
        var rule = rule(for: kind)
        change(&rule)
        rules[kind.rawValue] = rule == kind.defaultRule ? nil : rule
    }

    public mutating func resetRule(_ kind: NotificationKind) {
        rules[kind.rawValue] = nil
    }

    public mutating func setDuration(_ seconds: Double) {
        duration = Self.clampDuration(seconds)
    }

    public mutating func setVolume(_ value: Double) {
        volume = Self.clampVolume(value)
    }

    public func alert(for trigger: AlertTrigger) -> DeckAlert? {
        guard enabled, rule(for: trigger.kind).enabled else { return nil }
        return rendered(trigger)
    }

    public func rendered(_ trigger: AlertTrigger) -> DeckAlert {
        let rule = rule(for: trigger.kind)
        let title = NotificationTemplate.render(rule.title, trigger.values)
        let body = NotificationTemplate.render(rule.body, trigger.values)
        return DeckAlert(
            kind: trigger.kind,
            sessionId: trigger.sessionId,
            title: title.isEmpty ? (trigger.values["sesion"] ?? trigger.kind.label) : title,
            body: body,
            sound: rule.sound
        )
    }

    public static let sampleValues = [
        "sesion": "Sesión de ejemplo",
        "proyecto": "claude-deck",
        "mensaje": "Claude needs your permission to use Bash",
        "subagente": "Buscar logs del pago",
    ]

    public func preview(_ kind: NotificationKind) -> DeckAlert {
        var settings = self
        settings.enabled = true
        settings.update(kind) { $0.enabled = true }
        return settings.alert(for: AlertTrigger(kind: kind, sessionId: "", values: Self.sampleValues))!
    }

    private static func clampDuration(_ seconds: Double) -> Double {
        min(max(seconds, durationRange.lowerBound), durationRange.upperBound)
    }

    private static func clampVolume(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }
}

public enum NotificationTemplate {
    public static func render(_ template: String, _ values: [String: String]) -> String {
        var result = template
        for (key, value) in values {
            result = result.replacingOccurrences(of: "{\(key)}", with: value)
        }
        let unknown = try? NSRegularExpression(pattern: #"\{[a-z]+\}"#)
        if let unknown {
            result = unknown.stringByReplacingMatches(in: result, range: NSRange(result.startIndex..., in: result), withTemplate: "")
        }
        return result
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: ":·-").union(.whitespaces))
    }
}

public struct AlertTrigger: Equatable, Sendable {
    public let kind: NotificationKind
    public let sessionId: String
    public let values: [String: String]

    public init(kind: NotificationKind, sessionId: String, values: [String: String]) {
        self.kind = kind
        self.sessionId = sessionId
        self.values = values
    }
}

public struct DeckAlert: Equatable, Sendable, Identifiable {
    public let id = UUID()
    public let kind: NotificationKind
    public let sessionId: String
    public let title: String
    public let body: String
    public let sound: String

    public init(kind: NotificationKind, sessionId: String, title: String, body: String, sound: String) {
        self.kind = kind
        self.sessionId = sessionId
        self.title = title
        self.body = body
        self.sound = sound
    }

    public static func == (lhs: DeckAlert, rhs: DeckAlert) -> Bool {
        lhs.kind == rhs.kind && lhs.sessionId == rhs.sessionId && lhs.title == rhs.title
            && lhs.body == rhs.body && lhs.sound == rhs.sound
    }
}

public struct NotificationDetector: Sendable {
    private var statuses: [String: SessionStatus]?
    private var finishedSubagents: [String: Set<String>] = [:]

    public init() {}

    public mutating func triggers(in sessions: [String: SessionState], title: (SessionState) -> String) -> [AlertTrigger] {
        defer { remember(sessions) }
        guard let statuses else { return [] }
        var found: [AlertTrigger] = []
        for session in sessions.values.sorted(by: { $0.id < $1.id }) {
            guard let previous = statuses[session.id] else { continue }
            let current = session.live.status
            var values = [
                "sesion": title(session),
                "proyecto": session.summary.cwd.map { URL(fileURLWithPath: $0).lastPathComponent } ?? session.project,
            ]
            if current == .waiting, previous != .waiting {
                values["mensaje"] = session.live.message ?? ""
                found.append(AlertTrigger(kind: .permission, sessionId: session.id, values: values))
            } else if current == .idle, previous == .working || previous == .waiting {
                found.append(AlertTrigger(kind: .turnFinished, sessionId: session.id, values: values))
            } else if current == .ended, previous.isActive {
                found.append(AlertTrigger(kind: .sessionEnded, sessionId: session.id, values: values))
            }
            let known = finishedSubagents[session.id] ?? []
            for subagent in session.orderedSubagents.reversed() where subagent.meta?.finished == true && !known.contains(subagent.id) {
                var subagentValues = values
                subagentValues["subagente"] = subagent.displayTitle
                found.append(AlertTrigger(kind: .subagentFinished, sessionId: session.id, values: subagentValues))
            }
        }
        return found
    }

    private mutating func remember(_ sessions: [String: SessionState]) {
        statuses = sessions.mapValues(\.live.status)
        finishedSubagents = sessions.mapValues { session in
            Set(session.subagents.values.filter { $0.meta?.finished == true }.map(\.id))
        }
    }
}

public final class NotificationStore: @unchecked Sendable {
    public let file: URL

    public init(file: URL) {
        self.file = file
    }

    public static var standard: NotificationStore {
        NotificationStore(file: DeckPaths.standard.deckDirectory.appendingPathComponent("notifications.json"))
    }

    public func load() -> NotificationSettings {
        guard let data = try? Data(contentsOf: file) else { return NotificationSettings() }
        return (try? JSONDecoder().decode(NotificationSettings.self, from: data)) ?? NotificationSettings()
    }

    public func save(_ settings: NotificationSettings) throws {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(settings).write(to: file, options: .atomic)
    }
}
