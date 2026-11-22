import Foundation
import Testing
@testable import DeckCore

struct BrainLibraryTests {
    let directory = TemporaryDirectory()
    var library: BrainLibrary { BrainLibrary(root: directory.url.appendingPathComponent("brains"), now: { Date(timeIntervalSince1970: 1_800_000_000) }) }

    @Test func newSessionsStartFromTheTemplateAndAreUnmodified() throws {
        let brain = try library.prepareWorkingBrain(sessionId: "s1", baseSlug: nil, title: "Guardia")

        #expect(brain.baseSlug == nil)
        #expect(library.content(of: library.workingBrainFile("s1")) == BrainLibrary.template(title: "Guardia"))
        #expect(!library.isModified("s1"))
        #expect(library.workingSessionIds() == ["s1"])
    }

    @Test func preparingTwiceKeepsTheExistingBrain() throws {
        try library.prepareWorkingBrain(sessionId: "s1", baseSlug: nil, title: nil)
        try "# notas".write(to: library.workingBrainFile("s1"), atomically: true, encoding: .utf8)

        try library.prepareWorkingBrain(sessionId: "s1", baseSlug: nil, title: "otro")
        #expect(library.content(of: library.workingBrainFile("s1")) == "# notas")
        #expect(library.isModified("s1"))
    }

    @Test func savingCreatesASpecialistAndClearsTheWorkingCopy() throws {
        try library.prepareWorkingBrain(sessionId: "s1", baseSlug: nil, title: nil)
        try "# Guardia\\nhallazgo".write(to: library.workingBrainFile("s1"), atomically: true, encoding: .utf8)

        let saved = try library.save(sessionId: "s1", name: "Guardia de Connectivity")

        #expect(saved.slug == "guardia-de-connectivity")
        #expect(saved.sessionIds == ["s1"])
        #expect(library.savedBrains().map(\.name) == ["Guardia de Connectivity"])
        #expect(library.content(of: library.savedBrainFile(saved.slug)) == "# Guardia\\nhallazgo")
        #expect(library.workingBrain("s1") == nil)
    }

    @Test func aSpecialistEvolvesWhenANewSessionSavesBackIntoIt() throws {
        try library.prepareWorkingBrain(sessionId: "s1", baseSlug: nil, title: nil)
        try "v1".write(to: library.workingBrainFile("s1"), atomically: true, encoding: .utf8)
        let saved = try library.save(sessionId: "s1", name: "PCA4")

        let working = try library.prepareWorkingBrain(sessionId: "s2", baseSlug: saved.slug, title: nil)
        #expect(working.baseSlug == "pca4")
        #expect(library.content(of: library.workingBrainFile("s2")) == "v1")
        #expect(!library.isModified("s2"))

        try "v2".write(to: library.workingBrainFile("s2"), atomically: true, encoding: .utf8)
        #expect(library.isModified("s2"))
        let evolved = try library.save(sessionId: "s2", name: "PCA4")

        #expect(evolved.sessionIds == ["s1", "s2"])
        #expect(library.content(of: library.savedBrainFile("pca4")) == "v2")
        #expect(library.savedBrains().count == 1)
    }

    @Test func discardingRemovesOnlyTheWorkingCopy() throws {
        try library.prepareWorkingBrain(sessionId: "s1", baseSlug: nil, title: nil)
        _ = try library.save(sessionId: "s1", name: "Base")
        try library.prepareWorkingBrain(sessionId: "s2", baseSlug: "base", title: nil)

        try library.discard(sessionId: "s2")
        try library.discard(sessionId: "nunca-existio")

        #expect(library.workingBrain("s2") == nil)
        #expect(library.savedBrain("base") != nil)
    }

    @Test func deletingASpecialistRemovesIt() throws {
        try library.prepareWorkingBrain(sessionId: "s1", baseSlug: nil, title: nil)
        _ = try library.save(sessionId: "s1", name: "Temporal")

        try library.deleteSaved("temporal")
        #expect(library.savedBrains().isEmpty)
        #expect(throws: BrainLibraryError.missingSavedBrain("temporal")) { try library.deleteSaved("temporal") }
    }

    @Test func rejectsUnknownBasesAndEmptyNames() throws {
        #expect(throws: BrainLibraryError.missingSavedBrain("nope")) {
            try library.prepareWorkingBrain(sessionId: "s1", baseSlug: "nope", title: nil)
        }
        try library.prepareWorkingBrain(sessionId: "s1", baseSlug: nil, title: nil)
        #expect(throws: BrainLibraryError.emptyName) { try library.save(sessionId: "s1", name: "   ") }
        #expect(throws: BrainLibraryError.missingWorkingBrain("x")) { try library.save(sessionId: "x", name: "a") }
    }

    @Test func writesASystemPromptWithTheRulesAndThePath() throws {
        try library.prepareWorkingBrain(sessionId: "s1", baseSlug: nil, title: "Guardia")
        let file = try library.writeSystemPrompt(sessionId: "s1")
        let prompt = library.content(of: file)

        #expect(prompt.contains(library.workingBrainFile("s1").path))
        #expect(!prompt.contains("# Guardia"))
        #expect(prompt.contains("\(BrainLibrary.maximumCharacters) caracteres"))
        #expect(throws: BrainLibraryError.missingWorkingBrain("x")) { try library.writeSystemPrompt(sessionId: "x") }
    }

    @Test func buildsReadableSlugs() {
        #expect(BrainLibrary.slug(for: "Guardia de Connectivity") == "guardia-de-connectivity")
        #expect(BrainLibrary.slug(for: "Iniciativa PCA4 · Pre-chargeback") == "iniciativa-pca4-pre-chargeback")
        #expect(BrainLibrary.slug(for: "Cañón Ñandú") == "canon-nandu")
        #expect(BrainLibrary.slug(for: "!!!") == "cerebro")
    }
}

