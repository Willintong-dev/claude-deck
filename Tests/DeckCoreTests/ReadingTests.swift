import Foundation
import Testing
@testable import DeckCore

struct LineBufferTests {
    @Test func returnsOnlyCompleteLinesAndKeepsTheRemainder() {
        var buffer = LineBuffer()
        let first = buffer.append(Data("one\ntw".utf8))
        let second = buffer.append(Data("o\n\nthree".utf8))
        let third = buffer.append(Data("\n".utf8))

        #expect(first.map { String(decoding: $0, as: UTF8.self) } == ["one"])
        #expect(second.map { String(decoding: $0, as: UTF8.self) } == ["two"])
        #expect(third.map { String(decoding: $0, as: UTF8.self) } == ["three"])
    }
}

struct TailReaderTests {
    @Test func readsOnlyAppendedLinesOnSubsequentCalls() {
        let directory = TemporaryDirectory()
        let file = directory.file("log.jsonl")
        write("a\nb\n", to: file)
        let reader = TailReader(url: file, initialWindow: 1024)

        #expect(reader.readNewLines().count == 2)
        append("c\nd", to: file)
        #expect(reader.readNewLines().map { String(decoding: $0, as: UTF8.self) } == ["c"])
        append("\n", to: file)
        #expect(reader.readNewLines().map { String(decoding: $0, as: UTF8.self) } == ["d"])
        #expect(reader.readNewLines().isEmpty)
    }

    @Test func startsInsideTheWindowAndDropsThePartialFirstLine() {
        let directory = TemporaryDirectory()
        let file = directory.file("big.jsonl")
        write("first-long-line\nsecond\nthird\n", to: file)
        let reader = TailReader(url: file, initialWindow: 10)

        #expect(reader.readNewLines().map { String(decoding: $0, as: UTF8.self) } == ["third"])
    }

    @Test func restartsFromTheBeginningWhenTheFileIsTruncated() {
        let directory = TemporaryDirectory()
        let file = directory.file("rotated.jsonl")
        write("old-1\nold-2\n", to: file)
        let reader = TailReader(url: file, initialWindow: 1024)
        _ = reader.readNewLines()

        write("new\n", to: file)
        #expect(reader.readNewLines().map { String(decoding: $0, as: UTF8.self) } == ["new"])
    }

    @Test func returnsNothingForAMissingFile() {
        let reader = TailReader(url: URL(fileURLWithPath: "/nonexistent/\(UUID().uuidString)"), initialWindow: 10)
        #expect(reader.readNewLines().isEmpty)
    }
}

struct TranscriptLineTests {
    @Test func extractsTextFromAssistantBlocksIgnoringThinking() throws {
        let line = try #require(TranscriptLine.parse(Data(Lines.assistant("Hola", at: "2026-11-21T10:00:00.000Z", uuid: "u1").utf8)))

        #expect(line.type == "assistant")
        #expect(line.timestamp == date("2026-11-21T10:00:00.000Z"))
        #expect(line.message == TranscriptMessage(id: "u1", role: .assistant, text: "Hola", timestamp: date("2026-11-21T10:00:00.000Z")))
    }

    @Test func readsContextFromUserLines() throws {
        let line = try #require(TranscriptLine.parse(Data(Lines.user("arranca", at: "2026-11-21T10:00:00.000Z", cwd: "/x/y", branch: "feature/A").utf8)))

        #expect(line.cwd == "/x/y")
        #expect(line.gitBranch == "feature/A")
        #expect(line.message?.text == "arranca")
    }

    @Test func ignoresToolResultsMetaAndTaggedContent() throws {
        let toolResult = try #require(TranscriptLine.parse(Data(Lines.toolResult(at: "2026-11-21T10:00:00.000Z").utf8)))
        let meta = try #require(TranscriptLine.parse(Data(#"{"type":"user","isMeta":true,"message":{"content":"hidden"}}"#.utf8)))
        let tagged = try #require(TranscriptLine.parse(Data(#"{"type":"user","message":{"content":"<command-name>/clear</command-name>"}}"#.utf8)))

        #expect(toolResult.message == nil)
        #expect(meta.message == nil)
        #expect(tagged.message == nil)
    }

