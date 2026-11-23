import AppKit
import DeckCore
import SwiftTerm
import SwiftUI

@MainActor
final class TerminalHost: NSObject {
    static let shared = TerminalHost()

    var tmux: Tmux?
    var onDetached: ((String) -> Void)?
    var appearance: (String) -> TerminalAppearance = { _ in .standard }
    var onPinch: ((String, Int) -> Void)?
    private var terminals: [String: DeckTerminalView] = [:]
    private var applied: [String: TerminalAppearance] = [:]

    func terminal(for sessionId: String) -> DeckTerminalView? {
        if let existing = terminals[sessionId] { return existing }
        guard let tmux else { return nil }
        let view = DeckTerminalView(frame: NSRect(x: 0, y: 0, width: 800, height: 500))
        view.processDelegate = self
        view.onPinch = { [weak self] steps in self?.onPinch?(sessionId, steps) }
        apply(appearance(sessionId), to: view, sessionId: sessionId)
        view.startProcess(
            executable: tmux.executable.path,
            args: tmux.attachArguments(sessionId: sessionId),
            environment: Tmux.environment().map { "\($0.key)=\($0.value)" },
            execName: "tmux"
        )
        terminals[sessionId] = view
        return view
    }

    func refreshAppearance() {
        for (sessionId, view) in terminals {
            apply(appearance(sessionId), to: view, sessionId: sessionId)
        }
    }

    private func apply(_ appearance: TerminalAppearance, to view: DeckTerminalView, sessionId: String) {
        guard applied[sessionId] != appearance else { return }
        let previous = applied[sessionId]
        applied[sessionId] = appearance
        let theme = appearance.theme
        if previous?.themeId != appearance.themeId {
            view.installColors(theme.ansi.map(TerminalColors.terminalColor))
            view.nativeBackgroundColor = TerminalColors.color(theme.background)
            view.nativeForegroundColor = TerminalColors.color(theme.foreground)
            view.caretColor = TerminalColors.color(theme.cursor)
            view.selectedTextBackgroundColor = TerminalColors.color(theme.selection)
        }
        if previous?.themeId != appearance.themeId || previous?.opacity != appearance.opacity {
            view.backgroundOpacity = CGFloat(appearance.opacity)
        }
        (view.superview as? TerminalFrameView)?.apply(appearance)
        if previous?.fontName != appearance.fontName || previous?.fontSize != appearance.fontSize {
            view.font = TerminalFonts.font(named: appearance.fontName, size: appearance.fontSize)
        }
    }

    func detachAll() {
        let views = terminals.values
        terminals.removeAll()
        applied.removeAll()
        for view in views {
            view.terminate()
            view.removeFromSuperview()
        }
    }

    func forget(_ sessionId: String) {
        applied.removeValue(forKey: sessionId)
        guard let view = terminals.removeValue(forKey: sessionId) else { return }
        view.terminate()
        view.removeFromSuperview()
    }

    fileprivate func terminated(_ source: TerminalView) {
        guard let entry = terminals.first(where: { $0.value === source }) else { return }
        terminals.removeValue(forKey: entry.key)
        applied.removeValue(forKey: entry.key)
        entry.value.removeFromSuperview()
        onDetached?(entry.key)
    }
}

extension TerminalHost: LocalProcessTerminalViewDelegate {
    nonisolated func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}

    nonisolated func setTerminalTitle(source: LocalProcessTerminalView, title: String) {}

    nonisolated func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}

    nonisolated func processTerminated(source: TerminalView, exitCode: Int32?) {
        DispatchQueue.main.async {
            TerminalHost.shared.terminated(source)
        }
    }
}

struct TerminalContainer: NSViewRepresentable {
    let sessionId: String

    func makeNSView(context: Context) -> TerminalFrameView {
        let frame = TerminalFrameView()
        frame.apply(TerminalHost.shared.appearance(sessionId))
        return frame
    }

