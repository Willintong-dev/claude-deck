import Foundation

public struct SubagentState: Equatable, Sendable, Identifiable {
    public let id: String
    public let sessionId: String
    public var transcriptURL: URL?
    public var meta: SubagentMeta?
    public var summary = SessionSummary()

    public init(id: String, sessionId: String) {
        self.id = id
        self.sessionId = sessionId
    }

    public static let activityTimeout: TimeInterval = 15 * 60

    public func isRunning(at now: Date) -> Bool {
        guard meta?.finished != true, let last = summary.lastActivity else { return false }
        return now.timeIntervalSince(last) < Self.activityTimeout
    }
    public var displayTitle: String { meta?.description ?? summary.lastPrompt.map { String($0.prefix(60)) } ?? "Subagente \(id.prefix(7))" }
}

public struct SessionState: Equatable, Sendable, Identifiable {
    public let id: String
    public var project: String
    public var transcriptURL: URL?
    public var summary = SessionSummary()
    public var live = LiveState()
    public var subagents: [String: SubagentState] = [:]

    public init(id: String, project: String) {
        self.id = id
        self.project = project
    }

    public func runningSubagentCount(at now: Date) -> Int {
        subagents.values.filter { $0.isRunning(at: now) }.count
    }

    public var orderedSubagents: [SubagentState] {
        subagents.values.sorted {
            ($0.summary.lastActivity ?? .distantPast) > ($1.summary.lastActivity ?? .distantPast)
        }
    }
}

public final class SessionIndex {
    public let paths: DeckPaths
    public private(set) var sessions: [String: SessionState] = [:]
    public private(set) var liveStates: [String: LiveState] = [:]

    private let recentWindow: TimeInterval
    private let initialTailBytes: UInt64
    private let now: () -> Date
    private var readers: [URL: TailReader] = [:]
    private var eventsReader: TailReader?
    private var retainedSessionIds: Set<String> = []
    private var tombstones: [String: Date] = [:]

    public init(
        paths: DeckPaths,
        recentWindow: TimeInterval = 7 * 24 * 3600,
        initialTailBytes: UInt64 = 256 * 1024,
        now: @escaping () -> Date = Date.init
    ) {
        self.paths = paths
        self.recentWindow = recentWindow
        self.initialTailBytes = initialTailBytes
        self.now = now
    }

    public func snapshot() -> [String: SessionState] {
        var merged = sessions
        for (id, live) in liveStates {
            if merged[id] != nil {
                merged[id]?.live = live
            } else if live.status.isActive {
                var placeholder = SessionState(id: id, project: "")
                placeholder.summary.cwd = live.cwd
                placeholder.live = live
                merged[id] = placeholder
            }
        }
        return merged
    }

    public func retain(_ sessionIds: Set<String>) {
        retainedSessionIds = sessionIds
    }

    public func bury(_ tombstones: [String: Date]) {
        self.tombstones = tombstones
        for id in tombstones.keys { drop(id) }
    }

    public func forget(_ sessionId: String, at date: Date) {
        tombstones[sessionId] = date
        drop(sessionId)
    }

    private func drop(_ sessionId: String) {
        sessions.removeValue(forKey: sessionId)
        liveStates.removeValue(forKey: sessionId)
        readers = readers.filter { url, _ in
            url.deletingPathExtension().lastPathComponent != sessionId && !url.path.contains("/\(sessionId)/")
        }
    }

    @discardableResult
    public func fullScan() -> Set<String> {
        var changed: Set<String> = []
        let cutoff = now().addingTimeInterval(-recentWindow)
        let fileManager = FileManager.default
        let projects = (try? fileManager.contentsOfDirectory(at: paths.projectsDirectory, includingPropertiesForKeys: nil)) ?? []
        for project in projects {
            let files = (try? fileManager.contentsOfDirectory(
                at: project,
                includingPropertiesForKeys: [.contentModificationDateKey]
            )) ?? []
            for file in files where file.pathExtension == "jsonl" {
                let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
                let sessionId = file.deletingPathExtension().lastPathComponent
                guard (modified ?? .distantPast) >= cutoff || retainedSessionIds.contains(sessionId) else { continue }
                changed.formUnion(handleChanges(at: [file]))
                let subagents = file.deletingPathExtension().appendingPathComponent("subagents")
                let agentFiles = (try? fileManager.contentsOfDirectory(at: subagents, includingPropertiesForKeys: nil)) ?? []
                changed.formUnion(handleChanges(at: agentFiles.sorted { $0.lastPathComponent < $1.lastPathComponent }))
            }
        }
        changed.formUnion(handleChanges(at: [paths.eventsFile]))
        return changed
    }

    @discardableResult
    public func handleChanges(at urls: [URL]) -> Set<String> {
        var changed: Set<String> = []
        for url in urls {
            autoreleasepool {
                changed.formUnion(handleChange(at: url))
            }
        }
        return changed
    }

