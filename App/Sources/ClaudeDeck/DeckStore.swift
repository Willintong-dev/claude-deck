import AppKit
import DeckCore
import Foundation
import Observation

@MainActor
@Observable
final class DeckStore {
    static let shared = DeckStore()

    private(set) var sessions: [String: SessionState] = [:]
    private(set) var ownedSessionIds: Set<String> = []
    private(set) var pendingLaunches: [String: PendingLaunch] = [:]
    var selection: SidebarItem.ID?
    var showingNewSession = false
    var subagentDraft = ""
    var takeoverCandidate: SessionState?
    private(set) var takingOver: Set<String> = []
    var notice: String?
    var skipPermissions: Bool = UserDefaults.standard.object(forKey: "skipPermissions") as? Bool ?? true {
        didSet { UserDefaults.standard.set(skipPermissions, forKey: "skipPermissions") }
    }
    let transcript = TranscriptModel()
    private(set) var savedBrains: [SavedBrain] = []
    var newSessionBrain: String?
    var closing: ClosingRequest?
    var closingName = ""
    private(set) var finalizing: [String: Date] = [:]
    private(set) var relieving: [String: ContextRelief] = [:]
    var brainPopoverSessionId: String?
    private(set) var catalog: SessionCatalog
    private(set) var appearance: AppearanceSettings
    var appearancePopoverSessionId: String?
    var appearanceScope: AppearanceScope = AppearanceScope(rawValue: UserDefaults.standard.string(forKey: "appearanceScope") ?? "") ?? .session {
        didSet { UserDefaults.standard.set(appearanceScope.rawValue, forKey: "appearanceScope") }
    }
    private(set) var notifications: NotificationSettings
    var notificationEditingKind: NotificationKind = .permission
    var namePrompt: NamePrompt?
    var deletionCandidate: SessionState?
    private(set) var deleting: Set<String> = []

    @ObservationIgnored let library = BrainLibrary.standard
    @ObservationIgnored private let catalogStore = SessionCatalogStore.standard
    @ObservationIgnored private let appearanceStore = AppearanceStore.standard
    @ObservationIgnored private let notificationStore = NotificationStore.standard
    @ObservationIgnored private var detector = NotificationDetector()
    @ObservationIgnored private var closingHandled: Set<String> = []
    @ObservationIgnored private var closingQueue: [ClosingRequest] = []
    @ObservationIgnored private var checkedOrphanBrains = false

    @ObservationIgnored private var engine: DeckEngine?
    @ObservationIgnored let tmux: Tmux?
    @ObservationIgnored private let actions = DispatchQueue(label: "claude-deck.actions", qos: .userInitiated)

    init() {
        catalog = catalogStore.load()
        appearance = appearanceStore.load()
        notifications = notificationStore.load()
        tmux = Tmux.locate().map {
            Tmux(executable: $0, configFile: DeckPaths.standard.deckDirectory.appendingPathComponent("tmux.conf"))
        }
    }

    func start() {
        guard engine == nil else { return }
        TerminalHost.shared.tmux = tmux
        TerminalHost.shared.appearance = { [weak self] id in
            self?.appearance.resolved(for: id) ?? .standard
        }
        TerminalHost.shared.onPinch = { [weak self] id, steps in
            guard let self else { return }
            self.zoom(id, steps: steps, scope: self.appearanceScope)
        }
        applyAppTheme()
        DeckNotifier.shared.onOpen = { [weak self] id in self?.reveal(id) }
        TerminalHost.shared.onDetached = { [weak self] _ in
            self?.engine?.refreshOwnedSessions()
        }
        refreshBrains()
        let engine = DeckEngine(tmux: tmux, catalog: catalog) { [weak self] snapshot in
            MainActor.assumeIsolated {
                self?.apply(snapshot)
            }
        }
        self.engine = engine
        engine.start()
    }

