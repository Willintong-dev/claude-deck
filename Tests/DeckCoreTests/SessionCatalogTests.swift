import Foundation
import Testing
@testable import DeckCore

struct SessionCatalogTests {
    let directory = TemporaryDirectory()

    @Test func renamingStoresTrimmedNamesAndClearsWithAnEmptyOne() {
        var catalog = SessionCatalog()
        catalog.rename("s1", to: "  Guardia pagos  ")
        #expect(catalog.name(of: "s1") == "Guardia pagos")

        catalog.rename("s1", to: "   ")
        #expect(catalog.name(of: "s1") == nil)
    }

    @Test func groupsCollectSessionsAndReleaseThemWhenDeleted() throws {
        var catalog = SessionCatalog()
        let created = catalog.createGroup(named: "Routing", id: "g1")
        let group = try #require(created)
        #expect(catalog.createGroup(named: "  ") == nil)

        catalog.assign("s1", to: group.id)
        catalog.assign("s2", to: group.id)
        catalog.assign("s3", to: "missing")
        #expect(catalog.members(of: "g1") == ["s1", "s2"])
        #expect(catalog.group(of: "s1")?.name == "Routing")
        #expect(catalog.group(of: "s3") == nil)

        catalog.renameGroup("g1", to: "Routing ms")
        catalog.setCollapsed("g1", true)
        #expect(catalog.group(withId: "g1")?.name == "Routing ms")
        #expect(catalog.group(withId: "g1")?.collapsed == true)

        catalog.assign("s2", to: nil)
        #expect(catalog.members(of: "g1") == ["s1"])

        catalog.deleteGroup("g1")
        #expect(catalog.groups.isEmpty)
        #expect(catalog.group(of: "s1") == nil)
    }

    @Test func deletingASessionForgetsItsNameAndGroup() {
        var catalog = SessionCatalog()
        let group = catalog.createGroup(named: "Pagos", id: "g1")
        catalog.rename("s1", to: "Uno")
        catalog.assign("s1", to: group?.id)
        #expect(catalog.retainedSessionIds == ["s1"])

        catalog.markDeleted("s1", at: date("2026-11-22T10:00:00.000Z"))

        #expect(catalog.name(of: "s1") == nil)
        #expect(catalog.group(of: "s1") == nil)
        #expect(catalog.retainedSessionIds.isEmpty)
        #expect(catalog.deleted["s1"] == date("2026-11-22T10:00:00.000Z"))
    }

    @Test func storeRoundTripsAndToleratesMissingOrPartialFiles() throws {
        let store = SessionCatalogStore(file: directory.url.appendingPathComponent("deck/catalog.json"))
        #expect(store.load() == SessionCatalog())

        var catalog = SessionCatalog()
        catalog.rename("s1", to: "Uno")
        catalog.createGroup(named: "Pagos", id: "g1", at: date("2026-11-22T10:00:00.000Z"))
        catalog.assign("s1", to: "g1")
        catalog.markDeleted("s9", at: date("2026-11-22T11:00:00.000Z"))
        try store.save(catalog)
        #expect(store.load() == catalog)

        write(#"{"names":{"s2":"Dos"}}"#, to: store.file)
        #expect(store.load().name(of: "s2") == "Dos")
        #expect(store.load().groups.isEmpty)
    }
}

struct SessionEraserTests {
    let directory = TemporaryDirectory()
    let sessionId = "8e1f7c2a-1b2c-4d5e-8f90-123456789abc"

    private func eraser(removed: Box<[URL]>) -> SessionEraser {
        SessionEraser(claudeDirectory: directory.url) { url in
            removed.value.append(url)
            try FileManager.default.removeItem(at: url)
        }
    }

    @Test func erasesTheTranscriptSubagentsAndPerSessionFolders() throws {
        let transcript = directory.file("projects/proj/\(sessionId).jsonl")
        write("{}", to: transcript)
        write("{}", to: directory.file("projects/proj/\(sessionId)/subagents/agent-a1.jsonl"))
        write("x", to: directory.file("file-history/\(sessionId)/v1"))
        write("x", to: directory.file("session-env/\(sessionId)/env"))
        let other = directory.file("projects/proj/0f1e2d3c-1b2c-4d5e-8f90-123456789abc.jsonl")
        write("{}", to: other)
        let removed = Box<[URL]>([])

        let erased = try eraser(removed: removed).erase(sessionId)

        #expect(erased.count == 4)
        #expect(removed.value == erased)
        #expect(!FileManager.default.fileExists(atPath: transcript.path))
        #expect(!FileManager.default.fileExists(atPath: directory.url.appendingPathComponent("projects/proj/\(sessionId)").path))
        #expect(!FileManager.default.fileExists(atPath: directory.url.appendingPathComponent("file-history/\(sessionId)").path))
        #expect(FileManager.default.fileExists(atPath: other.path))
    }

