import AppKit
import DeckCore
import SwiftUI

struct MainView: View {
    @Bindable var store: DeckStore

    var body: some View {
        NavigationSplitView {
            TimelineView(.periodic(from: .now, by: 60)) { context in
                List(selection: $store.selection) {
                    section("Activas", sessions: store.activeSessions, now: context.date)
                    ForEach(store.groups) { group in
                        groupSection(group, now: context.date)
                    }
                    if !store.savedBrains.isEmpty {
                        Section("Cerebros") {
                            ForEach(store.savedBrains) { brain in
                                SavedBrainRow(brain: brain, now: context.date)
                                    .tag(SidebarItem.ID.brain(brain.slug))
                                    .contextMenu {
                                        Button("Nueva sesión con este cerebro") { store.startSession(with: brain.slug) }
                                    }
                            }
                        }
                    }
                    section("Recientes · 7 días", sessions: store.recentSessions, now: context.date)
                }
                .listStyle(.sidebar)
            }
            .navigationSplitViewColumnWidth(min: 300, ideal: 380)
            .toolbar {
                ToolbarItem {
                    Button {
                        store.showingNewSession = true
                    } label: {
                        Label("Nueva sesión", systemImage: "plus")
                    }
                    .help("Nueva sesión")
                    .disabled(store.tmux == nil)
                }
            }
        } detail: {
            DetailView(store: store)
        }
        .sheet(isPresented: $store.showingNewSession) {
            NewSessionView(store: store)
        }
        .sheet(item: $store.closing) { request in
            ClosingBrainView(store: store, request: request)
        }
        .sheet(item: $store.namePrompt) { _ in
            NamePromptView(store: store)
        }
        .confirmationDialog(
            "¿Borrar esta sesión?",
            isPresented: deletionBinding,
            titleVisibility: .visible,
            presenting: store.deletionCandidate
        ) { _ in
            Button("Borrar", role: .destructive) { store.confirmDelete() }
            Button("Cancelar", role: .cancel) { store.deletionCandidate = nil }
        } message: { session in
            Text(deletionMessage(for: session))
        }
        .confirmationDialog(
            "¿Traer esta sesión a Claude Deck?",
            isPresented: takeoverBinding,
            titleVisibility: .visible,
            presenting: store.takeoverCandidate
        ) { _ in
            Button("Traer") { store.confirmBringHere() }
            Button("Cancelar", role: .cancel) { store.takeoverCandidate = nil }
        } message: { session in
            Text("“\(store.title(of: session))” se cerrará en \(store.ownerName(of: session) ?? "el otro proceso") y se reanudará aquí con todo su historial.")
        }
        .alert("Claude Deck", isPresented: noticeBinding) {
            Button("OK") { store.notice = nil }
        } message: {
            Text(store.notice ?? "")
        }
    }

    private var takeoverBinding: Binding<Bool> {
        Binding(get: { store.takeoverCandidate != nil }, set: { if !$0 { store.takeoverCandidate = nil } })
    }

    private var deletionBinding: Binding<Bool> {
        Binding(get: { store.deletionCandidate != nil }, set: { if !$0 { store.deletionCandidate = nil } })
    }

    private func deletionMessage(for session: SessionState) -> String {
        var parts = ["“\(store.title(of: session))” desaparece de Claude Deck y de claude --resume: se borran para siempre su transcript, sus subagentes y su historial de archivos. No se puede deshacer."]
        if store.isOwned(session.id) {
            parts.append("Está abierta aquí: se cierra y su cerebro de trabajo se descarta sin guardarlo.")
        }
        return parts.joined(separator: " ")
    }

    @ViewBuilder
    private func groupSection(_ group: SessionGroup, now: Date) -> some View {
        let expanded = Binding(get: { !store.isCollapsed(group) }, set: { store.setCollapsed(group, !$0) })
        Section(isExpanded: expanded) {
            OutlineGroup(store.items(for: store.sessions(in: group)), children: \.children) { item in
                row(for: item, now: now)
            }
        } header: {
            Label(group.name, systemImage: "folder")
                .contextMenu {
                    Button("Renombrar grupo…") { store.requestRenameGroup(group) }
                    Button("Eliminar grupo", role: .destructive) { store.deleteGroup(group) }
                }
        }
    }

    private var noticeBinding: Binding<Bool> {
        Binding(get: { store.notice != nil }, set: { if !$0 { store.notice = nil } })
    }

    @ViewBuilder
    private func section(_ title: String, sessions: [SessionState], now: Date) -> some View {
        if !sessions.isEmpty {
            Section(title) {
                OutlineGroup(store.items(for: sessions), children: \.children) { item in
                    row(for: item, now: now)
                }
            }
        }
    }