    private func handleChange(at url: URL) -> Set<String> {
        let resolved = url.standardizedFileURL
        if resolved.path == paths.eventsFile.path {
            return ingestEvents()
        }
        switch TranscriptPath.classify(resolved, projectsDirectory: paths.projectsDirectory) {
        case let .session(sessionId, project)?:
            return ingestSessionTranscript(resolved, sessionId: sessionId, project: project) ? [sessionId] : []
        case let .subagent(sessionId, agentId, project)?:
            return ingestSubagentTranscript(resolved, sessionId: sessionId, agentId: agentId, project: project) ? [sessionId] : []
        case let .subagentMeta(sessionId, agentId, project)?:
            return ingestSubagentMeta(resolved, sessionId: sessionId, agentId: agentId, project: project) ? [sessionId] : []
        case nil:
            return []
        }
    }

    public func markProcessExited(pid: Int32) -> Set<String> {
        var changed: Set<String> = []
        for (id, live) in liveStates where live.pid == pid {
            liveStates[id]?.processExited(at: now())
            changed.insert(id)
        }
        return changed
    }

    public func registerRunningProcesses(_ processes: [Int32: String]) -> Set<String> {
        var changed: Set<String> = []
        for (pid, sessionId) in processes {
            let before = liveStates[sessionId]
            var live = before ?? LiveState()
            live.attach(pid: pid)
            if live != before {
                liveStates[sessionId] = live
                changed.insert(sessionId)
            }
        }
        return changed
    }

    public func sessionsWithoutProcess(among ids: Set<String>) -> Set<String> {
        ids.filter { liveStates[$0]?.pid == nil }
    }

    public func trackedPids() -> [Int32: String] {
        var result: [Int32: String] = [:]
        for (id, live) in liveStates {
            if let pid = live.pid, live.status.isActive { result[pid] = id }
        }
        return result
    }

    private func ingestSessionTranscript(_ url: URL, sessionId: String, project: String) -> Bool {
        guard FileManager.default.fileExists(atPath: url.path) else {
            readers.removeValue(forKey: url)
            return sessions.removeValue(forKey: sessionId) != nil
        }
        let lines = reader(for: url).readNewLines()
        if sessions[sessionId] == nil {
            sessions[sessionId] = SessionState(id: sessionId, project: project)
        }
        sessions[sessionId]?.transcriptURL = url
        guard !lines.isEmpty else { return sessions[sessionId]?.summary.lastActivity == nil }
        var summary = sessions[sessionId]?.summary ?? SessionSummary()
        for data in lines {
            guard let line = TranscriptLine.parse(data) else { continue }
            summary.apply(line)
        }
        sessions[sessionId]?.summary = summary
        if let activity = summary.lastConversationActivity {
            liveStates[sessionId]?.observeConversationActivity(at: activity)
        }
        return true
    }

    private func ingestSubagentTranscript(_ url: URL, sessionId: String, agentId: String, project: String) -> Bool {
        guard FileManager.default.fileExists(atPath: url.path) else {
            readers.removeValue(forKey: url)
            return sessions[sessionId]?.subagents.removeValue(forKey: agentId) != nil
        }
        let lines = reader(for: url).readNewLines()
        ensureSubagent(sessionId: sessionId, agentId: agentId, project: project)
        sessions[sessionId]?.subagents[agentId]?.transcriptURL = url
        var summary = sessions[sessionId]?.subagents[agentId]?.summary ?? SessionSummary()
        for data in lines {
            guard let line = TranscriptLine.parse(data) else { continue }
            summary.apply(line)
        }
        sessions[sessionId]?.subagents[agentId]?.summary = summary
        return true
    }

    private func ingestSubagentMeta(_ url: URL, sessionId: String, agentId: String, project: String) -> Bool {
        guard let meta = SubagentMeta.load(from: url) else { return false }
        ensureSubagent(sessionId: sessionId, agentId: agentId, project: project)
        guard sessions[sessionId]?.subagents[agentId]?.meta != meta else { return false }
        sessions[sessionId]?.subagents[agentId]?.meta = meta
        return true
    }

    private func ensureSubagent(sessionId: String, agentId: String, project: String) {
        if sessions[sessionId] == nil {
            sessions[sessionId] = SessionState(id: sessionId, project: project)
        }
        if sessions[sessionId]?.subagents[agentId] == nil {
            sessions[sessionId]?.subagents[agentId] = SubagentState(id: agentId, sessionId: sessionId)
        }
    }

    private func ingestEvents() -> Set<String> {
        if eventsReader == nil {
            eventsReader = TailReader(url: paths.eventsFile, initialWindow: initialTailBytes)
        }
        var changed: Set<String> = []
        for line in eventsReader?.readNewLines() ?? [] {
            guard let event = HookEvent.decode(line: line) else { continue }
            if let buried = tombstones[event.sessionId], event.timestamp <= buried { continue }
            var live = liveStates[event.sessionId] ?? LiveState()
            live.apply(event)
            if let activity = sessions[event.sessionId]?.summary.lastConversationActivity {
                live.observeConversationActivity(at: activity)
            }
            liveStates[event.sessionId] = live
            changed.insert(event.sessionId)
        }
        return changed
    }

    private func reader(for url: URL) -> TailReader {
        if let existing = readers[url] { return existing }
        let created = TailReader(url: url, initialWindow: initialTailBytes)
        readers[url] = created
        return created
    }
}