    private func apply(_ snapshot: DeckSnapshot) {
        let vanished = ownedSessionIds.subtracting(snapshot.ownedSessionIds)
        if snapshot.sessions != sessions { sessions = snapshot.sessions }
        if snapshot.ownedSessionIds != ownedSessionIds { ownedSessionIds = snapshot.ownedSessionIds }
        for id in vanished where !closingHandled.contains(id) && closing?.sessionId != id {
            offerToKeepBrain(of: id, mode: .ended)
        }
        if !checkedOrphanBrains {
            checkedOrphanBrains = true
            for id in library.workingSessionIds() where !snapshot.ownedSessionIds.contains(id) {
                offerToKeepBrain(of: id, mode: .ended)
            }
        }
        advanceContextRelief(using: snapshot)
        announce(detector.triggers(in: snapshot.sessions) { self.title(of: $0) })
        for (id, requestedAt) in finalizing {
            guard let live = snapshot.sessions[id]?.live else { continue }
            if live.status == .idle, (live.since ?? .distantPast) > requestedAt {
                completeClosing(id)
            }
        }
        let now = Date()
        pendingLaunches = pendingLaunches.filter { id, pending in
            snapshot.sessions[id] == nil
                && (snapshot.ownedSessionIds.contains(id) || now.timeIntervalSince(pending.createdAt) < PendingLaunch.gracePeriod)
        }
    }

    private func announce(_ triggers: [AlertTrigger]) {
        for trigger in triggers where !isQuiet(trigger) {
            guard let alert = notifications.alert(for: trigger) else { continue }
            DeckNotifier.shared.show(alert, settings: notifications)
        }
    }

    private func isQuiet(_ trigger: AlertTrigger) -> Bool {
        let id = trigger.sessionId
        if trigger.kind == .sessionEnded,
           deleting.contains(id) || closingHandled.contains(id) || finalizing[id] != nil || closing?.sessionId == id {
            return true
        }
        guard notifications.quietWhenViewing, NSApp.isActive, MainWindow.shared.isKey else { return false }
        switch selection {
        case let .session(selected)?: return selected == id
        case let .subagent(parent, _)?: return parent == id
        default: return false
        }
    }

    func reveal(_ sessionId: String) {
        guard sessions[sessionId] != nil else { return }
        selection = .session(sessionId)
        MainWindow.shared.show()
    }

    func updateNotifications(_ change: (inout NotificationSettings) -> Void) {
        var updated = notifications
        change(&updated)
        guard updated != notifications else { return }
        notifications = updated
        try? notificationStore.save(updated)
    }

    var allSessions: [String: SessionState] {
        var merged = sessions
        for (id, pending) in pendingLaunches where merged[id] == nil {
            var placeholder = SessionState(id: id, project: "")
            placeholder.summary.cwd = pending.directory
            placeholder.live.status = .open
            merged[id] = placeholder
        }
        return merged
    }

    var activeSessions: [SessionState] {
        sorted(ungroupedSessions.filter { isLive($0) })
    }

    var recentSessions: [SessionState] {
        sorted(ungroupedSessions.filter { !isLive($0) })
    }

    var groups: [SessionGroup] { catalog.groups }

    func sessions(in group: SessionGroup) -> [SessionState] {
        let members = catalog.members(of: group.id)
        return sorted(allSessions.values.filter { members.contains($0.id) })
    }

    private var ungroupedSessions: [SessionState] {
        allSessions.values.filter { catalog.group(of: $0.id) == nil }
    }

    private func isLive(_ session: SessionState) -> Bool {
        session.live.status.isActive || ownedSessionIds.contains(session.id)
    }

    func title(of session: SessionState) -> String {
        catalog.name(of: session.id) ?? session.summary.displayTitle
    }

    func isCollapsed(_ group: SessionGroup) -> Bool {
        catalog.group(withId: group.id)?.collapsed ?? false
    }

    func setCollapsed(_ group: SessionGroup, _ collapsed: Bool) {
        updateCatalog { $0.setCollapsed(group.id, collapsed) }
    }

    func requestRename(_ session: SessionState) {
        namePrompt = NamePrompt(kind: .renameSession(session.id), text: title(of: session))
    }

