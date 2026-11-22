import DeckCore
import Foundation

struct DeckSnapshot: Equatable {
    var sessions: [String: SessionState] = [:]
    var ownedSessionIds: Set<String> = []
}

final class DeckEngine: @unchecked Sendable {
    private let queue = DispatchQueue(label: "claude-deck.engine", qos: .utility, autoreleaseFrequency: .workItem)
    private let index: SessionIndex
    private let tmux: Tmux?
    private var fileWatcher: FileWatcher?
    private var processWatcher: ProcessWatcher?
    private var ownedSessionIds: Set<String> = []
    private var lastProcessScan = Date.distantPast
    private var processScanScheduled = false
    private let publish: (DeckSnapshot) -> Void

    private static let processScanInterval: TimeInterval = 5

    init(paths: DeckPaths = .standard, tmux: Tmux?, catalog: SessionCatalog, publish: @escaping (DeckSnapshot) -> Void) {
        index = SessionIndex(paths: paths)
        index.retain(catalog.retainedSessionIds)
        index.bury(catalog.deleted)
        self.tmux = tmux
        self.publish = publish
    }

    func start() {
        queue.async { [self] in
            let paths = index.paths
            try? FileManager.default.createDirectory(at: paths.deckDirectory, withIntermediateDirectories: true)
            try? tmux?.writeConfiguration()
            EventLog.rotateIfNeeded(paths.eventsFile)
            processWatcher = ProcessWatcher(queue: queue) { [weak self] pid in
                self?.processExited(pid)
            }
            index.fullScan()
            scanProcesses()
            refreshOwned()
            refreshProcessWatches()
            emit()
            fileWatcher = FileWatcher(
                paths: [paths.projectsDirectory, paths.deckDirectory],
                latency: 1.0,
                queue: queue
            ) { [weak self] change in
                self?.handle(change)
            }
        }
    }

    func refreshOwnedSessions() {
        queue.async { [self] in
            refreshOwned()
            scanProcesses()
            refreshProcessWatches()
            emit()
        }
    }

    func retain(_ sessionIds: Set<String>) {
        queue.async { [self] in
            index.retain(sessionIds)
        }
    }

    func forget(_ sessionId: String, at date: Date) {
        queue.async { [self] in
            index.forget(sessionId, at: date)
            refreshOwned()
            emit()
        }
    }

    private func handle(_ change: FileWatcher.Change) {
        let changed: Set<String>
        switch change {
        case let .files(urls):
            changed = index.handleChanges(at: urls)
        case .rescanRequired:
            changed = index.fullScan()
        }
        guard !changed.isEmpty else { return }
        if !index.sessionsWithoutProcess(among: changed).isEmpty {
            scheduleProcessScan()
        }
        refreshProcessWatches()
        emit()
    }

    private func scheduleProcessScan() {
        guard !processScanScheduled else { return }
        let wait = max(0, Self.processScanInterval - Date().timeIntervalSince(lastProcessScan))
        processScanScheduled = true
        queue.asyncAfter(deadline: .now() + wait) { [weak self] in
            guard let self else { return }
            processScanScheduled = false
            if scanProcesses() {
                refreshProcessWatches()
                emit()
            }
        }
    }

    @discardableResult
    private func scanProcesses() -> Bool {
        lastProcessScan = Date()
        return !index.registerRunningProcesses(ClaudeProcesses.running()).isEmpty
    }

    private func refreshOwned() {
        ownedSessionIds = tmux?.ownedSessionIds() ?? []
    }

    private func processExited(_ pid: Int32) {
        guard !index.markProcessExited(pid: pid).isEmpty else { return }
        refreshOwned()
        emit()
    }

    private func refreshProcessWatches() {
        var alive: Set<Int32> = []
        var exited = false
        for pid in index.trackedPids().keys {
            if ProcessTree.isAlive(pid) {
                alive.insert(pid)
            } else {
                exited = !index.markProcessExited(pid: pid).isEmpty || exited
            }
        }
        processWatcher?.watch(alive)
        if exited { emit() }
    }

    private func emit() {
        let snapshot = DeckSnapshot(sessions: index.snapshot(), ownedSessionIds: ownedSessionIds)
        DispatchQueue.main.async { [publish] in
            publish(snapshot)
        }
    }
}
