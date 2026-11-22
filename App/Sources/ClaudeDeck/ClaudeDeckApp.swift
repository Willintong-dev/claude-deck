import AppKit
import DeckCore
import SwiftUI

@main
struct ClaudeDeckApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    private let store = DeckStore.shared

    var body: some Scene {
        MenuBarExtra {
            MenuContentView(store: store)
        } label: {
            MenuBarLabel(store: store)
        }
        .commands {
            ZoomCommands(store: store)
        }
        Settings {
            DeckSettingsView(store: store)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        DeckStore.shared.start()
        MainWindow.shared.show()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        MainWindow.shared.show()
        return true
    }
}

@MainActor
final class MainWindow: NSObject, NSWindowDelegate {
    static let shared = MainWindow()
    private var window: NSWindow?

    var isKey: Bool { window?.isKeyWindow == true }

    func show() {
        let window = window ?? makeWindow()
        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        TerminalHost.shared.detachAll()
        window = nil
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1000, height: 640),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        let hosting = NSHostingController(rootView: MainView(store: DeckStore.shared))
        hosting.sizingOptions = []
        window.title = "Claude Deck"
        window.isReleasedWhenClosed = false
        window.contentViewController = hosting
        window.contentMinSize = NSSize(width: 720, height: 420)
        window.setContentSize(NSSize(width: 1000, height: 640))
        window.delegate = self
        window.center()
        window.setFrameAutosaveName("ClaudeDeckWindow")
        return window
    }
}

struct MenuBarLabel: View {
    let store: DeckStore

    var body: some View {
        if store.waitingCount > 0 {
            Image(systemName: "exclamationmark.bubble.fill")
            Text("\(store.waitingCount)")
        } else if store.workingCount > 0 {
            Image(systemName: "bubble.left.and.bubble.right.fill")
        } else {
            Image(systemName: "bubble.left.and.bubble.right")
        }
    }
}

struct MenuContentView: View {
    let store: DeckStore

    var body: some View {
        let active = store.activeSessions
        if active.isEmpty {
            Text("Sin sesiones activas")
        } else {
            ForEach(active) { session in
                Button {
                    show(.session(session.id))
                } label: {
                    Label(menuTitle(for: session), systemImage: session.live.status.symbolName)
                }
            }
        }
        Divider()
        Button("Abrir Claude Deck") { show(nil) }
            .keyboardShortcut("o")
        Button("Nueva sesión…") {
            show(nil)
            store.showingNewSession = true
        }
        .keyboardShortcut("n")
        SettingsLink {
            Text("Ajustes…")
        }
        .keyboardShortcut(",")
        Button("Salir") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q")
    }

    private func menuTitle(for session: SessionState) -> String {
        let running = session.runningSubagentCount(at: Date())
        let suffix = running > 0 ? "  (\(running) subagentes)" : ""
        return "\(session.live.status.label) · \(store.title(of: session))\(suffix)"
    }

    private func show(_ selection: SidebarItem.ID?) {
        if let selection { store.selection = selection }
        MainWindow.shared.show()
    }
}