    func requestNewGroup(assigning sessionId: String?) {
        namePrompt = NamePrompt(kind: .newGroup(assigning: sessionId), text: "")
    }

    func requestRenameGroup(_ group: SessionGroup) {
        namePrompt = NamePrompt(kind: .renameGroup(group.id), text: group.name)
    }

    func submitNamePrompt() {
        guard let prompt = namePrompt else { return }
        namePrompt = nil
        switch prompt.kind {
        case let .renameSession(id):
            updateCatalog { $0.rename(id, to: prompt.text) }
        case let .newGroup(sessionId):
            updateCatalog { catalog in
                guard let group = catalog.createGroup(named: prompt.text), let sessionId else { return }
                catalog.assign(sessionId, to: group.id)
            }
        case let .renameGroup(id):
            updateCatalog { $0.renameGroup(id, to: prompt.text) }
        }
    }

    func group(of sessionId: String) -> SessionGroup? {
        catalog.group(of: sessionId)
    }

    func move(_ sessionId: String, to group: SessionGroup?) {
        updateCatalog { $0.assign(sessionId, to: group?.id) }
    }

    func deleteGroup(_ group: SessionGroup) {
        updateCatalog { $0.deleteGroup(group.id) }
    }

    var focusedTerminalSessionId: String? {
        guard case let .session(id) = selection, isOwned(id) else { return nil }
        return id
    }

    func terminalAppearance(for sessionId: String?) -> TerminalAppearance {
        appearance.resolved(for: sessionId)
    }

    func isAppearanceCustomized(_ sessionId: String) -> Bool {
        appearance.isCustomized(sessionId)
    }

    func updateAppearance(_ sessionId: String?, scope: AppearanceScope, _ change: (inout TerminalAppearance) -> Void) {
        updateAppearanceSettings { $0.update(sessionId, scope: scope, change) }
    }

    func zoom(_ sessionId: String?, steps: Int, scope: AppearanceScope = .session) {
        updateAppearanceSettings { $0.zoom(sessionId, steps: steps, scope: scope) }
    }

    func resetZoom(_ sessionId: String, scope: AppearanceScope) {
        updateAppearanceSettings { $0.resetZoom(sessionId, scope: scope) }
    }

    func resetAppearance(_ sessionId: String) {
        updateAppearanceSettings { $0.reset(sessionId) }
    }

    var appTheme: AppTheme {
        get { appearance.appTheme }
        set { updateAppearanceSettings { $0.appTheme = newValue } }
    }

    private func updateAppearanceSettings(_ change: (inout AppearanceSettings) -> Void) {
        var updated = appearance
        change(&updated)
        guard updated != appearance else { return }
        let themeChanged = updated.appTheme != appearance.appTheme
        appearance = updated
        try? appearanceStore.save(updated)
        TerminalHost.shared.refreshAppearance()
        if themeChanged { applyAppTheme() }
    }

    private func applyAppTheme() {
        switch appearance.appTheme {
        case .system: NSApplication.shared.appearance = nil
        case .light: NSApplication.shared.appearance = NSAppearance(named: .aqua)
        case .dark: NSApplication.shared.appearance = NSAppearance(named: .darkAqua)
        }
    }

    func canDelete(_ session: SessionState) -> Bool {
        runningElsewhere(session) == nil && !deleting.contains(session.id) && SessionEraser.isValidSessionId(session.id)
    }

    func requestDelete(_ session: SessionState) {
        guard canDelete(session) else {
            notice = "Esta sesión está abierta en otro programa. Ciérrala allí antes de borrarla."
            return
        }
        deletionCandidate = session
    }

