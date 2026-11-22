import AppKit
import DeckCore
import SwiftUI

@MainActor
enum SidebarFonts {
    static func font(family: String, size: Double) -> Font {
        if !family.isEmpty,
           let font = NSFontManager.shared.font(withFamily: family, traits: [], weight: 5, size: CGFloat(size)) {
            return Font(font)
        }
        return .system(size: CGFloat(size))
    }

    static let families: [String] = NSFontManager.shared.availableFontFamilies
        .filter { !$0.hasPrefix(".") }
        .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
}

extension SidebarAccent {
    var color: Color {
        hex.map { Color(nsColor: TerminalColors.color($0)) } ?? .accentColor
    }
}

extension SidebarStyle {
    @MainActor var titleFont: Font { SidebarFonts.font(family: fontFamily, size: titleSize) }
    @MainActor var detailFont: Font { SidebarFonts.font(family: fontFamily, size: detailSize) }

    func statusColor(_ byStatus: Color) -> Color {
        switch statusColors {
        case .byStatus: return byStatus
        case .accent: return accent.color
        case .monochrome: return .secondary
        }
    }
}

private struct SidebarStyleModifier: ViewModifier {
    let style: SidebarStyle

    func body(content: Content) -> some View {
        if let theme = style.backgroundTheme {
            content
                .tint(style.accent.color)
                .scrollContentBackground(.hidden)
                .background(Color(nsColor: TerminalColors.color(theme.background)))
                .foregroundStyle(Color(nsColor: TerminalColors.color(theme.foreground)))
                .environment(\.colorScheme, theme.isDark ? .dark : .light)
        } else {
            content.tint(style.accent.color)
        }
    }
}

extension View {
    func sidebarStyle(_ style: SidebarStyle) -> some View {
        modifier(SidebarStyleModifier(style: style))
    }
}

struct SidebarSettingsView: View {
    @Bindable var store: DeckStore

