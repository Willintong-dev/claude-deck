import DeckCore
import SwiftUI

struct TerminalAppearanceForm: View {
    @Bindable var store: DeckStore
    let sessionId: String?

    private var current: TerminalAppearance { store.terminalAppearance(for: sessionId) }
    private var scope: AppearanceScope { sessionId == nil ? .all : store.appearanceScope }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(sessionId == nil ? "Terminal de todas las sesiones" : "Apariencia")
                .font(.headline)
            if sessionId != nil {
                Picker("Aplicar a", selection: $store.appearanceScope) {
                    ForEach(AppearanceScope.allCases, id: \.self) { scope in
                        Text(scope.label).tag(scope)
                    }
                }
                .pickerStyle(.segmented)
                Text(scope == .session
                     ? "Los cambios solo afectan a esta sesión."
                     : "Los cambios se aplican a todas las sesiones, también a las que tenían ese ajuste personalizado.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Picker("Tema", selection: binding(\.themeId)) {
                ForEach(TerminalTheme.all) { theme in
                    HStack {
                        ThemeSwatch(theme: theme)
                        Text(theme.name)
                    }
                    .tag(theme.id)
                }
            }
            Picker("Letra", selection: binding(\.fontName)) {
                Text("SF Mono (sistema)").tag(TerminalAppearance.systemFont)
                Divider()
                ForEach(TerminalFonts.available, id: \.name) { font in
                    Text(font.label).tag(font.name)
                }
            }
            HStack {
                Text("Tamaño")
                Spacer()
                Button {
                    store.zoom(sessionId, steps: -1, scope: scope)
                } label: {
                    Image(systemName: "textformat.size.smaller")
                }
                .help("Alejar (⌘-)")
                Text(String(format: "%g pt", current.fontSize))
                    .monospacedDigit()
                    .frame(minWidth: 48)
                Button {
                    store.zoom(sessionId, steps: 1, scope: scope)
                } label: {
                    Image(systemName: "textformat.size.larger")
                }
                .help("Acercar (⌘+)")
            }
            LabeledContent("Margen") {
                HStack {
                    Slider(value: binding(\.padding), in: TerminalAppearance.paddingRange, step: 2)
                    Text("\(Int(current.padding)) pt")
                        .monospacedDigit()
                        .frame(width: 44, alignment: .trailing)
                }
            }
            LabeledContent("Opacidad") {
                HStack {
                    Slider(value: binding(\.opacity), in: TerminalAppearance.opacityRange, step: 0.05)
                    Text("\(Int((current.opacity * 100).rounded())) %")
                        .monospacedDigit()
                        .frame(width: 44, alignment: .trailing)
                }
            }
            ThemePreview(appearance: current)
            if let sessionId {
                HStack {
                    Text(store.isAppearanceCustomized(sessionId) ? "Esta sesión está personalizada" : "Esta sesión usa la apariencia de todas")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Quitar personalización") { store.resetAppearance(sessionId) }
                        .disabled(!store.isAppearanceCustomized(sessionId))
                }
            }
        }
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<TerminalAppearance, Value>) -> Binding<Value> {
        Binding(
            get: { store.terminalAppearance(for: sessionId)[keyPath: keyPath] },
            set: { value in store.updateAppearance(sessionId, scope: scope) { $0[keyPath: keyPath] = value } }
        )
    }
}

struct ThemeSwatch: View {
    let theme: TerminalTheme

    var body: some View {
        HStack(spacing: 0) {
            ForEach([theme.background, theme.ansi[1], theme.ansi[2], theme.ansi[4]], id: \.self) { hex in
                Rectangle().fill(Color(nsColor: TerminalColors.color(hex)))
            }
        }
        .frame(width: 28, height: 12)
        .clipShape(RoundedRectangle(cornerRadius: 2))
    }
}

struct ThemePreview: View {
    let appearance: TerminalAppearance

    var body: some View {
        let theme = appearance.theme
        VStack(alignment: .leading, spacing: 2) {
            Text("> claude --resume")
                .foregroundStyle(color(theme.foreground))
            HStack(spacing: 0) {
                Text("✓ ").foregroundStyle(color(theme.ansi[2]))
                Text("tests ").foregroundStyle(color(theme.foreground))
                Text("✗ build").foregroundStyle(color(theme.ansi[1]))
            }
            Text("⏺ Leyendo cerebro…")
                .foregroundStyle(color(theme.ansi[4]))
        }
        .font(Font(TerminalFonts.font(named: appearance.fontName, size: appearance.fontSize)))
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 6).fill(color(theme.background)))
    }

    private func color(_ hex: String) -> Color {
        Color(nsColor: TerminalColors.color(hex))
    }
}

struct AppearanceSettingsView: View {
    @Bindable var store: DeckStore

    var body: some View {
        Form {
            Picker("Apariencia de la app", selection: $store.appTheme) {
                ForEach(AppTheme.allCases, id: \.self) { theme in
                    Text(theme.label).tag(theme)
                }
            }
            .pickerStyle(.segmented)
            Divider()
            TerminalAppearanceForm(store: store, sessionId: nil)
            Divider()
            Toggle("Barra de estado de Claude Deck", isOn: $store.claudeStatusLine)
            Text("Muestra nombre de la sesión, modelo, contexto y rama al pie de Claude, solo en las sesiones abiertas desde Claude Deck. Se aplica al abrir o reanudar una sesión.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("Desde el botón de la paleta en la cabecera de cada sesión eliges si un cambio es solo para esa sesión o para todas. El zoom con ⌘+, ⌘-, ⌘0 o pellizco sigue esa misma elección.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .frame(width: 440)
    }
}

struct ZoomCommands: Commands {
    let store: DeckStore

    var body: some Commands {
        CommandGroup(after: .toolbar) {
            Button("Acercar") { store.zoom(store.focusedTerminalSessionId, steps: 1, scope: store.appearanceScope) }
                .keyboardShortcut("+")
                .disabled(store.focusedTerminalSessionId == nil)
            Button("Acercar") { store.zoom(store.focusedTerminalSessionId, steps: 1, scope: store.appearanceScope) }
                .keyboardShortcut("=")
                .disabled(store.focusedTerminalSessionId == nil)
            Button("Alejar") { store.zoom(store.focusedTerminalSessionId, steps: -1, scope: store.appearanceScope) }
                .keyboardShortcut("-")
                .disabled(store.focusedTerminalSessionId == nil)
            Button("Tamaño real") {
                if let id = store.focusedTerminalSessionId { store.resetZoom(id, scope: store.appearanceScope) }
            }
            .keyboardShortcut("0")
            .disabled(store.focusedTerminalSessionId == nil)
            Divider()
        }
    }
}