    func confirmDelete() {
        guard let session = deletionCandidate else { return }
        deletionCandidate = nil
        guard canDelete(session) else { return }
        let id = session.id
        let owned = isOwned(id)
        let pid = session.live.pid
        deleting.insert(id)
        closingHandled.insert(id)
        relieving.removeValue(forKey: id)
        finalizing.removeValue(forKey: id)
        pendingLaunches.removeValue(forKey: id)
        if case let .session(selected) = selection, selected == id { selection = nil }
        if case let .subagent(parent, _) = selection, parent == id { selection = nil }
        TerminalHost.shared.forget(id)
        let library = library
        actions.async { [weak self, tmux] in
            if owned, let tmux {
                tmux.run(tmux.killSessionArguments(sessionId: id))
            }
            if let pid { Self.waitForExit(pid) }
            try? library.discard(sessionId: id)
            let result = Result { try SessionEraser.permanent().erase(id) }
            DispatchQueue.main.async {
                guard let self else { return }
                self.deleting.remove(id)
                let date = Date()
                self.updateCatalog { $0.markDeleted(id, at: date) }
                self.updateAppearanceSettings { $0.reset(id) }
                self.engine?.forget(id, at: date)
                if case let .failure(error) = result {
                    self.notice = "No pude borrar todos los archivos de la sesión: \(error.localizedDescription)"
                }
            }
        }
    }

    nonisolated private static func waitForExit(_ pid: Int32) {
        let deadline = Date().addingTimeInterval(10)
        while ProcessTree.isAlive(pid), Date() < deadline {
            usleep(100_000)
        }
    }

    private func updateCatalog(_ change: (inout SessionCatalog) -> Void) {
        var updated = catalog
        change(&updated)
        guard updated != catalog else { return }
        let retainedBefore = catalog.retainedSessionIds
        catalog = updated
        do {
            try catalogStore.save(updated)
        } catch {
            notice = "No pude guardar los cambios: \(error.localizedDescription)"
        }
        if updated.retainedSessionIds != retainedBefore {
            engine?.retain(updated.retainedSessionIds)
        }
    }

    var waitingCount: Int { sessions.values.filter { $0.live.status == .waiting }.count }
    var workingCount: Int { sessions.values.filter { $0.live.status == .working }.count }

    var recentDirectories: [String] {
        var seen: Set<String> = []
        return sessions.values
            .sorted { ($0.summary.lastActivity ?? .distantPast) > ($1.summary.lastActivity ?? .distantPast) }
            .compactMap(\.summary.cwd)
            .filter { seen.insert($0).inserted }
            .prefix(8)
            .map { $0 }
    }

    func items(for sessions: [SessionState]) -> [SidebarItem] {
        sessions.map(SidebarItem.init(session:))
    }

    func session(withId id: String) -> SessionState? { allSessions[id] }

    func isOwned(_ id: String) -> Bool { ownedSessionIds.contains(id) || pendingLaunches[id] != nil }

    func runningElsewhere(_ session: SessionState) -> Int32? {
        guard !isOwned(session.id), let pid = session.live.pid, ProcessTree.isAlive(pid) else { return nil }
        return pid
    }

    func ownerName(of session: SessionState) -> String? {
        runningElsewhere(session).flatMap(ProcessTree.ownerName(of:))
    }

    func canBringHere(_ session: SessionState) -> Bool {
        session.summary.cwd != nil && session.live.status != .working && !takingOver.contains(session.id)
    }

    func requestBringHere(_ session: SessionState) {
        guard runningElsewhere(session) != nil else {
            resume(session)
            return
        }
        takeoverCandidate = session
    }

    func confirmBringHere() {
        guard let session = takeoverCandidate else { return }
        takeoverCandidate = nil
        guard let pid = runningElsewhere(session) else {
            resume(session)
            return
        }
        guard canBringHere(session) else {
            notice = "La sesión está trabajando. Espera a que termine para traerla."
            return
        }
        takingOver.insert(session.id)
        actions.async { [weak self] in
            let matches = ClaudeProcesses.sessionId(of: pid) == session.id
            let exited = matches && ProcessTree.terminate(pid)
            DispatchQueue.main.async {
                guard let self else { return }
                self.takingOver.remove(session.id)
                if !matches {
                    self.notice = "El proceso \(pid) ya no corresponde a esta sesión. No lo toqué."
                } else if exited {
                    self.resume(session)
                } else {
                    self.notice = "No pude cerrar el proceso \(pid). Ciérralo a mano y usa “Reanudar aquí”."
                }
            }
        }
    }