    var body: some View {
        Form {
            Section("Vista previa") {
                List {
                    SessionRow(session: Self.sample, title: "Sesión de ejemplo", owned: true, now: Date(), style: style)
                }
                .listStyle(.sidebar)
                .sidebarStyle(style)
                .frame(height: 64 + style.titleSize + style.detailSize)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            Section("Letra") {
                Picker("Tipo de letra", selection: binding(\.fontFamily)) {
                    Text("Del sistema").tag(SidebarStyle.systemFont)
                    Divider()
                    ForEach(SidebarFonts.families, id: \.self) { family in
                        Text(family).tag(family)
                    }
                }
                Stepper(value: Binding(get: { style.titleSize }, set: { size in store.updateSidebar { $0.setTitleSize(size) } }),
                        in: SidebarStyle.titleSizeRange, step: 1) {
                    LabeledContent("Tamaño del nombre", value: "\(Int(style.titleSize)) pt")
                }
                Stepper(value: Binding(get: { style.detailSize }, set: { size in store.updateSidebar { $0.setDetailSize(size) } }),
                        in: SidebarStyle.detailSizeRange, step: 1) {
                    LabeledContent("Tamaño del detalle", value: "\(Int(style.detailSize)) pt")
                }
            }
            Section("Qué muestra el detalle") {
                ForEach(SidebarDetail.allCases) { detail in
                    Toggle(detail.label, isOn: Binding(
                        get: { style.details.contains(detail) },
                        set: { visible in store.updateSidebar { $0.show(detail, visible) } }
                    ))
                }
                Text("Si apagas todo, cada sesión ocupa una sola línea.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Densidad, íconos y colores") {
                Picker("Íconos", selection: binding(\.iconStyle)) {
                    ForEach(SidebarIconStyle.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                Picker("Densidad", selection: binding(\.density)) {
                    ForEach(SidebarDensity.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                Picker("Color de acento", selection: binding(\.accent)) {
                    ForEach(SidebarAccent.allCases, id: \.self) { accent in
                        Label {
                            Text(accent.label)
                        } icon: {
                            Image(systemName: "circle.fill").foregroundStyle(accent.color)
                        }
                        .tag(accent)
                    }
                }
                Picker("Íconos de estado", selection: binding(\.statusColors)) {
                    ForEach(SidebarStatusColors.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                Picker("Fondo", selection: binding(\.backgroundThemeId)) {
                    Text("Del sistema").tag(String?.none)
                    Divider()
                    ForEach(TerminalTheme.all) { theme in
                        Text(theme.name).tag(String?.some(theme.id))
                    }
                }
            }
            Section {
                Button("Restaurar la lista") {
                    store.updateSidebar { $0 = SidebarStyle() }
                }
                .disabled(style == SidebarStyle())
            }
        }
        .formStyle(.grouped)
        .frame(width: 500, height: 640)
    }

    private var style: SidebarStyle { store.sidebarStyle }

    private func binding<Value>(_ keyPath: WritableKeyPath<SidebarStyle, Value>) -> Binding<Value> {
        Binding(
            get: { store.sidebarStyle[keyPath: keyPath] },
            set: { value in store.updateSidebar { $0[keyPath: keyPath] = value } }
        )
    }

    private static let sample: SessionState = {
        var session = SessionState(id: "preview", project: "claude-deck")
        session.live.status = .working
        session.summary.cwd = "/Users/tu/claude-deck"
        session.summary.gitBranch = "main"
        session.summary.contextTokens = 42_000
        session.summary.lastActivity = Date().addingTimeInterval(-120)
        session.summary.preview = "Listo, ya quedó el README."
        return session
    }()
}

extension SessionStatus {
    var badgeSymbol: String {
        switch self {
        case .waiting: return "exclamationmark"
        case .working: return "ellipsis"
        case .idle: return "checkmark"
        case .open: return "circle.fill"
        case .ended: return "stop.fill"
        case .unknown: return "questionmark"
        }
    }

    var badgeColor: Color {
        switch self {
        case .ended, .unknown: return .gray
        default: return color
        }
    }
}

struct IconTile: View {
    enum Content {
        case initials(String)
        case symbol(String)
    }

    let content: Content
    let color: Color
    let size: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
            .fill(LinearGradient(colors: [color.opacity(0.95), color.opacity(0.65)], startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay(RoundedRectangle(cornerRadius: size * 0.3, style: .continuous).strokeBorder(.white.opacity(0.18)))
            .overlay {
                switch content {
                case let .initials(text):
                    Text(text)
                        .font(.system(size: size * 0.4, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .minimumScaleFactor(0.5)
                case let .symbol(name):
                    Image(systemName: name)
                        .font(.system(size: size * 0.45, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: size, height: size)
            .shadow(color: color.opacity(0.35), radius: 3, y: 1)
    }
}

struct AvatarStatusBadge: View {
    let status: SessionStatus
    let color: Color
    let size: CGFloat
    let ring: Color

    var body: some View {
        Circle()
            .fill(color)
            .overlay {
                Image(systemName: status.badgeSymbol)
                    .font(.system(size: size * 0.5, weight: .heavy))
                    .foregroundStyle(.white)
            }
            .frame(width: size, height: size)
            .overlay(Circle().strokeBorder(ring, lineWidth: max(1.5, size * 0.12)))
            .shadow(color: status == .waiting ? color.opacity(0.8) : .clear, radius: 4)
    }
}

struct SessionIcon: View {
    let session: SessionState
    let title: String
    let style: SidebarStyle
    var attention: SessionAttention = .seen

    var body: some View {
        switch style.iconStyle {
        case .simple:
            Image(systemName: session.live.status.symbolName)
                .foregroundStyle(style.statusColor(session.live.status.color))
                .font(style.detailFont)
                .padding(.top, 3)
        case .avatar:
            IconTile(content: .initials(SessionAvatar.initials(of: title)), color: avatarColor, size: tileSize)
                .saturation(session.live.status.isActive ? 1 : 0.35)
                .background {
                    if session.live.status.pulsePeriod > 0 {
                        PulseHalo(color: style.statusColor(session.live.status.badgeColor), period: session.live.status.pulsePeriod)
                            .allowsHitTesting(false)
                    }
                }
                .overlay(alignment: .bottomTrailing) {
                    AvatarStatusBadge(status: session.live.status, color: attention == .seen ? .gray : style.statusColor(session.live.status.badgeColor), size: tileSize * 0.48, ring: style.ringColor)
                        .offset(x: tileSize * 0.14, y: tileSize * 0.14)
                }
                .padding(.trailing, tileSize * 0.14)
                .padding(.bottom, tileSize * 0.1)
        }
    }

    private var tileSize: CGFloat { style.iconSize }

    private var avatarColor: Color {
        Color(nsColor: TerminalColors.color(SessionAvatar.colorHex(for: session.id)))
    }
}

extension SidebarStyle {
    var iconSize: CGFloat {
        let lines = details.isEmpty ? titleSize * 1.3 : titleSize + detailSize + 6
        return CGFloat(max(22, lines + density.lineSpacing))
    }

    var ringColor: Color {
        backgroundTheme.map { Color(nsColor: TerminalColors.color($0.background)) } ?? Color(nsColor: .windowBackgroundColor)
    }
}

final class PulseHaloView: NSView {
    private let halo = CAShapeLayer()
    private var color: NSColor = .systemGreen
    private var period: Double = 0
    var cornerFraction: CGFloat = 0.3

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = false
        halo.fillColor = nil
        halo.lineWidth = 2
        layer?.addSublayer(halo)
    }

    required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
        halo.frame = bounds
        let radius = min(bounds.width, bounds.height) * cornerFraction
        halo.path = CGPath(roundedRect: bounds, cornerWidth: radius, cornerHeight: radius, transform: nil)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        restart()
    }

    func configure(color: NSColor, period: Double) {
        guard color != self.color || period != self.period else { return }
        self.color = color
        self.period = period
        restart()
    }

    private func restart() {
        halo.removeAllAnimations()
        halo.strokeColor = color.cgColor
        guard period > 0, window != nil, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            halo.opacity = 0
            return
        }
        let scale = CABasicAnimation(keyPath: "transform.scale")
        scale.fromValue = 1
        scale.toValue = 1.45
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0.9
        fade.toValue = 0
        let group = CAAnimationGroup()
        group.animations = [scale, fade]
        group.duration = period
        group.repeatCount = .infinity
        group.timingFunction = CAMediaTimingFunction(name: .easeOut)
        group.isRemovedOnCompletion = false
        halo.opacity = 0
        halo.add(group, forKey: "pulse")
    }
}

struct PulseHalo: NSViewRepresentable {
    let color: Color
    let period: Double

    func makeNSView(context: Context) -> PulseHaloView {
        PulseHaloView(frame: .zero)
    }

    func updateNSView(_ view: PulseHaloView, context: Context) {
        view.configure(color: NSColor(color), period: period)
    }
}

extension SessionStatus {
    var pulsePeriod: Double {
        switch self {
        case .waiting: return 1.0
        case .working: return 1.8
        default: return 0
        }
    }
}
