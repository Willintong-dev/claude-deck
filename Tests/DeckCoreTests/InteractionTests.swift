import Foundation
import Testing
@testable import DeckCore

struct ClaudeProcessesTests {
    let id = "950c98df-ee2f-497d-b3f8-32b8f743838f"

    @Test func readsTheSessionIdFromEveryFlagStyle() {
        #expect(ClaudeProcesses.sessionId(fromArguments: ["claude", "--session-id", id, "--ide"]) == id)
        #expect(ClaudeProcesses.sessionId(fromArguments: ["claude", "--resume", id]) == id)
        #expect(ClaudeProcesses.sessionId(fromArguments: ["claude", "-r", id]) == id)
        #expect(ClaudeProcesses.sessionId(fromArguments: ["claude", "--session-id=\(id)"]) == id)
    }

    @Test func ignoresArgumentsWithoutAValidSessionId() {
        #expect(ClaudeProcesses.sessionId(fromArguments: ["claude"]) == nil)
        #expect(ClaudeProcesses.sessionId(fromArguments: ["claude", "--resume"]) == nil)
        #expect(ClaudeProcesses.sessionId(fromArguments: ["claude", "--resume", "my search"]) == nil)
        #expect(ClaudeProcesses.sessionId(fromArguments: ["claude", "-p", id]) == nil)
    }

    @Test func parsesTheKernelArgumentLayout() {
        var buffer: [UInt8] = []
        withUnsafeBytes(of: Int32(3)) { buffer += $0 }
        buffer += Array("/usr/bin/claude".utf8) + [0, 0, 0]
        buffer += Array("claude".utf8) + [0] + Array("--resume".utf8) + [0] + Array(id.utf8) + [0]
        buffer += Array("HOME=/Users/x".utf8) + [0]

        #expect(ClaudeProcesses.parseProcArgs(buffer) == ["claude", "--resume", id])
        #expect(ClaudeProcesses.parseProcArgs([1, 0]) == nil)
    }

    @Test func readsTheArgumentsOfTheCurrentProcess() throws {
        let arguments = try #require(ClaudeProcesses.arguments(of: getpid()))
        #expect(arguments == CommandLine.arguments)
    }
}

struct ClaudeLaunchTests {
    let id = "11111111-2222-3333-4444-555555555555"

    @Test func buildsNewAndResumeCommands() {
        let new = ClaudeLaunch(sessionId: id, directory: "/r", mode: .new, skipPermissions: true)
        let resume = ClaudeLaunch(sessionId: id, directory: "/r", mode: .resume, skipPermissions: false)

        #expect(new.claudeArguments == ["claude", "--session-id", id, "--permission-mode", "bypassPermissions"])
        #expect(resume.claudeArguments == ["claude", "--resume", id])
        #expect(resume.shellCommand(loginShell: "/bin/zsh") == "exec /bin/zsh -lic 'exec claude --resume \(id)'")
    }

    @Test func quotesShellArgumentsSafely() {
        #expect(Shell.quote("plain-value_1.2") == "plain-value_1.2")
        #expect(Shell.quote("with space") == "'with space'")
        #expect(Shell.quote("it's") == "'it'\\''s'")
        #expect(Shell.quote("") == "''")
        #expect(Shell.quote("$(rm -rf /)") == "'$(rm -rf /)'")
    }
}

struct TmuxArgumentTests {
    let tmux = Tmux(executable: URL(fileURLWithPath: "/opt/homebrew/bin/tmux"), configFile: URL(fileURLWithPath: "/d/tmux.conf"), socketName: "s")
    let id = "11111111-2222-3333-4444-555555555555"

