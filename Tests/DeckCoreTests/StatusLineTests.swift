import Foundation
import Testing
@testable import DeckCore

struct StatusLineTests {
    let directory = TemporaryDirectory()
    let sessionId = "11111111-2222-3333-4444-555555555555"

    private func withoutColors(_ text: String) -> String {
        text.replacingOccurrences(of: "\u{1B}\\[[0-9;]*m", with: "", options: .regularExpression)
    }

    private func payload(transcript: URL? = nil, percentage: Double? = nil) -> Data {
        var object: [String: Any] = [
            "session_id": sessionId,
            "cwd": "/repos/ignorado",
            "model": ["id": "claude-opus-5-5", "display_name": "Opus 5.5"],
            "workspace": ["current_dir": "/repos/pagos"],
        ]
        if let transcript { object["transcript_path"] = transcript.path }
        if let percentage { object["context_window"] = ["used_percentage": percentage] }
        return try! JSONSerialization.data(withJSONObject: object)
    }

    @Test func parsesTheClaudePayload() {
        let input = StatusLineInput.parse(payload(percentage: 41.6))
        #expect(input == StatusLineInput(sessionId: sessionId, model: "Opus 5.5", cwd: "/repos/pagos", usedPercentage: 41.6))
        #expect(StatusLineInput.parse(Data("no es json".utf8)) == nil)
        #expect(StatusLineInput.parse(Data(#"{"model":{}}"#.utf8)) == nil)
    }

    @Test func prefersTheDeckNameThenTheTitleThenTheFolder() {
        var catalog = SessionCatalog()
        let input = StatusLineInput(sessionId: sessionId, cwd: "/repos/pagos")
        var titled = TranscriptLine(type: "ai-title")
        titled.aiTitle = "Arreglar webhooks"

        #expect(StatusLine.parts(for: input, catalog: catalog, transcript: []).name == "pagos")
        #expect(StatusLine.parts(for: input, catalog: catalog, transcript: [titled]).name == "Arreglar webhooks")
        catalog.rename(sessionId, to: "Guardia pagos")
        #expect(StatusLine.parts(for: input, catalog: catalog, transcript: [titled]).name == "Guardia pagos")
    }

    @Test func colorsTheContextByHowFullItIs() {
        let catalog = SessionCatalog()
        var assistant = TranscriptLine(type: "assistant")
        assistant.contextTokens = 120_000
        assistant.gitBranch = "feature/x"

        let fromTokens = StatusLine.parts(for: StatusLineInput(sessionId: sessionId), catalog: catalog, transcript: [assistant])
        #expect(fromTokens.context == "120k ctx")
        #expect(fromTokens.contextLevel == .high)
        #expect(fromTokens.branch == "feature/x")

        let fromPercentage = StatusLine.parts(for: StatusLineInput(sessionId: sessionId, usedPercentage: 55), catalog: catalog, transcript: [assistant])
        #expect(fromPercentage.context == "ctx 55%")
        #expect(fromPercentage.contextLevel == .medium)

        let empty = StatusLine.parts(for: StatusLineInput(sessionId: sessionId), catalog: catalog, transcript: [])
        #expect(empty.context == nil)
        #expect(empty.branch == nil)
    }

    @Test func rendersOnlyThePartsItHasWithAnsiColors() {
        let full = StatusLine.render(StatusLineParts(name: "Uno", model: "Opus", context: "ctx 10%", contextLevel: .low, branch: "main"))
        let plain = withoutColors(full)
        #expect(plain == "◆ Uno · Opus · ctx 10% · ⎇ main")
        #expect(full.contains("\u{1B}[32mctx 10%"))

        let minimal = StatusLine.render(StatusLineParts(name: "Uno", model: nil, context: nil, contextLevel: .low, branch: nil))
        #expect(minimal == "\u{1B}[1;34m◆ Uno\u{1B}[0m")
    }

    @Test func readsTheTranscriptTailEndToEnd() {
        let transcript = directory.url.appendingPathComponent("t.jsonl")
        write("""
        {"type":"user","gitBranch":"main","message":{"role":"user","content":"hola"}}
        {"type":"assistant","gitBranch":"main","message":{"usage":{"input_tokens":10,"cache_read_input_tokens":41990}}}

        """, to: transcript)

        let line = StatusLine.line(for: payload(transcript: transcript), catalog: SessionCatalog())
        let plain = line.map(withoutColors)
        #expect(plain == "◆ pagos · Opus 5.5 · 42k ctx · ⎇ main")
        #expect(StatusLine.line(for: Data(), catalog: SessionCatalog()) == nil)
    }
}
