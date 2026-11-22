import AppKit
import DeckCore
import SwiftUI

@MainActor
final class DeckNotifier {
    static let shared = DeckNotifier()

    var onOpen: ((String) -> Void)?
    private var toasts: [(id: UUID, panel: NSPanel)] = []
    private var sound: NSSound?
    private let width: CGFloat = 340
    private let margin: CGFloat = 16
    private let spacing: CGFloat = 8
    private let maximumVisible = 4

    func show(_ alert: DeckAlert, settings: NotificationSettings) {
        play(alert.sound, volume: settings.volume)
        let panel = makePanel(for: alert)
        toasts.insert((alert.id, panel), at: 0)
        while toasts.count > maximumVisible {
            close(toasts[toasts.count - 1].id)
        }
        layout(settings)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { $0.duration = 0.2; panel.animator().alphaValue = 1 }
        guard settings.duration != NotificationSettings.untilDismissed else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + settings.duration) { [weak self] in
            self?.dismiss(alert.id, settings: settings)
        }
    }

    func play(_ name: String, volume: Double) {
        guard !name.isEmpty, let sound = NSSound(named: NSSound.Name(name)) else { return }
        self.sound?.stop()
        sound.volume = Float(volume)
        sound.play()
        self.sound = sound
    }

    private func dismiss(_ id: UUID, settings: NotificationSettings) {
        guard let entry = toasts.first(where: { $0.id == id }) else { return }
        NSAnimationContext.runAnimationGroup({ $0.duration = 0.25; entry.panel.animator().alphaValue = 0 }) { [weak self] in
            MainActor.assumeIsolated {
                self?.close(id)
                self?.layout(settings)
            }
        }
    }

    private func close(_ id: UUID) {
        guard let position = toasts.firstIndex(where: { $0.id == id }) else { return }
        toasts[position].panel.orderOut(nil)
        toasts.remove(at: position)
    }

    private func makePanel(for alert: DeckAlert) -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: width, height: 80),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        let view = AlertToastView(
            alert: alert,
            open: { [weak self] in
                self?.close(alert.id)
                if !alert.sessionId.isEmpty { self?.onOpen?(alert.sessionId) }
            },
            dismiss: { [weak self] in
                self?.close(alert.id)
            }
        )
        let hosting = NSHostingView(rootView: view.frame(width: width))
        hosting.setFrameSize(hosting.fittingSize)
        panel.contentView = hosting
        panel.setContentSize(hosting.fittingSize)
        return panel
    }

    private func layout(_ settings: NotificationSettings) {
        let screen = targetScreen(settings.screen)
        let area = screen.visibleFrame
        var offset = margin
        for entry in toasts {
            let size = entry.panel.frame.size
            let x: CGFloat
            switch settings.position {
            case .topLeft, .bottomLeft: x = area.minX + margin
            case .topCenter, .bottomCenter: x = area.midX - size.width / 2
            case .topRight, .bottomRight: x = area.maxX - size.width - margin
            }
            let y = settings.position.isTop ? area.maxY - offset - size.height : area.minY + offset
            entry.panel.setFrameOrigin(NSPoint(x: x, y: y))
            offset += size.height + spacing
        }
    }

    private func targetScreen(_ choice: NotificationScreen) -> NSScreen {
        let fallback = NSScreen.screens.first ?? NSScreen.main ?? NSScreen()
        guard choice == .pointer else { return fallback }
        let pointer = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(pointer, $0.frame, false) } ?? fallback
    }

    static let availableSounds: [String] = {
        let folders = [
            URL(fileURLWithPath: "/System/Library/Sounds"),
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Sounds"),
        ]
        let names = folders.flatMap { folder in
            ((try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [])
                .map { $0.deletingPathExtension().lastPathComponent }
        }
        return Array(Set(names)).sorted()
    }()
}

extension NotificationKind {
    var symbolName: String {
        switch self {
        case .permission: return "exclamationmark.bubble.fill"
        case .turnFinished: return "checkmark.bubble.fill"
        case .sessionEnded: return "xmark.circle.fill"
        case .subagentFinished: return "person.2.fill"
        }
    }

    var tint: Color {
        switch self {
        case .permission: return .orange
        case .turnFinished: return .green
        case .sessionEnded: return .secondary
        case .subagentFinished: return .blue
        }
    }
}