    @Test func targetsTheSessionOnTheDeckSocket() {
        let launch = ClaudeLaunch(sessionId: id, directory: "/repo dir", mode: .new, skipPermissions: false)
        let arguments = tmux.newSessionArguments(launch, loginShell: "/bin/zsh", columns: 120, rows: 40)

        #expect(Array(arguments.prefix(4)) == ["-L", "s", "-f", "/d/tmux.conf"])
        #expect(arguments.contains("cd-\(id)"))
        #expect(arguments.contains("/repo dir"))
        #expect(arguments.last == launch.shellCommand(loginShell: "/bin/zsh"))
        #expect(tmux.attachArguments(sessionId: id).suffix(3) == ["attach-session", "-t", "=cd-\(id)"])
        #expect(tmux.killSessionArguments(sessionId: id).suffix(3) == ["kill-session", "-t", "=cd-\(id)"])
    }

    @Test func sendsTextLiterallyAndThenEnter() {
        let commands = tmux.sendTextArguments(sessionId: id, text: "hola; rm -rf")
        #expect(commands.count == 2)
        #expect(commands[0].suffix(5) == ["send-keys", "-t", "=cd-\(id):", "-l", "hola; rm -rf"])
        #expect(commands[1].suffix(4) == ["send-keys", "-t", "=cd-\(id):", "Enter"])
    }

    @Test func parsesOnlyDeckSessionNames() {
        let output = "cd-\(id)\nother\ncd-not-a-uuid\n"
        #expect(Tmux.parseSessionList(output) == [id])
    }

    @Test func buildsAnEnvironmentThatFindsHomebrewTools() {
        let environment = Tmux.environment(base: ["PATH": "/usr/bin:/bin", "TMUX": "x"])
        #expect(environment["PATH"] == "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin")
        #expect(environment["TMUX"] == nil)
        #expect(environment["TERM"] == "xterm-256color")
        #expect(Tmux.environment(base: ["PATH": "/opt/homebrew/bin:/usr/bin"])["PATH"] == "/usr/local/bin:/opt/homebrew/bin:/usr/bin")
    }

    @Test func relaysSubagentMessagesOnASingleLine() {
        let message = SubagentRelay.message(agentId: "a1", description: "Buscar", text: "primera\nsegunda")
        #expect(message == "Usa SendMessage para enviarle al subagente a1 (Buscar) exactamente este mensaje: primera segunda")
        #expect(!message.contains("\n"))
    }
}

struct TmuxIntegrationTests {
    @Test func createsListsTypesIntoAndKillsASession() throws {
        let executable = try #require(Tmux.locate())
        let directory = TemporaryDirectory()
        let tmux = Tmux(executable: executable, configFile: directory.file("tmux.conf"), socketName: "claude-deck-test-\(getpid())")
        try tmux.writeConfiguration()
        let id = UUID().uuidString.lowercased()
        defer { tmux.run(tmux.baseArguments + ["kill-server"]) }

        let created = tmux.run(tmux.baseArguments + ["new-session", "-d", "-s", Tmux.sessionName(for: id), "-x", "80", "-y", "20", "cat"])
        #expect(created.status == 0)
        #expect(tmux.ownedSessionIds() == [id])

        for arguments in tmux.sendTextArguments(sessionId: id, text: "mensaje-de-prueba") {
            #expect(tmux.run(arguments).status == 0)
        }
        var captured = ""
        for _ in 0..<20 where !captured.contains("mensaje-de-prueba") {
            usleep(50_000)
            captured = tmux.run(tmux.baseArguments + ["capture-pane", "-p", "-t", "=" + Tmux.sessionName(for: id) + ":"]).output
        }
        #expect(captured.contains("mensaje-de-prueba"))

        #expect(tmux.run(tmux.killSessionArguments(sessionId: id)).status == 0)
        #expect(tmux.ownedSessionIds().isEmpty)
    }
}

struct RunningProcessIndexTests {
    let directory = TemporaryDirectory()

