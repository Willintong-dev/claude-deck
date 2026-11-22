import Foundation
import Testing
@testable import DeckCore

struct HookEventTests {
    @Test func buildsAnEventFromTheHookPayload() throws {
        let payload = #"{"hook_event_name":"Notification","session_id":"s1","cwd":"/r","notification_type":"permission_prompt","message":"\#(String(repeating: "m", count: 400))","transcript_path":"/t"}"#
        let event = try #require(HookEvent.fromHookPayload(Data(payload.utf8), timestamp: Date(timeIntervalSince1970: 100), pid: 42))

        #expect(event.event == "Notification")
        #expect(event.sessionId == "s1")
        #expect(event.pid == 42)
        #expect(event.notificationType == "permission_prompt")
        #expect(event.message?.count == HookEvent.maximumMessageLength)
    }

    @Test func rejectsPayloadsWithoutEventOrSession() {
        #expect(HookEvent.fromHookPayload(Data(#"{"session_id":"s1"}"#.utf8), timestamp: Date(), pid: nil) == nil)
        #expect(HookEvent.fromHookPayload(Data(#"{"hook_event_name":"Stop"}"#.utf8), timestamp: Date(), pid: nil) == nil)
        #expect(HookEvent.fromHookPayload(Data("garbage".utf8), timestamp: Date(), pid: nil) == nil)
    }

    @Test func roundTripsThroughTheLogLineFormat() throws {
        let event = HookEvent(event: "Stop", sessionId: "s1", timestamp: Date(timeIntervalSince1970: 1_800_000_000.25), pid: 7)
        let line = try #require(event.encodedLine())

        #expect(line.last == 0x0A)
        #expect(HookEvent.decode(line: line.dropLast()) == event)
    }
}

struct LiveStateTests {
    private func event(_ name: String, at seconds: TimeInterval, type: String? = nil, message: String? = nil, pid: Int32? = 9) -> HookEvent {
        HookEvent(event: name, sessionId: "s", timestamp: Date(timeIntervalSince1970: seconds), pid: pid, notificationType: type, message: message)
    }

    @Test func followsTheConversationLifecycle() {
        var state = LiveState()
        state.apply(event("SessionStart", at: 1))
        #expect(state.status == .idle)
        #expect(state.pid == 9)
        state.apply(event("UserPromptSubmit", at: 2))
        #expect(state.status == .working)
        state.apply(event("Notification", at: 3, type: "permission_prompt", message: "Claude needs your permission to use Bash"))
        #expect(state.status == .waiting)
        #expect(state.message == "Claude needs your permission to use Bash")
        state.apply(event("Stop", at: 4))
        #expect(state.status == .idle)
        #expect(state.message == nil)
        state.apply(event("SessionEnd", at: 5))
        #expect(state.status == .ended)
        #expect(state.pid == nil)
    }

    @Test func idleNotificationsAndUnknownTypesDoNotRaiseWaiting() {
        var state = LiveState()
        state.apply(event("UserPromptSubmit", at: 1))
        state.apply(event("Notification", at: 2, type: "auth_success"))
        #expect(state.status == .working)
        state.apply(event("Notification", at: 3, type: "idle_prompt"))
        #expect(state.status == .idle)
    }

    @Test func untypedPermissionNotificationsStillMeanWaiting() {
        var state = LiveState()
        state.apply(event("Notification", at: 1, message: "Claude needs your permission"))
        #expect(state.status == .waiting)
    }

    @Test func ignoresEventsOlderThanTheCurrentState() {
        var state = LiveState()
        state.apply(event("Stop", at: 10))
        state.apply(event("UserPromptSubmit", at: 5))
        #expect(state.status == .idle)
    }

    @Test func conversationActivityAfterWaitingMeansWorkingAgain() {
        var state = LiveState()
        state.apply(event("Notification", at: 10, type: "permission_prompt"))
        state.observeConversationActivity(at: Date(timeIntervalSince1970: 9))
        #expect(state.status == .waiting)
        state.observeConversationActivity(at: Date(timeIntervalSince1970: 11))
        #expect(state.status == .working)
    }

    @Test func processExitEndsTheSession() {
        var state = LiveState()
        state.apply(event("UserPromptSubmit", at: 1))
        state.processExited(at: Date(timeIntervalSince1970: 2))
        #expect(state.status == .ended)
        #expect(state.pid == nil)
    }

    @Test func ordersStatusesByUrgency() {
        let ordered = SessionStatus.allCases.sorted { $0.priority < $1.priority }
        #expect(ordered == [.waiting, .working, .idle, .open, .unknown, .ended])
        #expect(SessionStatus.allCases.filter(\.isActive) == [.waiting, .working, .idle, .open])
    }

    @Test func attachingAProcessOpensOnlyInactiveSessions() {
        var unknown = LiveState()
        unknown.attach(pid: 3)
        #expect(unknown.status == .open)
        #expect(unknown.pid == 3)

        var working = LiveState()
        working.apply(event("UserPromptSubmit", at: 1))
        working.attach(pid: 4)
        #expect(working.status == .working)
        #expect(working.pid == 4)

        var ended = LiveState()
        ended.apply(event("SessionEnd", at: 1))
        ended.attach(pid: 5)
        #expect(ended.status == .open)
    }
}

struct ProcessTreeTests {
    @Test func findsTheCurrentProcessAsItsOwnAncestor() throws {
        let me = getpid()
        let entry = try #require(ProcessTree.entry(of: me))

        #expect(entry.parent == getppid())
        #expect(!entry.path.isEmpty)
        #expect(ProcessTree.ancestor(of: me) { $0.path == entry.path } == me)
        #expect(ProcessTree.ancestor(of: me) { _ in false } == nil)
    }

    @Test func recognisesClaudeExecutables() {
        #expect(ProcessTree.isClaudeExecutable("/Users/u/.local/bin/claude"))
        #expect(ProcessTree.isClaudeExecutable("/Users/u/.local/share/claude/versions/2.1.330"))
        #expect(!ProcessTree.isClaudeExecutable("/bin/zsh"))
        #expect(!ProcessTree.isClaudeExecutable("/opt/versions/2.1.330"))
    }

    @Test func reportsLiveness() {
        #expect(ProcessTree.isAlive(getpid()))
        #expect(!ProcessTree.isAlive(Int32.max - 1))
    }
}

struct EventLogTests {
    @Test func appendsEventsAsLines() {
        let directory = TemporaryDirectory()
        let file = directory.url.appendingPathComponent("nested/events.jsonl")
        try? EventLog.append(HookEvent(event: "Stop", sessionId: "a", timestamp: Date()), to: file)
        try? EventLog.append(HookEvent(event: "Stop", sessionId: "b", timestamp: Date()), to: file)

        let lines = TailReader(url: file, initialWindow: 4096).readNewLines()
        #expect(lines.compactMap(HookEvent.decode(line:)).map(\.sessionId) == ["a", "b"])
    }

    @Test func rotatesOnlyPastTheThreshold() {
        let directory = TemporaryDirectory()
        let file = directory.file("events.jsonl")
        write("small\n", to: file)
        EventLog.rotateIfNeeded(file)
        #expect(FileManager.default.fileExists(atPath: file.path))

        write(String(repeating: "x", count: Int(EventLog.rotationThreshold) + 1), to: file)
        EventLog.rotateIfNeeded(file)
        #expect(!FileManager.default.fileExists(atPath: file.path))
        #expect(FileManager.default.fileExists(atPath: directory.url.appendingPathComponent("events.1.jsonl").path))
    }
}