    @Test func permanentErasureLeavesNothingBehind() throws {
        let transcript = directory.file("projects/proj/\(sessionId).jsonl")
        write("{}", to: transcript)
        write("x", to: directory.file("session-env/\(sessionId)/env"))

        let erased = try SessionEraser.permanent(claudeDirectory: directory.url).erase(sessionId)

        #expect(erased.count == 2)
        #expect(SessionEraser.permanent(claudeDirectory: directory.url).artifacts(of: sessionId).isEmpty)
        #expect(!FileManager.default.fileExists(atPath: transcript.path))
    }

    @Test func refusesAnythingThatIsNotASessionId() throws {
        write("{}", to: directory.file("projects/proj/x.jsonl"))
        let removed = Box<[URL]>([])

        #expect(try eraser(removed: removed).erase("").isEmpty)
        #expect(try eraser(removed: removed).erase("../projects").isEmpty)
        #expect(try eraser(removed: removed).erase("x").isEmpty)
        #expect(removed.value.isEmpty)
    }
}

struct SessionIndexLifecycleTests {
    let directory = TemporaryDirectory()
    var paths: DeckPaths {
        DeckPaths(projectsDirectory: directory.url.appendingPathComponent("projects"), deckDirectory: directory.url.appendingPathComponent("deck"))
    }

    private func makeIndex() -> SessionIndex {
        try? FileManager.default.createDirectory(at: paths.projectsDirectory, withIntermediateDirectories: true)
        return SessionIndex(paths: paths, now: { date("2026-11-21T12:00:00.000Z") })
    }

    private func sessionFile(_ id: String) -> URL {
        paths.projectsDirectory.appendingPathComponent("proj/\(id).jsonl")
    }

    private func age(_ url: URL, to modified: String) throws {
        try FileManager.default.setAttributes([.modificationDate: date(modified)], ofItemAtPath: url.path)
    }

    @Test func retainedSessionsLoadEvenWhenOlderThanTheRecentWindow() throws {
        write(Lines.user("viejo", at: "2026-10-01T11:00:00.000Z"), to: sessionFile("old"))
        write(Lines.user("otro", at: "2026-10-01T11:00:00.000Z"), to: sessionFile("other"))
        try age(sessionFile("old"), to: "2026-10-01T11:00:00.000Z")
        try age(sessionFile("other"), to: "2026-10-01T11:00:00.000Z")
        let index = makeIndex()

        index.retain(["old"])
        index.fullScan()

        #expect(index.snapshot()["old"] != nil)
        #expect(index.snapshot()["other"] == nil)
    }

    @Test func forgottenSessionsIgnoreTheirOldEventsButNotNewOnes() throws {
        write(Lines.user("uno", at: "2026-11-21T11:00:00.000Z"), to: sessionFile("s1"))
        try? EventLog.append(HookEvent(event: "Stop", sessionId: "s1", timestamp: date("2026-11-21T11:01:00.000Z"), pid: 9), to: paths.eventsFile)
        let index = makeIndex()
        index.fullScan()
        #expect(index.snapshot()["s1"]?.live.status == .idle)

        try FileManager.default.removeItem(at: sessionFile("s1"))
        index.forget("s1", at: date("2026-11-21T11:30:00.000Z"))
        index.handleChanges(at: [sessionFile("s1")])
        #expect(index.snapshot()["s1"] == nil)

        let fresh = makeIndex()
        fresh.bury(["s1": date("2026-11-21T11:30:00.000Z")])
        fresh.fullScan()
        #expect(fresh.snapshot()["s1"] == nil)

        try? EventLog.append(HookEvent(event: "SessionStart", sessionId: "s1", timestamp: date("2026-11-21T11:45:00.000Z"), pid: 10), to: paths.eventsFile)
        fresh.handleChanges(at: [paths.eventsFile])
        #expect(fresh.snapshot()["s1"]?.live.status == .idle)
    }

    @Test func aTranscriptRemovedFromOutsideDisappearsFromTheIndex() throws {
        write(Lines.user("uno", at: "2026-11-21T11:00:00.000Z"), to: sessionFile("s1"))
        let index = makeIndex()
        index.fullScan()
        #expect(index.snapshot()["s1"] != nil)

        try FileManager.default.removeItem(at: sessionFile("s1"))

        #expect(index.handleChanges(at: [sessionFile("s1")]) == ["s1"])
        #expect(index.snapshot()["s1"] == nil)
    }
}

final class Box<Value>: @unchecked Sendable {
    var value: Value
    init(_ value: Value) { self.value = value }
}
