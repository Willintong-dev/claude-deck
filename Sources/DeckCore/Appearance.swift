import Foundation

public struct RGB: Equatable, Sendable {
    public let red: UInt8
    public let green: UInt8
    public let blue: UInt8

    public init?(hex: String) {
        let digits = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else { return nil }
        red = UInt8((value >> 16) & 0xFF)
        green = UInt8((value >> 8) & 0xFF)
        blue = UInt8(value & 0xFF)
    }

    public var luminance: Double {
        (0.2126 * Double(red) + 0.7152 * Double(green) + 0.0722 * Double(blue)) / 255
    }
}

public struct TerminalTheme: Equatable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let background: String
    public let foreground: String
    public let cursor: String
    public let selection: String
    public let ansi: [String]

    public var isDark: Bool { (RGB(hex: background)?.luminance ?? 0) < 0.5 }

    public static let fallback = all[0]

    public static func named(_ id: String?) -> TerminalTheme {
        all.first { $0.id == id } ?? fallback
    }

    public static let all: [TerminalTheme] = [
        TerminalTheme(
            id: "deck-dark", name: "Deck oscuro",
            background: "1C1C1E", foreground: "E6E6E6", cursor: "E6E6E6", selection: "3A3D41",
            ansi: ["1C1C1E", "FF5F57", "5FD068", "F5C451", "4EA1FF", "C177F5", "4FD1C5", "D0D0D0",
                   "6E6E73", "FF7B72", "7EE787", "F9E2AF", "79C0FF", "D2A8FF", "76E3EA", "FFFFFF"]
        ),
        TerminalTheme(
            id: "deck-light", name: "Deck claro",
            background: "FFFFFF", foreground: "1D1D1F", cursor: "1D1D1F", selection: "B4D5FE",
            ansi: ["000000", "C4161C", "1A7F37", "9A6700", "0550AE", "8250DF", "1B7C83", "6E7781",
                   "57606A", "D1242F", "2DA44E", "BF8700", "218BFF", "A475F9", "3192AA", "8C959F"]
        ),
        TerminalTheme(
            id: "solarized-dark", name: "Solarized oscuro",
            background: "002B36", foreground: "839496", cursor: "93A1A1", selection: "073642",
            ansi: solarized
        ),
        TerminalTheme(
            id: "solarized-light", name: "Solarized claro",
            background: "FDF6E3", foreground: "657B83", cursor: "586E75", selection: "EEE8D5",
            ansi: solarized
        ),
        TerminalTheme(
            id: "nord", name: "Nord",
            background: "2E3440", foreground: "D8DEE9", cursor: "D8DEE9", selection: "434C5E",
            ansi: ["3B4252", "BF616A", "A3BE8C", "EBCB8B", "81A1C1", "B48EAD", "88C0D0", "E5E9F0",
                   "4C566A", "BF616A", "A3BE8C", "EBCB8B", "81A1C1", "B48EAD", "8FBCBB", "ECEFF4"]
        ),
        TerminalTheme(
            id: "dracula", name: "Dracula",
            background: "282A36", foreground: "F8F8F2", cursor: "F8F8F2", selection: "44475A",
            ansi: ["21222C", "FF5555", "50FA7B", "F1FA8C", "BD93F9", "FF79C6", "8BE9FD", "F8F8F2",
                   "6272A4", "FF6E6E", "69FF94", "FFFFA5", "D6ACFF", "FF92DF", "A4FFFF", "FFFFFF"]
        ),
        TerminalTheme(
            id: "gruvbox-dark", name: "Gruvbox oscuro",
            background: "282828", foreground: "EBDBB2", cursor: "EBDBB2", selection: "504945",
            ansi: ["282828", "CC241D", "98971A", "D79921", "458588", "B16286", "689D6A", "A89984",
                   "928374", "FB4934", "B8BB26", "FABD2F", "83A598", "D3869B", "8EC07C", "EBDBB2"]
        ),
        TerminalTheme(
            id: "one-dark", name: "One Dark",
            background: "282C34", foreground: "ABB2BF", cursor: "528BFF", selection: "3E4451",
            ansi: ["282C34", "E06C75", "98C379", "E5C07B", "61AFEF", "C678DD", "56B6C2", "ABB2BF",
                   "5C6370", "E06C75", "98C379", "E5C07B", "61AFEF", "C678DD", "56B6C2", "FFFFFF"]
        ),
    ]

    private static let solarized = [
        "073642", "DC322F", "859900", "B58900", "268BD2", "D33682", "2AA198", "EEE8D5",
        "002B36", "CB4B16", "586E75", "657B83", "839496", "6C71C4", "93A1A1", "FDF6E3",
    ]
}

public enum AppearanceScope: String, Codable, CaseIterable, Sendable {
    case session
    case all

    public var label: String {
        switch self {
        case .session: return "Esta sesión"
        case .all: return "Todas las sesiones"
        }
    }
}

public enum AppTheme: String, Codable, CaseIterable, Sendable {
    case system
    case light
    case dark

    public var label: String {
        switch self {
        case .system: return "Como el sistema"
        case .light: return "Claro"
        case .dark: return "Oscuro"
        }
    }
}

public struct TerminalAppearance: Codable, Equatable, Sendable {
    public var themeId: String
    public var fontName: String
    public var fontSize: Double