    @ViewBuilder
    private func row(for item: SidebarItem, now: Date) -> some View {
        switch item.id {
        case let .session(id):
            if let session = store.session(withId: id) {
                SessionRow(session: session, title: store.title(of: session), owned: store.isOwned(id), now: now)
                    .contextMenu {
                        Button("Renombrar…") { store.requestRename(session) }
                        Menu("Mover a grupo") {
                            ForEach(store.groups) { group in
                                Button(group.name) { store.move(id, to: group) }
                                    .disabled(store.group(of: id)?.id == group.id)
                            }
                            if !store.groups.isEmpty { Divider() }
                            Button("Nuevo grupo…") { store.requestNewGroup(assigning: id) }
                            if store.group(of: id) != nil {
                                Button("Quitar del grupo") { store.move(id, to: nil) }
                            }
                        }
                        Divider()
                        if store.isOwned(id) {
                            Button("Terminar sesión", role: .destructive) { store.terminate(id) }
                        } else if store.runningElsewhere(session) != nil {
                            Button("Traer a Claude Deck") { store.requestBringHere(session) }
                                .disabled(!store.canBringHere(session))
                        } else if session.summary.cwd != nil {
                            Button("Reanudar aquí") { store.resume(session) }
                        }
                        Button("Copiar id de sesión") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(id, forType: .string)
                        }
                        Divider()
                        Button("Borrar sesión…", role: .destructive) { store.requestDelete(session) }
                            .disabled(!store.canDelete(session))
                    }
            }
        case let .subagent(sessionId, agentId):
            if let agent = store.session(withId: sessionId)?.subagents[agentId] {
                SubagentRow(agent: agent, now: now)
            }
        case .brain:
            EmptyView()
        }
    }
}

struct SessionRow: View {
    let session: SessionState
    let title: String
    let owned: Bool
    let now: Date

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: session.live.status.symbolName)
                .foregroundStyle(session.live.status.color)
                .font(.caption)
                .padding(.top, 3)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            if owned {
                Image(systemName: "terminal")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .help("Abierta en Claude Deck")
            }
            if session.runningSubagentCount(at: now) > 0 {
                Text("\(session.runningSubagentCount(at: now))")
                    .font(.caption2.monospacedDigit())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(.green.opacity(0.25)))
            }
        }
    }

    private var subtitle: String {
        let folder = session.summary.cwd.map { URL(fileURLWithPath: $0).lastPathComponent } ?? session.project
        let context = session.summary.contextTokens.map { SessionSummary.formatTokens($0) + " ctx" }
        return [folder, session.summary.gitBranch, context, RelativeTime.describe(session.summary.lastActivity, relativeTo: now)]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }
}

struct SubagentRow: View {
    let agent: SubagentState
    let now: Date

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: agent.isRunning(at: now) ? "circle.fill" : "checkmark.circle")
                .foregroundStyle(agent.isRunning(at: now) ? Color.green : Color.secondary)
                .font(.caption2)
            VStack(alignment: .leading, spacing: 1) {
                Text(agent.displayTitle)
                    .lineLimit(1)
                Text([agent.meta?.agentType, RelativeTime.describe(agent.summary.lastActivity, relativeTo: now)]
                    .compactMap { $0 }
                    .joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct SavedBrainRow: View {
    let brain: SavedBrain
    let now: Date

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "brain")
                .foregroundStyle(.pink)
                .font(.caption)
            VStack(alignment: .leading, spacing: 2) {
                Text(brain.name)
                    .lineLimit(1)
                Text("\(brain.sessionIds.count) sesiones · \(RelativeTime.describe(brain.updatedAt, relativeTo: now))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct NamePromptView: View {
    @Bindable var store: DeckStore

    var body: some View {
        if let prompt = store.namePrompt {
            VStack(alignment: .leading, spacing: 14) {
                Text(prompt.title)
                    .font(.headline)
                TextField(prompt.placeholder, text: textBinding)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { store.submitNamePrompt() }
                HStack {
                    Spacer()
                    Button("Cancelar", role: .cancel) { store.namePrompt = nil }
                        .keyboardShortcut(.cancelAction)
                    Button("Guardar") { store.submitNamePrompt() }
                        .keyboardShortcut(.defaultAction)
                }
            }
            .padding(20)
            .frame(width: 380)
        }
    }

    private var textBinding: Binding<String> {
        Binding(get: { store.namePrompt?.text ?? "" }, set: { store.namePrompt?.text = $0 })
    }
}
