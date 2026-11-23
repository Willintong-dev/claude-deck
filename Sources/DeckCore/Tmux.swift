import Foundation

public struct ClaudeLaunch: Equatable, Sendable {
    public enum Mode: Equatable, Sendable {
        case new
        case resume
    }

    public let sessionId: String
    public let directory: String
    public let mode: Mode
    public let skipPermissions: Bool
    public let systemPromptFile: String?
    public let brainDirectory: String?
    public let environment: [String: String]
    public let statusLineCommand: String?

    public init(
        sessionId: String,
        directory: String,
        mode: Mode,
        skipPermissions: Bool,
        systemPromptFile: String? = nil,
        brainDirectory: String? = nil,
        environment: [String: String] = [:],
        statusLineCommand: String? = nil
    ) {
        self.sessionId = sessionId
        self.directory = directory
        self.mode = mode
        self.skipPermissions = skipPermissions
        self.systemPromptFile = systemPromptFile
        self.brainDirectory = brainDirectory
        self.environment = environment
        self.statusLineCommand = statusLineCommand
    }

    public var claudeArguments: [String] {
        var arguments = ["claude", mode == .new ? "--session-id" : "--resume", sessionId]
        if skipPermissions {
            arguments += ["--permission-mode", "bypassPermissions"]
        }
        if let systemPromptFile {
            arguments += ["--append-system-prompt-file", systemPromptFile]
        }
        if let brainDirectory {
            arguments += ["--allowedTools", "Read(/\(brainDirectory)/**)", "Edit(/\(brainDirectory)/**)"]
        }
        if let statusLineCommand {
            arguments += ["--settings", Self.statusLineSettings(command: statusLineCommand)]
        }
        return arguments
    }

    public static func statusLineSettings(command: String) -> String {
        let settings: [String: Any] = ["statusLine": ["type": "command", "command": command, "padding": 0]]
        let data = (try? JSONSerialization.data(withJSONObject: settings, options: [.sortedKeys, .withoutEscapingSlashes])) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }

    public func shellCommand(loginShell: String) -> String {
        let inner = "exec " + claudeArguments.map(Shell.quote).joined(separator: " ")
        return "exec \(Shell.quote(loginShell)) -lic \(Shell.quote(inner))"
    }
}

public enum Shell {
    public static func quote(_ value: String) -> String {
        if !value.isEmpty, value.allSatisfy({ $0.isLetter || $0.isNumber || "-_./=:@%+".contains($0) }) {
            return value
        }
        return "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

public struct Tmux: Sendable {
    public static let defaultSocketName = "claude-deck"
    public static let sessionPrefix = "cd-"

    public let executable: URL
    public let configFile: URL
    public let socketName: String

    public init(executable: URL, configFile: URL, socketName: String = Tmux.defaultSocketName) {
        self.executable = executable
        self.configFile = configFile
        self.socketName = socketName
    }

    public static let configuration = """
    set -g status off
    set -g mouse on
    set -g history-limit 50000
    set -g default-terminal "xterm-256color"
    set -ga terminal-overrides ",xterm-256color:Tc"
    set -sg escape-time 0
    set -g window-size latest
    set -g aggressive-resize on
    set -g destroy-unattached off
    set -g exit-empty on
    set -g extended-keys on
    set -g allow-passthrough on

    """

    public static func locate(candidates: [String] = ["/opt/homebrew/bin/tmux", "/usr/local/bin/tmux", "/usr/bin/tmux"]) -> URL? {
        candidates.first { FileManager.default.isExecutableFile(atPath: $0) }.map(URL.init(fileURLWithPath:))
    }

    public static func sessionName(for sessionId: String) -> String {
        sessionPrefix + sessionId
    }

    public static func sessionId(fromName name: String) -> String? {
        guard name.hasPrefix(sessionPrefix) else { return nil }
        let id = String(name.dropFirst(sessionPrefix.count))
        return ClaudeProcesses.isSessionId(id) ? id : nil
    }

    public var baseArguments: [String] {
        ["-L", socketName, "-f", configFile.path]
    }

    public func newSessionArguments(_ launch: ClaudeLaunch, loginShell: String, columns: Int = 200, rows: Int = 50) -> [String] {
        baseArguments + [
            "new-session", "-d",
            "-s", Self.sessionName(for: launch.sessionId),
            "-c", launch.directory,
            "-x", String(columns), "-y", String(rows),
        ] + launch.environment.sorted { $0.key < $1.key }.flatMap { ["-e", "\($0.key)=\($0.value)"] } + [
            launch.shellCommand(loginShell: loginShell),
        ]
    }

    public func attachArguments(sessionId: String) -> [String] {
        baseArguments + ["attach-session", "-t", "=" + Self.sessionName(for: sessionId)]
    }

    public func listSessionsArguments() -> [String] {
        baseArguments + ["list-sessions", "-F", "#{session_name}"]
    }

    public func killSessionArguments(sessionId: String) -> [String] {
        baseArguments + ["kill-session", "-t", "=" + Self.sessionName(for: sessionId)]
    }

    public func sendTextArguments(sessionId: String, text: String) -> [[String]] {
        let target = "=" + Self.sessionName(for: sessionId) + ":"
        return [
            baseArguments + ["send-keys", "-t", target, "-l", text],
            baseArguments + ["send-keys", "-t", target, "Enter"],
        ]
    }

    public static func parseSessionList(_ output: String) -> Set<String> {
        Set(output.split(whereSeparator: \.isNewline).compactMap { sessionId(fromName: String($0)) })
    }

    @discardableResult
    public func run(_ arguments: [String]) -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.environment = Self.environment()
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
        } catch {
            return (-1, error.localizedDescription)
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: data, as: UTF8.self))
    }

    public func ownedSessionIds() -> Set<String> {
        let result = run(listSessionsArguments())
        guard result.status == 0 else { return [] }
        return Self.parseSessionList(result.output)
    }

    public func writeConfiguration() throws {
        try FileManager.default.createDirectory(at: configFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Self.configuration.write(to: configFile, atomically: true, encoding: .utf8)
    }

    public static func environment(base: [String: String] = ProcessInfo.processInfo.environment) -> [String: String] {
        var environment = base
        environment["TERM"] = "xterm-256color"
        environment["COLORTERM"] = "truecolor"
        environment["LANG"] = base["LANG"] ?? "en_US.UTF-8"
        environment["LC_CTYPE"] = base["LC_CTYPE"] ?? "en_US.UTF-8"
        let extraPaths = ["/opt/homebrew/bin", "/usr/local/bin"]
        let currentPath = base["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        let missing = extraPaths.filter { !currentPath.split(separator: ":").contains(Substring($0)) }
        environment["PATH"] = (missing + [currentPath]).joined(separator: ":")
        environment.removeValue(forKey: "TMUX")
        return environment
    }
}

public struct SubagentRelay {
    public static func message(agentId: String, description: String?, text: String) -> String {
        let label = description.map { " (\($0))" } ?? ""
        let flattened = text.split(whereSeparator: \.isNewline).joined(separator: " ")
        return "Usa SendMessage para enviarle al subagente \(agentId)\(label) exactamente este mensaje: \(flattened)"
    }
}