    func updateNSView(_ frame: TerminalFrameView, context: Context) {
        guard let terminal = TerminalHost.shared.terminal(for: sessionId) else { return }
        frame.apply(TerminalHost.shared.appearance(sessionId))
        guard terminal.superview !== frame else { return }
        frame.host(terminal)
        DispatchQueue.main.async {
            frame.window?.makeFirstResponder(terminal)
        }
    }
}

final class TerminalFrameView: NSView {
    private let blur = NSVisualEffectView()
    private let tint = NSView()
    private weak var terminal: NSView?
    private var padding: CGFloat = 0

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        blur.blendingMode = .behindWindow
        blur.material = .hudWindow
        blur.state = .active
        blur.autoresizingMask = [.width, .height]
        tint.wantsLayer = true
        tint.autoresizingMask = [.width, .height]
        addSubview(blur)
        addSubview(tint)
    }

    required init?(coder: NSCoder) {
        nil
    }

    func host(_ view: NSView) {
        terminal?.removeFromSuperview()
        view.removeFromSuperview()
        view.autoresizingMask = []
        addSubview(view)
        terminal = view
        needsLayout = true
    }

    func apply(_ appearance: TerminalAppearance) {
        let background = TerminalColors.color(appearance.theme.background)
        blur.isHidden = !appearance.isTranslucent
        tint.layer?.backgroundColor = background.withAlphaComponent(CGFloat(appearance.opacity)).cgColor
        blur.appearance = NSAppearance(named: appearance.theme.isDark ? .darkAqua : .aqua)
        guard padding != CGFloat(appearance.padding) else { return }
        padding = CGFloat(appearance.padding)
        needsLayout = true
    }

    override func layout() {
        super.layout()
        blur.frame = bounds
        tint.frame = bounds
        terminal?.frame = bounds.insetBy(dx: padding, dy: padding)
    }
}

final class DeckTerminalView: LocalProcessTerminalView {
    var onPinch: ((Int) -> Void)?
    private var pinch: CGFloat = 0

    override func magnify(with event: NSEvent) {
        if event.phase == .began { pinch = 0 }
        pinch += event.magnification
        let steps = Int(pinch / 0.12)
        guard steps != 0 else { return }
        pinch -= CGFloat(steps) * 0.12
        onPinch?(steps)
    }
}

enum TerminalColors {
    static func color(_ hex: String) -> NSColor {
        guard let rgb = RGB(hex: hex) else { return .textColor }
        return NSColor(srgbRed: CGFloat(rgb.red) / 255, green: CGFloat(rgb.green) / 255, blue: CGFloat(rgb.blue) / 255, alpha: 1)
    }

    static func terminalColor(_ hex: String) -> SwiftTerm.Color {
        let rgb = RGB(hex: hex)
        return SwiftTerm.Color(red8: UInt16(rgb?.red ?? 0), green8: UInt16(rgb?.green ?? 0), blue8: UInt16(rgb?.blue ?? 0))
    }
}

@MainActor
enum TerminalFonts {
    static func font(named name: String, size: Double) -> NSFont {
        if !name.isEmpty, let font = NSFont(name: name, size: CGFloat(size)) { return font }
        return NSFont.monospacedSystemFont(ofSize: CGFloat(size), weight: .regular)
    }

    static let available: [(name: String, label: String)] = {
        let names = NSFontManager.shared.availableFontNames(with: .fixedPitchFontMask) ?? []
        var seen: Set<String> = []
        return names.compactMap { name -> (String, String)? in
            guard let font = NSFont(name: name, size: 12) else { return nil }
            let traits = font.fontDescriptor.symbolicTraits
            guard !traits.contains(.bold), !traits.contains(.italic), !name.hasPrefix(".") else { return nil }
            let family = font.familyName ?? name
            guard seen.insert(family).inserted else { return nil }
            return (name, family)
        }
        .sorted { $0.1.localizedCaseInsensitiveCompare($1.1) == .orderedAscending }
    }()
}
