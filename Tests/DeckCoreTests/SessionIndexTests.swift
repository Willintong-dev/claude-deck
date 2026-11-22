import Foundation
import Testing
@testable import DeckCore

struct SessionIndexTests {
    let directory = TemporaryDirectory()
    var paths: DeckPaths {
        DeckPaths(projectsDirectory: directory.url.appendingPathComponent("projects"), deckDirectory: directory.url.appendingPathComponent("deck"))
    }

    private func makeIndex(now: Date = date("2026-11-21T12:00:00.000Z")) -> SessionIndex {
        try? FileManager.default.createDirectory(at: paths.projectsDirectory, withIntermediateDirectories: true)
        return SessionIndex(paths: paths, now: { now })
    }

    private func sessionFile(_ id: String, project: String = "proj") -> URL {
        paths.projectsDirectory.appendingPathComponent("\(project)/\(id).jsonl")
    }

    private func logEvent(_ event: HookEvent) {
        try? EventLog.append(event, to: paths.eventsFile)
    }

    @Test func fullScanLoadsRecentSessionsWithTheirSubagents() throws {
        let file = sessionFile("s1")
        write(Lines.user("hola", at: "2026-11-21T11:00:00.000Z") + Lines.title("Sesión uno"), to: file)
        let agentDirectory = file.deletingPathExtension().appendingPathComponent("subagents")
        write(Lines.user("investiga", at: "2026-11-21T11:05:00.000Z"), to: agentDirectory.appendingPathComponent("agent-a1.jsonl"))
        write(#"{"agentType":"Explore","description":"Buscar uso","finished":false}"#, to: agentDirectory.appendingPathComponent("agent-a1.meta.json"))
        write(#"{"agentType":"fork","description":"Listo","finished":true}"#, to: agentDirectory.appendingPathComponent("agent-a2.meta.json"))

        let index = makeIndex()
        let changed = index.fullScan()
        let session = try #require(index.snapshot()["s1"])

        #expect(changed == ["s1"])
        #expect(session.project == "proj")
        #expect(session.summary.displayTitle == "Sesión uno")
        #expect(session.subagents.count == 2)
        #expect(session.runningSubagentCount(at: date("2026-11-21T11:10:00.000Z")) == 1)
        #expect(session.runningSubagentCount(at: date("2026-11-21T11:30:00.000Z")) == 0)
        #expect(session.orderedSubagents.first?.id == "a1")
        #expect(session.subagents["a1"]?.displayTitle == "Buscar uso")
        #expect(session.subagents["a1"]?.summary.lastPrompt == nil)
    }

    @Test func fullScanSkipsSessionsOutsideTheRecentWindow() {
        let file = sessionFile("old")
        write(Lines.user("viejo", at: "2026-01-01T00:00:00.000Z"), to: file)
        try? FileManager.default.setAttributes([.modificationDate: date("2026-01-01T00:00:00.000Z")], ofItemAtPath: file.path)

        let index = makeIndex()
        index.fullScan()

        #expect(index.snapshot().isEmpty)
    }

    @Test func incrementalChangesUpdateOnlyTheAffectedSession() throws {
        write(Lines.user("uno", at: "2026-11-21T11:00:00.000Z"), to: sessionFile("s1"))
        write(Lines.user("dos", at: "2026-11-21T11:00:00.000Z"), to: sessionFile("s2"))
        let index = makeIndex()
        index.fullScan()

        append(Lines.assistant("respuesta", at: "2026-11-21T11:30:00.000Z"), to: sessionFile("s1"))
        let changed = index.handleChanges(at: [sessionFile("s1"), sessionFile("s2")])

        #expect(changed.contains("s1"))
        #expect(index.snapshot()["s1"]?.summary.preview == "respuesta")
        #expect(index.snapshot()["s1"]?.summary.lastActivity == date("2026-11-21T11:30:00.000Z"))
        #expect(index.snapshot()["s2"]?.summary.preview == "dos")
    }

    @Test func newSubagentFilesAppearUnderTheirSession() throws {
        write(Lines.user("uno", at: "2026-11-21T11:00:00.000Z"), to: sessionFile("s1"))
        let index = makeIndex()
        index.fullScan()

        let meta = sessionFile("s1").deletingPathExtension().appendingPathComponent("subagents/agent-n1.meta.json")
        write(#"{"agentType":"general-purpose","description":"Nuevo","finished":false}"#, to: meta)
        #expect(index.handleChanges(at: [meta]) == ["s1"])
        #expect(index.handleChanges(at: [meta]).isEmpty)

        write(#"{"agentType":"general-purpose","description":"Nuevo","finished":true}"#, to: meta)
        #expect(index.handleChanges(at: [meta]) == ["s1"])
        #expect(index.snapshot()["s1"]?.subagents["n1"]?.meta?.finished == true)
    }

    @Test func subagentsRunOnlyWhenUnfinishedAndRecentlyActive() {
        let recent = date("2026-11-21T11:00:00.000Z")
        var agent = SubagentState(id: "a", sessionId: "s")
        #expect(!agent.isRunning(at: recent))
        agent.summary.lastActivity = recent
        #expect(agent.isRunning(at: recent.addingTimeInterval(60)))
        #expect(!agent.isRunning(at: recent.addingTimeInterval(SubagentState.activityTimeout + 1)))
        agent.meta = SubagentMeta(agentType: "x", description: nil, finished: false, spawnDepth: nil)
        #expect(agent.isRunning(at: recent.addingTimeInterval(60)))
        agent.meta?.finished = true
        #expect(!agent.isRunning(at: recent.addingTimeInterval(60)))
    }

    @Test func hookEventsDriveTheLiveStatus() throws {
        write(Lines.user("uno", at: "2026-11-21T11:00:00.000Z"), to: sessionFile("s1"))
        let index = makeIndex()
        index.fullScan()

        logEvent(HookEvent(event: "UserPromptSubmit", sessionId: "s1", timestamp: date("2026-11-21T11:10:00.000Z"), pid: 4242))
        logEvent(HookEvent(event: "Notification", sessionId: "s1", timestamp: date("2026-11-21T11:11:00.000Z"), notificationType: "permission_prompt", message: "permiso"))
        #expect(index.handleChanges(at: [paths.eventsFile]) == ["s1"])

        let live = try #require(index.snapshot()["s1"]?.live)
        #expect(live.status == .waiting)
        #expect(live.pid == 4242)
        #expect(index.trackedPids() == [4242: "s1"])
    }

    @Test func transcriptActivityAfterAPermissionPromptMeansWorking() throws {
        write(Lines.user("uno", at: "2026-11-21T11:00:00.000Z"), to: sessionFile("s1"))
        logEvent(HookEvent(event: "Notification", sessionId: "s1", timestamp: date("2026-11-21T11:11:00.000Z"), notificationType: "permission_prompt"))
        let index = makeIndex()
        index.fullScan()
        #expect(index.snapshot()["s1"]?.live.status == .waiting)

        append(Lines.toolResult(at: "2026-11-21T11:12:00.000Z"), to: sessionFile("s1"))
        index.handleChanges(at: [sessionFile("s1")])

        #expect(index.snapshot()["s1"]?.live.status == .working)
    }

    @Test func processExitEndsEverySessionOwnedByThatPid() {
        write(Lines.user("uno", at: "2026-11-21T11:00:00.000Z"), to: sessionFile("s1"))
        logEvent(HookEvent(event: "SessionStart", sessionId: "s1", timestamp: date("2026-11-21T11:00:00.000Z"), pid: 77))
        let index = makeIndex()
        index.fullScan()

        #expect(index.markProcessExited(pid: 77) == ["s1"])
        #expect(index.snapshot()["s1"]?.live.status == .ended)
        #expect(index.trackedPids().isEmpty)
        #expect(index.markProcessExited(pid: 78).isEmpty)
    }

    @Test func placeholderSessionsGainTheirTranscriptWhenItAppears() {
        let index = makeIndex()
        index.fullScan()
        logEvent(HookEvent(event: "SessionStart", sessionId: "fresh", timestamp: date("2026-11-21T11:00:00.000Z"), pid: 5, cwd: "/repo/fresh"))
        index.handleChanges(at: [paths.eventsFile])
        #expect(index.snapshot()["fresh"]?.transcriptURL == nil)

        write(Lines.user("hola", at: "2026-11-21T11:00:01.000Z"), to: sessionFile("fresh"))
        index.handleChanges(at: [sessionFile("fresh")])
        #expect(index.snapshot()["fresh"]?.transcriptURL != nil)
        #expect(index.snapshot()["fresh"]?.live.status == .idle)
    }

    @Test func ignoresPathsOutsideTheWatchedLayout() {
        let index = makeIndex()
        index.fullScan()
        let stray = paths.projectsDirectory.appendingPathComponent("proj/s1/tool-results/x.txt")
        write("x", to: stray)

        #expect(index.handleChanges(at: [stray]).isEmpty)
    }
}
