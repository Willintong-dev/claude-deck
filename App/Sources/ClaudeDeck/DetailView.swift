import AppKit
import DeckCore
import SwiftUI

struct DetailView: View {
    @Bindable var store: DeckStore

    var body: some View {
        switch store.selection {
        case let .session(id)?:
            if let session = store.session(withId: id) {
                if store.isOwned(id) {
                    OwnedSessionView(store: store, session: session)
                } else {
                    ExternalSessionView(store: store, session: session)
                }
            } else {
                placeholder
            }
        case let .subagent(sessionId, agentId)?:
            if let parent = store.session(withId: sessionId), let agent = parent.subagents[agentId] {
                SubagentView(store: store, agent: agent, parent: parent)
            } else {
                placeholder
            }
        case let .brain(slug)?:
            if let brain = store.savedBrains.first(where: { $0.slug == slug }) {
                SavedBrainView(store: store, brain: brain)
            } else {
                placeholder
            }
        case nil:
            placeholder
        }
    }

    private var placeholder: some View {
        ContentUnavailableView(
            "Elige una sesión",
            systemImage: "bubble.left.and.bubble.right",
            description: Text("O crea una nueva con el botón +")
        )
    }
}

private struct OwnedSessionView: View {
    let store: DeckStore
    let session: SessionState

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                StatusBadge(status: session.live.status)
                Text(store.title(of: session))
                    .font(.headline)
                    .lineLimit(1)
                if let cwd = session.summary.cwd {
                    Text(URL(fileURLWithPath: cwd).lastPathComponent)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                contextControls
                if let base = store.baseBrainName(of: session.id) {
                    Label(base, systemImage: "brain")
                        .font(.caption)
                        .foregroundStyle(.pink)
                }
                Button("Cerebro") { store.brainPopoverSessionId = session.id }
                    .controlSize(.small)
                    .popover(isPresented: brainPopoverBinding, arrowEdge: .bottom) {
                        BrainText(content: store.workingBrainContent(session.id) ?? "Esta sesión no tiene cerebro.")
                            .frame(width: 520, height: 420)
                    }
                Button {
                    store.appearancePopoverSessionId = session.id
                } label: {
                    Image(systemName: store.isAppearanceCustomized(session.id) ? "paintpalette.fill" : "paintpalette")
                }
                .controlSize(.small)
                .help("Apariencia de esta sesión")
                .popover(isPresented: appearancePopoverBinding, arrowEdge: .bottom) {
                    TerminalAppearanceForm(store: store, sessionId: session.id)
                        .padding(16)
                        .frame(width: 340)
                }
                Button("Terminar", role: .destructive) { store.terminate(session.id) }
                    .controlSize(.small)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            Divider()
            TerminalContainer(sessionId: session.id)
                .id(session.id)
        }
    }

    @ViewBuilder
    private var contextControls: some View {
        if let relief = store.relieving[session.id] {
            ProgressView().controlSize(.small)
            Text(relief.label)
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            if let tokens = session.summary.contextTokens {
                Text("\(SessionSummary.formatTokens(tokens)) tokens")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(session.summary.needsContextRelief ? Color.orange : Color.secondary)
                    .help("Contexto que viaja en cada turno de esta sesión")
            }
            if session.summary.needsContextRelief {
                Button("Liberar contexto") { store.relieveContext(session) }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    .controlSize(.small)
                    .disabled(!store.canRelieveContext(session))
                    .help("Actualiza el cerebro y compacta la conversación; la sesión sigue con el cerebro recargado")
            } else {
                Button("Liberar contexto") { store.relieveContext(session) }
                    .controlSize(.small)
                    .disabled(!store.canRelieveContext(session) || session.summary.contextTokens == nil)
                    .help("Actualiza el cerebro y compacta la conversación; la sesión sigue con el cerebro recargado")
            }
        }
    }

    private var appearancePopoverBinding: Binding<Bool> {
        Binding(
            get: { store.appearancePopoverSessionId == session.id },
            set: { if !$0 { store.appearancePopoverSessionId = nil } }
        )
    }

    private var brainPopoverBinding: Binding<Bool> {
        Binding(
            get: { store.brainPopoverSessionId == session.id },
            set: { if !$0 { store.brainPopoverSessionId = nil } }
        )
    }
}

struct BrainText: View {
    let content: String

    var body: some View {
        ScrollView {
            Text(content)
                .font(.callout)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
        }
    }
}

private struct SavedBrainView: View {
    let store: DeckStore
    let brain: SavedBrain

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Label(brain.name, systemImage: "brain")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.primary)
                Text("Usado en \(brain.sessionIds.count) sesiones · actualizado \(brain.updatedAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    Button("Nueva sesión con este cerebro") { store.startSession(with: brain.slug) }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    Button("Mostrar en Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([store.library.savedBrainFile(brain.slug)])
                    }
                    .controlSize(.small)
                    Spacer()
                    Button("Borrar", role: .destructive) { store.deleteSavedBrain(brain.slug) }
                        .controlSize(.small)
                }
            }
            .padding(16)
            Divider()
            BrainText(content: store.savedBrainContent(brain.slug))
        }
    }
}