struct AlertToastView: View {
    let alert: DeckAlert
    let open: () -> Void
    let dismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: alert.kind.symbolName)
                .font(.title2)
                .foregroundStyle(alert.kind.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(alert.title)
                    .font(.headline)
                    .lineLimit(1)
                if !alert.body.isEmpty {
                    Text(alert.body)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
            Button(action: dismiss) {
                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.separator))
        .contentShape(RoundedRectangle(cornerRadius: 14))
        .onTapGesture(perform: open)
        .padding(4)
    }
}

struct NotificationSettingsView: View {
    @Bindable var store: DeckStore

    var body: some View {
        Form {
            Toggle("Mostrar avisos", isOn: setting(\.enabled))
            Section("Dónde y cuánto") {
                Picker("Posición", selection: setting(\.position)) {
                    ForEach(NotificationPosition.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                Picker("Pantalla", selection: setting(\.screen)) {
                    ForEach(NotificationScreen.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                LabeledContent("Duración") {
                    HStack {
                        Slider(
                            value: Binding(
                                get: { store.notifications.duration },
                                set: { value in store.updateNotifications { $0.setDuration(value.rounded()) } }
                            ),
                            in: NotificationSettings.durationRange
                        )
                        Text(durationLabel)
                            .monospacedDigit()
                            .frame(width: 110, alignment: .trailing)
                    }
                }
                LabeledContent("Volumen") {
                    Slider(
                        value: Binding(
                            get: { store.notifications.volume },
                            set: { value in store.updateNotifications { $0.setVolume(value) } }
                        ),
                        in: 0...1
                    ) { editing in
                        if !editing { DeckNotifier.shared.play(rule.sound, volume: store.notifications.volume) }
                    }
                }
                Toggle("No avisar de la sesión que estoy mirando", isOn: setting(\.quietWhenViewing))
            }
            .disabled(!store.notifications.enabled)
            Section("Eventos") {
                ForEach(NotificationKind.allCases) { kind in
                    Toggle(isOn: ruleBinding(kind, \.enabled)) {
                        Label(kind.label, systemImage: kind.symbolName)
                    }
                }
            }
            .disabled(!store.notifications.enabled)
            Section("Sonido y texto") {
                Picker("Evento", selection: $store.notificationEditingKind) {
                    ForEach(NotificationKind.allCases) { Text($0.label).tag($0) }
                }
                Picker("Sonido", selection: Binding(
                    get: { rule.sound },
                    set: { name in
                        store.updateNotifications { $0.update(editing) { $0.sound = name } }
                        DeckNotifier.shared.play(name, volume: store.notifications.volume)
                    }
                )) {
                    Text("Ninguno").tag(NotificationRule.silent)
                    Divider()
                    ForEach(DeckNotifier.availableSounds, id: \.self) { Text($0).tag($0) }
                }
                TextField("Título", text: ruleBinding(editing, \.title))
                TextField("Mensaje", text: ruleBinding(editing, \.body))
                Text("Puedes usar " + editing.placeholders.map { "{\($0)}" }.joined(separator: ", ") + ".")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    Button("Probar") {
                        DeckNotifier.shared.show(store.notifications.preview(editing), settings: store.notifications)
                    }
                    Spacer()
                    Button("Restaurar este evento") {
                        store.updateNotifications { $0.resetRule(editing) }
                    }
                    .disabled(rule == editing.defaultRule)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 500)
    }

    private var editing: NotificationKind { store.notificationEditingKind }

    private var rule: NotificationRule { store.notifications.rule(for: editing) }

    private var durationLabel: String {
        let seconds = store.notifications.duration
        return seconds == NotificationSettings.untilDismissed ? "Hasta cerrarlo" : "\(Int(seconds)) s"
    }

    private func setting<Value>(_ keyPath: WritableKeyPath<NotificationSettings, Value>) -> Binding<Value> {
        Binding(
            get: { store.notifications[keyPath: keyPath] },
            set: { value in store.updateNotifications { $0[keyPath: keyPath] = value } }
        )
    }

    private func ruleBinding<Value>(_ kind: NotificationKind, _ keyPath: WritableKeyPath<NotificationRule, Value>) -> Binding<Value> {
        Binding(
            get: { store.notifications.rule(for: kind)[keyPath: keyPath] },
            set: { value in store.updateNotifications { $0.update(kind) { $0[keyPath: keyPath] = value } } }
        )
    }
}

struct DeckSettingsView: View {
    let store: DeckStore

    var body: some View {
        TabView {
            AppearanceSettingsView(store: store)
                .tabItem { Label("Apariencia", systemImage: "paintpalette") }
            NotificationSettingsView(store: store)
                .tabItem { Label("Notificaciones", systemImage: "bell") }
        }
    }
}
