import Foundation

public enum SessionStatus: String, Sendable, CaseIterable {
    case waiting
    case working
    case idle
    case open
    case ended
    case unknown

    public var isActive: Bool {
        switch self {
        case .waiting, .working, .idle, .open: return true
        case .ended, .unknown: return false
        }
    }

    public var priority: Int {
        switch self {
        case .waiting: return 0
        case .working: return 1
        case .idle: return 2
        case .open: return 3
        case .unknown: return 4
        case .ended: return 5
        }
    }
}

public struct LiveState: Equatable, Sendable {
    public var status: SessionStatus = .unknown
    public var pid: Int32?
    public var since: Date?
    public var message: String?
    public var cwd: String?

    private static let waitingNotifications: Set<String> = ["permission_prompt", "elicitation_dialog"]

    public init() {}

    public mutating func apply(_ event: HookEvent) {
        if let since, event.timestamp < since { return }
        if let pid = event.pid { self.pid = pid }
        if let cwd = event.cwd { self.cwd = cwd }
        switch event.event {
        case "SessionStart":
            transition(to: .idle, at: event.timestamp)
        case "UserPromptSubmit":
            transition(to: .working, at: event.timestamp)
        case "Stop":
            transition(to: .idle, at: event.timestamp)
        case "SessionEnd":
            transition(to: .ended, at: event.timestamp)
            pid = nil
        case "Notification":
            applyNotification(event)
        default:
            break
        }
    }

    public mutating func observeConversationActivity(at date: Date) {
        guard status == .waiting, let since, date > since else { return }
        transition(to: .working, at: date)
    }

    public mutating func attach(pid: Int32) {
        self.pid = pid
        if !status.isActive || status == .open {
            status = .open
            message = nil
        }
    }

    public mutating func processExited(at date: Date) {
        transition(to: .ended, at: date)
        pid = nil
    }

    private mutating func applyNotification(_ event: HookEvent) {
        if let type = event.notificationType {
            if Self.waitingNotifications.contains(type) {
                transition(to: .waiting, at: event.timestamp, message: event.message)
            } else if type == "idle_prompt" {
                transition(to: .idle, at: event.timestamp)
            }
            return
        }
        if event.message?.localizedCaseInsensitiveContains("permission") == true {
            transition(to: .waiting, at: event.timestamp, message: event.message)
        }
    }

    private mutating func transition(to status: SessionStatus, at date: Date, message: String? = nil) {
        self.status = status
        since = date
        self.message = message
    }
}