private struct ExternalSessionView: View {
    let store: DeckStore
    let session: SessionState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    StatusBadge(status: session.live.status)
                    Text(store.title(of: session))
                        .font(.title3.weight(.semibold))
                        .lineLimit(2)
                }
                FactList(facts: [
                    ("Carpeta", session.summary.cwd),
                    ("Rama", session.summary.gitBranch),
                    ("Sesión", session.id),
                    ("Proceso", session.live.pid.map { "pid \($0)" }),
                ])
                if let message = session.live.status == .waiting ? session.live.message : nil {
                    Text(message)
                        .font(.callout)
                        .foregroundStyle(.orange)
                }
                resumeControls
            }
            .padding(16)
            Divider()
            TranscriptList(store: store, url: session.transcriptURL, activity: session.summary.lastActivity)
        }
    }

    @ViewBuilder
    private var resumeControls: some View {
        if store.takingOver.contains(session.id) {
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Trayendo la sesión…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } else if let pid = store.runningElsewhere(session) {
            HStack(spacing: 10) {
                Button("Traer a Claude Deck") { store.requestBringHere(session) }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(!store.canBringHere(session))
                Text(ownerDescription(pid: pid))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } else if session.summary.cwd != nil {
            Button("Reanudar aquí") { store.resume(session) }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
        }
    }

    private func ownerDescription(pid: Int32) -> String {
        let owner = store.ownerName(of: session).map { "en \($0)" } ?? "en otro proceso"
        if session.live.status == .working {
            return "Abierta \(owner) (pid \(pid)) y trabajando. Espera a que termine para traerla."
        }
        return "Abierta \(owner) (pid \(pid)). Se cerrará allí y seguirá aquí con todo su historial."
    }
}

private struct SubagentView: View {
    @Bindable var store: DeckStore
    let agent: SubagentState
    let parent: SessionState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    StatusBadge(status: agent.isRunning(at: Date()) ? .working : .ended)
                    Text(agent.displayTitle)
                        .font(.title3.weight(.semibold))
                        .lineLimit(2)
                }
                FactList(facts: [
                    ("Tipo", agent.meta?.agentType),
                    ("Sesión", store.title(of: parent)),
                    ("Agente", agent.id),
                ])
            }
            .padding(16)
            Divider()
            TranscriptList(store: store, url: agent.transcriptURL, activity: agent.summary.lastActivity)
            Divider()
            composer
                .padding(10)
        }
    }

    @ViewBuilder
    private var composer: some View {
        if store.isOwned(parent.id) {
            HStack {
                TextField("Mensaje para este subagente (se envía a través de su sesión)", text: $store.subagentDraft)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { store.sendToSubagent(agent) }
                Button("Enviar") { store.sendToSubagent(agent) }
                    .disabled(store.subagentDraft.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        } else {
            Text("Para escribirle, reanuda la sesión padre dentro de Claude Deck.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct TranscriptList: View {
    let store: DeckStore
    let url: URL?
    let activity: Date?

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(store.transcript.messages) { message in
                        MessageBubble(message: message)
                            .id(message.id)
                    }
                }
                .padding(16)
            }
            .onChange(of: store.transcript.messages.last?.id) { _, last in
                guard let last else { return }
                proxy.scrollTo(last, anchor: .bottom)
            }
        }
        .task(id: LoadKey(url: url, activity: activity)) {
            await store.transcript.load(url)
        }
    }
}

private struct LoadKey: Hashable {
    let url: URL?
    let activity: Date?
}

private struct StatusBadge: View {
    let status: SessionStatus

    var body: some View {
        Label(status.label, systemImage: status.symbolName)
            .font(.caption)
            .foregroundStyle(status.color)
    }
}

private struct FactList: View {
    let facts: [(String, String?)]

    var body: some View {
        ForEach(facts.compactMap { label, value in value.map { (label, $0) } }, id: \.0) { fact in
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(fact.0)
                    .foregroundStyle(.secondary)
                    .frame(width: 60, alignment: .leading)
                Text(fact.1)
                    .textSelection(.enabled)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .font(.caption)
        }
    }
}

private struct MessageBubble: View {
    let message: TranscriptMessage
    private static let maximumLength = 4000

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(message.role == .user ? "Tú" : "Claude")
                .font(.caption.weight(.semibold))
                .foregroundStyle(message.role == .user ? Color.accentColor : Color.secondary)
            Text(message.text.count > Self.maximumLength ? message.text.prefix(Self.maximumLength) + "…" : message.text)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(message.role == .user ? Color.accentColor.opacity(0.08) : Color.secondary.opacity(0.06))
        )
    }
}