    public static let systemFont = ""
    public static let standard = TerminalAppearance(themeId: TerminalTheme.fallback.id, fontName: systemFont, fontSize: 12.5)
    public static let sizeRange: ClosedRange<Double> = 8...32
    public static let zoomStep: Double = 1

    public init(themeId: String, fontName: String, fontSize: Double) {
        self.themeId = themeId
        self.fontName = fontName
        self.fontSize = Self.clamp(fontSize)
    }

    public var theme: TerminalTheme { TerminalTheme.named(themeId) }

    public static func clamp(_ size: Double) -> Double {
        min(max(size, sizeRange.lowerBound), sizeRange.upperBound)
    }
}

public struct AppearanceOverride: Codable, Equatable, Sendable {
    public var themeId: String?
    public var fontName: String?
    public var fontSize: Double?

    public init(themeId: String? = nil, fontName: String? = nil, fontSize: Double? = nil) {
        self.themeId = themeId
        self.fontName = fontName
        self.fontSize = fontSize
    }

    public var isEmpty: Bool { themeId == nil && fontName == nil && fontSize == nil }
}

public struct AppearanceSettings: Codable, Equatable, Sendable {
    public var appTheme: AppTheme = .system
    public private(set) var defaults: TerminalAppearance = .standard
    public private(set) var overrides: [String: AppearanceOverride] = [:]
    public var sidebar = SidebarStyle()

    public init() {}

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        appTheme = (try? container.decodeIfPresent(AppTheme.self, forKey: .appTheme)) ?? .system
        defaults = (try? container.decodeIfPresent(TerminalAppearance.self, forKey: .defaults)) ?? .standard
        overrides = (try? container.decodeIfPresent([String: AppearanceOverride].self, forKey: .overrides)) ?? [:]
        sidebar = (try? container.decodeIfPresent(SidebarStyle.self, forKey: .sidebar)) ?? SidebarStyle()
    }

    public func resolved(for sessionId: String?) -> TerminalAppearance {
        guard let sessionId, let override = overrides[sessionId] else { return defaults }
        return TerminalAppearance(
            themeId: override.themeId ?? defaults.themeId,
            fontName: override.fontName ?? defaults.fontName,
            fontSize: override.fontSize ?? defaults.fontSize
        )
    }

    public func isCustomized(_ sessionId: String) -> Bool {
        overrides[sessionId] != nil
    }

    public mutating func update(_ sessionId: String?, scope: AppearanceScope, _ change: (inout TerminalAppearance) -> Void) {
        let before = resolved(for: sessionId)
        var after = before
        change(&after)
        after.fontSize = TerminalAppearance.clamp(after.fontSize)
        if scope == .session, let sessionId {
            store(after, for: sessionId)
            return
        }
        if after.themeId != before.themeId {
            defaults.themeId = after.themeId
            clearOverrides(\.themeId)
        }
        if after.fontName != before.fontName {
            defaults.fontName = after.fontName
            clearOverrides(\.fontName)
        }
        if after.fontSize != before.fontSize {
            defaults.fontSize = after.fontSize
            clearOverrides(\.fontSize)
        }
        for id in Array(overrides.keys) { store(resolved(for: id), for: id) }
    }

    public mutating func zoom(_ sessionId: String?, steps: Int, scope: AppearanceScope = .session) {
        update(sessionId, scope: scope) { $0.fontSize += Double(steps) * TerminalAppearance.zoomStep }
    }

    private mutating func clearOverrides<Value>(_ field: WritableKeyPath<AppearanceOverride, Value?>) {
        for id in Array(overrides.keys) {
            overrides[id]?[keyPath: field] = nil
            if overrides[id]?.isEmpty == true { overrides[id] = nil }
        }
    }

    public mutating func resetZoom(_ sessionId: String, scope: AppearanceScope = .session) {
        if scope == .all {
            defaults.fontSize = TerminalAppearance.standard.fontSize
            clearOverrides(\.fontSize)
            return
        }
        guard var override = overrides[sessionId] else { return }
        override.fontSize = nil
        overrides[sessionId] = override.isEmpty ? nil : override
    }

    public mutating func reset(_ sessionId: String) {
        overrides[sessionId] = nil
    }

    private mutating func store(_ appearance: TerminalAppearance, for sessionId: String) {
        let override = AppearanceOverride(
            themeId: appearance.themeId == defaults.themeId ? nil : appearance.themeId,
            fontName: appearance.fontName == defaults.fontName ? nil : appearance.fontName,
            fontSize: appearance.fontSize == defaults.fontSize ? nil : appearance.fontSize
        )
        overrides[sessionId] = override.isEmpty ? nil : override
    }
}

public final class AppearanceStore: @unchecked Sendable {
    public let file: URL

    public init(file: URL) {
        self.file = file
    }

    public static var standard: AppearanceStore {
        AppearanceStore(file: DeckPaths.standard.deckDirectory.appendingPathComponent("appearance.json"))
    }

    public func load() -> AppearanceSettings {
        guard let data = try? Data(contentsOf: file) else { return AppearanceSettings() }
        return (try? JSONDecoder().decode(AppearanceSettings.self, from: data)) ?? AppearanceSettings()
    }

    public func save(_ settings: AppearanceSettings) throws {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(settings).write(to: file, options: .atomic)
    }
}