    func newSession(in directory: String) {
        let id = UUID().uuidString.lowercased()
        let base = newSessionBrain
        let title = base.flatMap { library.savedBrain($0)?.name }
        launch(sessionId: id, directory: directory, mode: .new, baseBrain: base, title: title)
    }

    func resume(_ session: SessionState) {
        if let pid = runningElsewhere(session) {
            notice = "Esta sesión sigue abierta en otro proceso (pid \(pid)). Ciérrala allí antes de reanudarla aquí."
            return
        }
        let directory = session.summary.cwd ?? FileManager.default.homeDirectoryForCurrentUser.path
        launch(sessionId: session.id, directory: directory, mode: .resume, baseBrain: nil, title: session.summary.title)
    }

    func terminate(_ sessionId: String) {
        if library.isModified(sessionId) {
            offerToKeepBrain(of: sessionId, mode: .terminate)
        } else {
            try? library.discard(sessionId: sessionId)
            killSession(sessionId)
        }
    }

    func workingBrainContent(_ sessionId: String) -> String? {
        guard library.workingBrain(sessionId) != nil else { return nil }
        return library.content(of: library.workingBrainFile(sessionId))
    }

    func savedBrainContent(_ slug: String) -> String {
        library.content(of: library.savedBrainFile(slug))
    }

    func baseBrainName(of sessionId: String) -> String? {
        library.workingBrain(sessionId)?.baseSlug.flatMap { library.savedBrain($0)?.name }
    }

    func saveClosingBrain(updatingFirst: Bool) {
        guard let request = closing else { return }
        guard !closingName.trimmingCharacters(in: .whitespaces).isEmpty else {
            notice = "Ponle un nombre al cerebro para guardarlo."
            return
        }
        closing = nil
        if updatingFirst, request.mode == .terminate, let tmux, ownedSessionIds.contains(request.sessionId) {
            pendingClosingNames[request.sessionId] = (closingName, request.mode)
            finalizing[request.sessionId] = Date()
            let sessionId = request.sessionId
            actions.async {
                for arguments in tmux.sendTextArguments(sessionId: sessionId, text: BrainPrompt.finalUpdateRequest) {
                    tmux.run(arguments)
                }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.finalUpdateTimeout) { [weak self] in
                self?.completeClosing(sessionId)
            }
            presentNextClosing()
            return
        }
        persist(request.sessionId, name: closingName, mode: request.mode)
        presentNextClosing()
    }

    func discardClosingBrain() {
        guard let request = closing else { return }
        closing = nil
        try? library.discard(sessionId: request.sessionId)
        if request.mode == .terminate { killSession(request.sessionId) }
        presentNextClosing()
    }

    func cancelClosing() {
        guard let request = closing else { return }
        closing = nil
        if request.mode == .terminate { closingHandled.remove(request.sessionId) }
        presentNextClosing()
    }

    func canRelieveContext(_ session: SessionState) -> Bool {
        ownedSessionIds.contains(session.id)
            && relieving[session.id] == nil
            && finalizing[session.id] == nil
            && session.live.status != .working
            && session.live.status != .waiting
    }

    func relieveContext(_ session: SessionState) {
        guard canRelieveContext(session) else {
            notice = "Espera a que la sesión termine lo que está haciendo para liberar contexto."
            return
        }
        let hasBrain = library.workingBrain(session.id) != nil
        let phase: ContextRelief.Phase = hasBrain ? .updatingBrain : .compacting
        relieving[session.id] = ContextRelief(phase: phase, startedAt: Date())
        send(hasBrain ? BrainPrompt.refreshRequest : BrainPrompt.compactCommand, to: session.id)
        scheduleReliefTimeout(session.id, phase: phase)
    }