struct BrainLaunchTests {
    @Test func passesTheBrainToClaude() {
        let launch = ClaudeLaunch(
            sessionId: "11111111-2222-3333-4444-555555555555",
            directory: "/repo",
            mode: .new,
            skipPermissions: false,
            systemPromptFile: "/b/s1/system-prompt.md",
            brainDirectory: "/b/s1"
        )
        #expect(launch.claudeArguments == [
            "claude", "--session-id", "11111111-2222-3333-4444-555555555555",
            "--append-system-prompt-file", "/b/s1/system-prompt.md",
            "--allowedTools", "Read(//b/s1/**)", "Edit(//b/s1/**)",
        ])
        #expect(launch.shellCommand(loginShell: "/bin/zsh").contains("'\\''Edit(//b/s1/**)'\\''"))
    }
}

struct ContextReliefTests {
    @Test func injectsTheCurrentBrainWhenTheSessionStartsOrCompacts() throws {
        let directory = TemporaryDirectory()
        let brain = directory.file("BRAIN.md")
        try "# Guardia\n- decisión X".write(to: brain, atomically: true, encoding: .utf8)

        let data = try #require(HookOutput.sessionStartBrain(environment: [BrainPrompt.environmentKey: brain.path], source: "compact"))
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let output = try #require(object["hookSpecificOutput"] as? [String: String])

        #expect(output["hookEventName"] == "SessionStart")
        #expect(output["additionalContext"]?.contains("después de compactar") == true)
        #expect(output["additionalContext"]?.contains("- decisión X") == true)
        #expect(output["additionalContext"]?.contains(brain.path) == true)
    }

    @Test func staysSilentWithoutABrain() throws {
        let directory = TemporaryDirectory()
        let empty = directory.file("EMPTY.md")
        try "  \n".write(to: empty, atomically: true, encoding: .utf8)

        #expect(HookOutput.sessionStartBrain(environment: [:], source: "startup") == nil)
        #expect(HookOutput.sessionStartBrain(environment: [BrainPrompt.environmentKey: "/no/existe"], source: nil) == nil)
        #expect(HookOutput.sessionStartBrain(environment: [BrainPrompt.environmentKey: empty.path], source: nil) == nil)
    }

    @Test func describesWhenTheBrainWasLoaded() {
        #expect(BrainPrompt.loadedContext(brainPath: "/b", content: "c", source: "startup").contains("al iniciar"))
        #expect(BrainPrompt.loadedContext(brainPath: "/b", content: "c", source: "resume").contains("al reanudar"))
        #expect(BrainPrompt.loadedContext(brainPath: "/b", content: "c", source: nil).contains("al iniciar"))
    }

    @Test func instructionsTellClaudeToUseTheBrainInsteadOfRereading() {
        let instructions = BrainPrompt.instructions(brainPath: "/b/BRAIN.md")
        #expect(instructions.contains("/b/BRAIN.md"))
        #expect(instructions.contains("No releas el transcript"))
        #expect(BrainPrompt.compactCommand.hasPrefix("/compact "))
    }

    @Test func launchesTmuxWithTheBrainEnvironment() {
        let tmux = Tmux(executable: URL(fileURLWithPath: "/t"), configFile: URL(fileURLWithPath: "/c"), socketName: "s")
        let launch = ClaudeLaunch(
            sessionId: "11111111-2222-3333-4444-555555555555",
            directory: "/repo",
            mode: .new,
            skipPermissions: false,
            environment: [BrainPrompt.environmentKey: "/b/BRAIN.md"]
        )
        let arguments = tmux.newSessionArguments(launch, loginShell: "/bin/zsh")
        let flag = arguments.firstIndex(of: "-e")
        #expect(flag.map { arguments[$0 + 1] } == "CLAUDE_DECK_BRAIN=/b/BRAIN.md")
        #expect(arguments.last == launch.shellCommand(loginShell: "/bin/zsh"))
    }

    @Test func measuresTheContextOfTheLatestMainAssistantMessage() throws {
        let usage = #"{"type":"assistant","message":{"usage":{"input_tokens":2,"cache_creation_input_tokens":4800,"cache_read_input_tokens":120000,"output_tokens":300},"content":[]}}"#
        let sidechain = #"{"type":"assistant","isSidechain":true,"message":{"usage":{"input_tokens":5},"content":[]}}"#
        var summary = SessionSummary()
        summary.apply(try #require(TranscriptLine.parse(Data(usage.utf8))))
        summary.apply(try #require(TranscriptLine.parse(Data(sidechain.utf8))))

        #expect(summary.contextTokens == 124_802)
        #expect(summary.needsContextRelief)
        #expect(SessionSummary.formatTokens(124_802) == "124k")
        #expect(SessionSummary.formatTokens(950) == "950")
    }
}