    @Test func runningProcessesMarkSessionsOpenWithoutOverridingKnownStates() {
        let paths = DeckPaths(projectsDirectory: directory.url.appendingPathComponent("projects"), deckDirectory: directory.url.appendingPathComponent("deck"))
        write(Lines.user("hola", at: "2026-11-21T11:00:00.000Z"), to: paths.projectsDirectory.appendingPathComponent("p/a.jsonl"))
        write(Lines.user("hola", at: "2026-11-21T11:00:00.000Z"), to: paths.projectsDirectory.appendingPathComponent("p/b.jsonl"))
        try? EventLog.append(HookEvent(event: "UserPromptSubmit", sessionId: "b", timestamp: date("2026-11-21T11:01:00.000Z")), to: paths.eventsFile)
        let index = SessionIndex(paths: paths, now: { date("2026-11-21T12:00:00.000Z") })
        index.fullScan()

        #expect(index.registerRunningProcesses([10: "a", 11: "b"]) == ["a", "b"])
        #expect(index.snapshot()["a"]?.live.status == .open)
        #expect(index.snapshot()["b"]?.live.status == .working)
        #expect(index.snapshot()["b"]?.live.pid == 11)
        #expect(index.registerRunningProcesses([10: "a", 11: "b"]).isEmpty)
        #expect(index.sessionsWithoutProcess(among: ["a", "b", "c"]) == ["c"])
    }

    @Test func activeSessionsWithoutTranscriptAppearAsPlaceholders() {
        let paths = DeckPaths(projectsDirectory: directory.url.appendingPathComponent("projects"), deckDirectory: directory.url.appendingPathComponent("deck"))
        try? FileManager.default.createDirectory(at: paths.projectsDirectory, withIntermediateDirectories: true)
        try? EventLog.append(HookEvent(event: "SessionStart", sessionId: "fresh", timestamp: date("2026-11-21T11:00:00.000Z"), pid: 5, cwd: "/repo/x"), to: paths.eventsFile)
        try? EventLog.append(HookEvent(event: "SessionEnd", sessionId: "gone", timestamp: date("2026-11-21T11:00:00.000Z")), to: paths.eventsFile)
        let index = SessionIndex(paths: paths, now: { date("2026-11-21T12:00:00.000Z") })
        index.fullScan()

        #expect(index.snapshot()["fresh"]?.summary.cwd == "/repo/x")
        #expect(index.snapshot()["fresh"]?.live.status == .idle)
        #expect(index.snapshot()["gone"] == nil)
    }
}

struct ProcessTerminationTests {
    private func spawn(_ arguments: [String]) throws -> Process {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = arguments
        try process.run()
        return process
    }

    @Test func terminatesAProcessThatHonoursSigterm() throws {
        let process = try spawn(["-c", "sleep 30"])
        let pid = process.processIdentifier
        #expect(ProcessTree.isAlive(pid))

        #expect(ProcessTree.terminate(pid, gracePeriod: 3))
        #expect(!ProcessTree.isAlive(pid))
    }

    @Test func escalatesToSigkillWhenSigtermIsIgnored() throws {
        let process = try spawn(["-c", "trap '' TERM; while :; do sleep 0.05; done"])
        let pid = process.processIdentifier
        usleep(200_000)

        #expect(ProcessTree.terminate(pid, gracePeriod: 0.5))
        #expect(!ProcessTree.isAlive(pid))
    }

    @Test func reportsAlreadyFinishedProcessesAsTerminated() throws {
        let process = try spawn(["-c", "exit 0"])
        process.waitUntilExit()
        #expect(ProcessTree.terminate(process.processIdentifier))
    }

    @Test func namesTheAppThatOwnsAProcess() throws {
        let process = try spawn(["-c", "sleep 5"])
        defer { process.terminate() }
        let owner = try #require(ProcessTree.ownerName(of: process.processIdentifier))
        #expect(!owner.isEmpty)
        #expect(!owner.contains("/"))
    }

    @Test func readsTheSessionIdOfARunningProcess() throws {
        let id = UUID().uuidString.lowercased()
        let process = try spawn(["-c", "sleep 5; true", "claude", "--resume", id.uppercased()])
        defer { process.terminate() }
        usleep(100_000)
        #expect(ClaudeProcesses.sessionId(of: process.processIdentifier) == id)
    }
}