    private func advanceContextRelief(using snapshot: DeckSnapshot) {
        for (id, relief) in relieving {
            guard let live = snapshot.sessions[id]?.live,
                  live.status == .idle,
                  (live.since ?? .distantPast) > relief.startedAt
            else { continue }
            switch relief.phase {
            case .updatingBrain:
                relieving[id] = ContextRelief(phase: .compacting, startedAt: Date())
                send(BrainPrompt.compactCommand, to: id)
                scheduleReliefTimeout(id, phase: .compacting)
            case .compacting:
                relieving.removeValue(forKey: id)
            }
        }
    }

    private func scheduleReliefTimeout(_ sessionId: String, phase: ContextRelief.Phase) {
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.finalUpdateTimeout) { [weak self] in
            guard let self, self.relieving[sessionId]?.phase == phase else { return }
            self.relieving.removeValue(forKey: sessionId)
            self.notice = "Liberar contexto tardó demasiado y lo detuve. Revisa la sesión."
        }
    }

    private func send(_ text: String, to sessionId: String) {
        guard let tmux else { return }
        actions.async {
            for arguments in tmux.sendTextArguments(sessionId: sessionId, text: text) {
                tmux.run(arguments)
            }
        }
    }

    func deleteSavedBrain(_ slug: String) {
        do {
            try library.deleteSaved(slug)
        } catch {
            notice = "No pude borrar el cerebro: \(error)"
        }
        if selection == .brain(slug) { selection = nil }
        refreshBrains()
    }

    func startSession(with slug: String) {
        newSessionBrain = slug
        showingNewSession = true
    }

    @ObservationIgnored private var pendingClosingNames: [String: (String, ClosingRequest.Mode)] = [:]
    private static let finalUpdateTimeout: TimeInterval = 180

    private func offerToKeepBrain(of sessionId: String, mode: ClosingRequest.Mode) {
        guard library.isModified(sessionId) else {
            if mode == .ended { try? library.discard(sessionId: sessionId) }
            return
        }
        closingHandled.insert(sessionId)
        let request = ClosingRequest(sessionId: sessionId, mode: mode)
        if closing == nil {
            present(request)
        } else {
            closingQueue.append(request)
        }
    }

    private func present(_ request: ClosingRequest) {
        closingName = baseBrainName(of: request.sessionId) ?? session(withId: request.sessionId).map(title(of:)) ?? ""
        closing = request
    }

    private func presentNextClosing() {
        guard closing == nil, !closingQueue.isEmpty else { return }
        present(closingQueue.removeFirst())
    }

    private func completeClosing(_ sessionId: String) {
        guard finalizing.removeValue(forKey: sessionId) != nil,
              let (name, mode) = pendingClosingNames.removeValue(forKey: sessionId)
        else { return }
        persist(sessionId, name: name, mode: mode)
    }

    private func persist(_ sessionId: String, name: String, mode: ClosingRequest.Mode) {
        do {
            let saved = try library.save(sessionId: sessionId, name: name)
            refreshBrains()
            notice = "Cerebro “\(saved.name)” guardado."
        } catch {
            notice = "No pude guardar el cerebro: \(error)"
        }
        if mode == .terminate { killSession(sessionId) }
    }

    private func refreshBrains() {
        let brains = library.savedBrains()
        if brains != savedBrains { savedBrains = brains }
    }

    private func killSession(_ sessionId: String) {
        closingHandled.insert(sessionId)
        guard let tmux else { return }
        actions.async { [engine] in
            tmux.run(tmux.killSessionArguments(sessionId: sessionId))
            engine?.refreshOwnedSessions()
        }
    }

    func sendToSubagent(_ agent: SubagentState) {
        let text = subagentDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let tmux, isOwned(agent.sessionId) else { return }
        let message = SubagentRelay.message(agentId: agent.id, description: agent.meta?.description, text: text)
        subagentDraft = ""
        actions.async {
            for arguments in tmux.sendTextArguments(sessionId: agent.sessionId, text: message) {
                tmux.run(arguments)
            }
        }
    }

    private func launch(sessionId: String, directory: String, mode: ClaudeLaunch.Mode, baseBrain: String?, title: String?) {
        guard let tmux else {
            notice = "No encontré tmux. Instálalo con: brew install tmux"
            return
        }
        var promptFile: String?
        do {
            try library.prepareWorkingBrain(sessionId: sessionId, baseSlug: baseBrain, title: title)
            promptFile = try library.writeSystemPrompt(sessionId: sessionId).path
        } catch {
            notice = "La sesión arranca sin cerebro: \(error)"
        }
        closingHandled.remove(sessionId)
        let launch = ClaudeLaunch(
            sessionId: sessionId,
            directory: directory,
            mode: mode,
            skipPermissions: skipPermissions,
            systemPromptFile: promptFile,
            brainDirectory: promptFile.map { _ in library.workingDirectory(sessionId).path },
            environment: promptFile == nil ? [:] : [BrainPrompt.environmentKey: library.workingBrainFile(sessionId).path]
        )
        pendingLaunches[launch.sessionId] = PendingLaunch(directory: launch.directory, createdAt: Date())
        selection = .session(launch.sessionId)
        let shell = Self.loginShell
        actions.async { [weak self, engine] in
            try? tmux.writeConfiguration()
            let result = tmux.run(tmux.newSessionArguments(launch, loginShell: shell))
            engine?.refreshOwnedSessions()
            guard result.status != 0 else { return }
            DispatchQueue.main.async {
                self?.pendingLaunches.removeValue(forKey: launch.sessionId)
                self?.notice = "No se pudo abrir la sesión: \(result.output.trimmingCharacters(in: .whitespacesAndNewlines))"
            }
        }
    }

    private static var loginShell: String {
        if let entry = getpwuid(getuid()), let shell = entry.pointee.pw_shell {
            let path = String(cString: shell)
            if !path.isEmpty { return path }
        }
        return ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
    }

    private func sorted(_ values: [SessionState]) -> [SessionState] {
        values.sorted {
            if $0.live.status.priority != $1.live.status.priority {
                return $0.live.status.priority < $1.live.status.priority
            }
            return ($0.summary.lastActivity ?? .distantPast) > ($1.summary.lastActivity ?? .distantPast)
        }
    }
}