    @Test func readsTitleAndLastPromptRecords() throws {
        let title = try #require(TranscriptLine.parse(Data(Lines.title("Mi sesión").utf8)))
        let prompt = try #require(TranscriptLine.parse(Data(#"{"type":"last-prompt","lastPrompt":"haz X"}"#.utf8)))

        #expect(title.aiTitle == "Mi sesión")
        #expect(prompt.lastPrompt == "haz X")
    }

    @Test func rejectsInvalidAndOversizedLines() {
        #expect(TranscriptLine.parse(Data("not json".utf8)) == nil)
        #expect(TranscriptLine.parse(Data(#"{"no":"type"}"#.utf8)) == nil)
        let huge = #"{"type":"user","pad":""# + String(repeating: "x", count: TranscriptLine.maximumParsedLineSize) + #""}"#
        #expect(TranscriptLine.parse(Data(huge.utf8)) == nil)
    }
}

struct SessionSummaryTests {
    @Test func accumulatesTitleContextActivityAndPreview() {
        var summary = SessionSummary()
        for raw in [
            Lines.user("primera", at: "2026-11-21T10:00:00.000Z", cwd: "/repo/app", branch: "main"),
            Lines.title("Título IA"),
            Lines.assistant(String(repeating: "r", count: 500), at: "2026-11-21T10:01:00.000Z"),
            Lines.toolResult(at: "2026-11-21T10:02:00.000Z"),
        ] {
            if let line = TranscriptLine.parse(Data(raw.utf8)) { summary.apply(line) }
        }

        #expect(summary.displayTitle == "Título IA")
        #expect(summary.cwd == "/repo/app")
        #expect(summary.gitBranch == "main")
        #expect(summary.lastActivity == date("2026-11-21T10:02:00.000Z"))
        #expect(summary.lastConversationActivity == date("2026-11-21T10:02:00.000Z"))
        #expect(summary.preview?.count == SessionSummary.previewLength)
    }

    @Test func fallsBackToPromptThenFolderForTheTitle() {
        var summary = SessionSummary()
        #expect(summary.displayTitle == "Sesión sin título")
        summary.cwd = "/a/proyecto"
        #expect(summary.displayTitle == "proyecto")
        summary.lastPrompt = "revisa el PR"
        #expect(summary.displayTitle == "revisa el PR")
    }
}

struct TranscriptPathTests {
    let root = URL(fileURLWithPath: "/home/.claude/projects")

    @Test func classifiesSessionSubagentAndMetaFiles() {
        #expect(TranscriptPath.classify(root.appendingPathComponent("p/abc.jsonl"), projectsDirectory: root) == .session(sessionId: "abc", project: "p"))
        #expect(TranscriptPath.classify(root.appendingPathComponent("p/abc/subagents/agent-x1.jsonl"), projectsDirectory: root) == .subagent(sessionId: "abc", agentId: "x1", project: "p"))
        #expect(TranscriptPath.classify(root.appendingPathComponent("p/abc/subagents/agent-x1.meta.json"), projectsDirectory: root) == .subagentMeta(sessionId: "abc", agentId: "x1", project: "p"))
    }

    @Test func ignoresUnrelatedFiles() {
        #expect(TranscriptPath.classify(root.appendingPathComponent("p/abc/tool-results/out.txt"), projectsDirectory: root) == nil)
        #expect(TranscriptPath.classify(root.appendingPathComponent("p/memory/MEMORY.md"), projectsDirectory: root) == nil)
        #expect(TranscriptPath.classify(URL(fileURLWithPath: "/elsewhere/p/abc.jsonl"), projectsDirectory: root) == nil)
        #expect(TranscriptPath.classify(root.appendingPathComponent("p/abc/subagents/notes.jsonl"), projectsDirectory: root) == nil)
    }
}

struct TranscriptTailTests {
    @Test func returnsTheLastConversationMessagesInOrder() {
        let directory = TemporaryDirectory()
        let file = directory.file("s.jsonl")
        var text = ""
        for index in 0..<10 {
            text += Lines.user("pregunta \(index)", at: "2026-11-21T10:00:0\(index).000Z")
            text += Lines.toolResult(at: "2026-11-21T10:00:0\(index).500Z")
        }
        write(text, to: file)

        let messages = TranscriptTail.recentMessages(at: file, limit: 3)
        #expect(messages.map(\.text) == ["pregunta 7", "pregunta 8", "pregunta 9"])
    }
}
