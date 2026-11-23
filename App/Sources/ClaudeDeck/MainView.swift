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
                                SavedBrainRow(brain: brain, now: context.date, style: store.sidebarStyle)
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
                .sidebarStyle(store.sidebarStyle)
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
                    .dropDestination(for: String.self) { payloads, _ in
                        store.dropSessions(payloads, into: group)
                    }
            }
        } header: {
            Label(group.name, systemImage: "folder")
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 2)
                .background(RoundedRectangle(cornerRadius: 5).fill(Color.accentColor.opacity(store.dropTargetGroupId == group.id ? 0.25 : 0)))
                .contentShape(Rectangle())
                .dropDestination(for: String.self) { payloads, _ in
                    store.dropSessions(payloads, into: group)
                } isTargeted: { targeted in
                    store.dropTargetGroupId = targeted ? group.id : (store.dropTargetGroupId == group.id ? nil : store.dropTargetGroupId)
                }
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
            Section {
                OutlineGroup(store.items(for: sessions), children: \.children) { item in
                    row(for: item, now: now)
                        .dropDestination(for: String.self) { payloads, _ in
                            store.dropSessions(payloads, into: nil)
                        }
                }
            } header: {
                Text(title)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 2)
                    .background(RoundedRectangle(cornerRadius: 5).fill(Color.accentColor.opacity(store.dropTargetGroupId == title ? 0.25 : 0)))
                    .contentShape(Rectangle())
                    .dropDestination(for: String.self) { payloads, _ in
                        store.dropSessions(payloads, into: nil)
                    } isTargeted: { targeted in
                        store.dropTargetGroupId = targeted ? title : (store.dropTargetGroupId == title ? nil : store.dropTargetGroupId)
                    }
            }
        }
    }

    @ViewBuilder
    private func row(for item: SidebarItem, now: Date) -> some View {
        switch item.id {
        case let .session(id):
            if let session = store.session(withId: id) {
                SessionRow(session: session, title: store.title(of: session), owned: store.isOwned(id), now: now, style: store.sidebarStyle, attention: store.attention(of: session))
                    .draggable(SidebarDrop.payload(for: id)) {
                        Label(store.title(of: session), systemImage: "terminal")
                            .padding(6)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
                    }
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
                        if store.attention(of: session) == .seen {
                            Button("Marcar como no vista") { store.markUnread(id) }
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
                SubagentRow(agent: agent, now: now, style: store.sidebarStyle)
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
    let style: SidebarStyle
    var attention: SessionAttention = .seen

    var body: some View {
        HStack(alignment: style.iconStyle == .avatar ? .center : .top, spacing: style.iconStyle == .avatar ? 10 : 8) {
            SessionIcon(session: session, title: title, style: style, attention: attention)
            VStack(alignment: .leading, spacing: style.density.lineSpacing) {
                Text(title)
                    .font(style.titleFont)
                    .fontWeight(attention == .seen || attention == .working ? .regular : .semibold)
                    .lineLimit(1)
                if !detail.isEmpty || attention != .seen {
                    (statusPrefix + Text(detail).foregroundStyle(.secondary))
                        .font(style.detailFont)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            if status == .working {
                ProgressView()
                    .controlSize(.small)
                    .tint(statusColor)
                    .help("Trabajando")
            }
            if owned {
                Image(systemName: "apple.terminal.fill")
                    .font(style.detailFont)
                    .foregroundStyle(style.accent.color)
                    .help("Abierta en Claude Deck")
            }
            if session.runningSubagentCount(at: now) > 0 {
                Text("\(session.runningSubagentCount(at: now))")
                    .font(style.detailFont.monospacedDigit())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(.green.opacity(0.25)))
            }
        }
        .padding(.vertical, style.density.rowPadding)
        .padding(.leading, 6)
        .background {
            if let highlight {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(highlight.opacity(0.14))
                    .padding(.horizontal, -4)
                    .padding(.vertical, -2)
            }
        }
        .background(alignment: .leading) {
            if let marker {
                Capsule()
                    .fill(marker)
                    .frame(width: attention == .unread ? 7 : 4, height: attention == .unread ? 7 : nil)
                    .padding(.vertical, 2)
                    .shadow(color: marker.opacity(0.7), radius: 3)
                    .offset(x: attention == .unread ? -3 : 0)
            }
        }
    }

    private var status: SessionStatus { session.live.status }

    private var statusColor: Color { style.statusColor(status.badgeColor) }

    private var unreadColor: Color { style.accent.color }

    private var marker: Color? {
        switch attention {
        case .needsYou, .working: return statusColor
        case .unread: return unreadColor
        case .seen: return nil
        }
    }

    private var highlight: Color? {
        switch attention {
        case .needsYou: return statusColor
        case .unread: return unreadColor
        case .working, .seen: return nil
        }
    }

    private var statusPrefix: Text {
        let label: String
        let color: Color
        switch attention {
        case .working: (label, color) = ("Trabajando…", statusColor)
        case .needsYou: (label, color) = ("Esperando tu permiso", statusColor)
        case .unread: (label, color) = (status == .ended ? "Terminó" : "Respuesta nueva", unreadColor)
        case .seen: return Text("")
        }
        return Text(label + (detail.isEmpty ? "" : SidebarStyle.separator)).foregroundStyle(color).bold()
    }

    private var detail: String {
        style.detailLine([
            .folder: session.summary.cwd.map { URL(fileURLWithPath: $0).lastPathComponent } ?? session.project,
            .branch: session.summary.gitBranch ?? "",
            .context: session.summary.contextTokens.map { SessionSummary.formatTokens($0) + " ctx" } ?? "",
            .lastActivity: RelativeTime.describe(session.summary.lastActivity, relativeTo: now),
            .preview: session.summary.preview ?? "",
        ])
    }
}

struct SubagentRow: View {
    let agent: SubagentState
    let now: Date
    let style: SidebarStyle

    var body: some View {
        HStack(spacing: 8) {
            if style.iconStyle == .avatar {
                IconTile(content: .symbol(agent.isRunning(at: now) ? "gearshape.2.fill" : "checkmark"),
                         color: agent.isRunning(at: now) ? style.statusColor(.green) : .gray,
                         size: style.iconSize * 0.75)
            } else {
                Image(systemName: agent.isRunning(at: now) ? "circle.fill" : "checkmark.circle")
                    .foregroundStyle(agent.isRunning(at: now) ? style.statusColor(.green) : Color.secondary)
                    .font(style.detailFont)
            }
            VStack(alignment: .leading, spacing: style.density.lineSpacing) {
                Text(agent.displayTitle)
                    .font(style.titleFont)
                    .lineLimit(1)
                Text([agent.meta?.agentType, RelativeTime.describe(agent.summary.lastActivity, relativeTo: now)]
                    .compactMap { $0 }
                    .joined(separator: " · "))
                    .font(style.detailFont)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, style.density.rowPadding)
    }
}

struct SavedBrainRow: View {
    let brain: SavedBrain
    let now: Date
    let style: SidebarStyle

    var body: some View {
        HStack(spacing: 8) {
            if style.iconStyle == .avatar {
                IconTile(content: .symbol("brain.head.profile"), color: style.statusColor(.pink), size: style.iconSize * 0.85)
            } else {
                Image(systemName: "brain")
                    .foregroundStyle(style.statusColor(.pink))
                    .font(style.detailFont)
            }
            VStack(alignment: .leading, spacing: style.density.lineSpacing) {
                Text(brain.name)
                    .font(style.titleFont)
                    .lineLimit(1)
                Text("\(brain.sessionIds.count) sesiones · \(RelativeTime.describe(brain.updatedAt, relativeTo: now))")
                    .font(style.detailFont)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, style.density.rowPadding)
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