struct NamePrompt: Identifiable, Equatable {
    enum Kind: Equatable {
        case renameSession(String)
        case newGroup(assigning: String?)
        case renameGroup(String)
    }

    let kind: Kind
    var text: String
    let id = UUID()

    var title: String {
        switch kind {
        case .renameSession: return "Renombrar sesión"
        case .newGroup: return "Nuevo grupo"
        case .renameGroup: return "Renombrar grupo"
        }
    }

    var placeholder: String {
        switch kind {
        case .renameSession: return "Nombre de la sesión (vacío vuelve al título de Claude)"
        case .newGroup, .renameGroup: return "Nombre del grupo"
        }
    }
}

struct ContextRelief: Equatable {
    enum Phase: Equatable {
        case updatingBrain
        case compacting
    }

    let phase: Phase
    let startedAt: Date

    var label: String {
        switch phase {
        case .updatingBrain: return "Actualizando el cerebro…"
        case .compacting: return "Compactando…"
        }
    }
}

struct ClosingRequest: Identifiable, Equatable {
    enum Mode: Equatable {
        case terminate
        case ended
    }

    let sessionId: String
    let mode: Mode

    var id: String { sessionId }
}

struct PendingLaunch: Equatable {
    static let gracePeriod: TimeInterval = 15

    let directory: String
    let createdAt: Date
}

struct SidebarItem: Identifiable, Hashable {
    enum ID: Hashable {
        case session(String)
        case subagent(sessionId: String, agentId: String)
        case brain(String)
    }

    let id: ID
    let children: [SidebarItem]?

    init(session: SessionState) {
        id = .session(session.id)
        let subagents = session.orderedSubagents.map {
            SidebarItem(id: .subagent(sessionId: session.id, agentId: $0.id), children: nil)
        }
        children = subagents.isEmpty ? nil : subagents
    }

    private init(id: ID, children: [SidebarItem]?) {
        self.id = id
        self.children = children
    }
}
