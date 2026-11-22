import Foundation

public enum SidebarDetail: String, Codable, CaseIterable, Sendable, Identifiable {
    case folder
    case branch
    case context
    case lastActivity
    case preview

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .folder: return "Carpeta"
        case .branch: return "Rama de git"
        case .context: return "Contexto usado"
        case .lastActivity: return "Hace cuánto"
        case .preview: return "Último mensaje"
        }
    }
}

public enum SidebarDensity: String, Codable, CaseIterable, Sendable {
    case compact
    case normal
    case comfortable

    public var label: String {
        switch self {
        case .compact: return "Compacta"
        case .normal: return "Normal"
        case .comfortable: return "Amplia"
        }
    }

    public var rowPadding: Double {
        switch self {
        case .compact: return 0
        case .normal: return 2
        case .comfortable: return 6
        }
    }

    public var lineSpacing: Double {
        switch self {
        case .compact: return 0
        case .normal: return 2
        case .comfortable: return 4
        }
    }
}

public enum SidebarAccent: String, Codable, CaseIterable, Sendable {
    case system
    case blue
    case purple
    case pink
    case red
    case orange
    case yellow
    case green
    case teal
    case graphite

    public var label: String {
        switch self {
        case .system: return "Del sistema"
        case .blue: return "Azul"
        case .purple: return "Morado"
        case .pink: return "Rosado"
        case .red: return "Rojo"
        case .orange: return "Naranja"
        case .yellow: return "Amarillo"
        case .green: return "Verde"
        case .teal: return "Turquesa"
        case .graphite: return "Grafito"
        }
    }

    public var hex: String? {
        switch self {
        case .system: return nil
        case .blue: return "0A84FF"
        case .purple: return "BF5AF2"
        case .pink: return "FF375F"
        case .red: return "FF453A"
        case .orange: return "FF9F0A"
        case .yellow: return "FFD60A"
        case .green: return "30D158"
        case .teal: return "40C8E0"
        case .graphite: return "8E8E93"
        }
    }
}

public enum SidebarStatusColors: String, Codable, CaseIterable, Sendable {
    case byStatus
    case accent
    case monochrome

    public var label: String {
        switch self {
        case .byStatus: return "Un color por estado"
        case .accent: return "Color de acento"
        case .monochrome: return "Gris"
        }
    }
}

public enum SidebarIconStyle: String, Codable, CaseIterable, Sendable {
    case avatar
    case simple

    public var label: String {
        switch self {
        case .avatar: return "Avatar de color con estado"
        case .simple: return "Solo el estado"
        }
    }
}

public enum SessionAvatar {
    public static let palette = [
        "FF6B6B", "FF9F43", "F7B731", "26DE81", "20BF6B", "2BCBBA",
        "45AAF2", "4B7BEC", "A55EEA", "D980FA", "FD79A8", "778CA3",
    ]

    public static func colorHex(for sessionId: String) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in sessionId.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return palette[Int(hash % UInt64(palette.count))]
    }

    public static func initials(of title: String) -> String {
        let words = title
            .split { !$0.isLetter && !$0.isNumber }
            .filter { !$0.isEmpty }
        guard let first = words.first?.first else { return "?" }
        guard words.count > 1, let second = words[1].first else { return String(first).uppercased() }
        return (String(first) + String(second)).uppercased()
    }
}

public struct SidebarStyle: Codable, Equatable, Sendable {
    public var fontFamily = SidebarStyle.systemFont
    public private(set) var titleSize = 13.0
    public private(set) var detailSize = 11.0
    public private(set) var details: Set<SidebarDetail> = [.folder, .branch, .context, .lastActivity]
    public var density: SidebarDensity = .normal
    public var accent: SidebarAccent = .system
    public var statusColors: SidebarStatusColors = .byStatus
    public var backgroundThemeId: String?
    public var iconStyle: SidebarIconStyle = .avatar

    public static let systemFont = ""
    public static let titleSizeRange: ClosedRange<Double> = 10...22
    public static let detailSizeRange: ClosedRange<Double> = 9...18
    public static let separator = " · "

    public init() {}

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let standard = SidebarStyle()
        fontFamily = (try? container.decodeIfPresent(String.self, forKey: .fontFamily)) ?? standard.fontFamily
        titleSize = Self.clamp((try? container.decodeIfPresent(Double.self, forKey: .titleSize)) ?? standard.titleSize, Self.titleSizeRange)
        detailSize = Self.clamp((try? container.decodeIfPresent(Double.self, forKey: .detailSize)) ?? standard.detailSize, Self.detailSizeRange)
        details = (try? container.decodeIfPresent(Set<SidebarDetail>.self, forKey: .details)) ?? standard.details
        density = (try? container.decodeIfPresent(SidebarDensity.self, forKey: .density)) ?? standard.density
        accent = (try? container.decodeIfPresent(SidebarAccent.self, forKey: .accent)) ?? standard.accent
        statusColors = (try? container.decodeIfPresent(SidebarStatusColors.self, forKey: .statusColors)) ?? standard.statusColors
        backgroundThemeId = try? container.decodeIfPresent(String.self, forKey: .backgroundThemeId)
        iconStyle = (try? container.decodeIfPresent(SidebarIconStyle.self, forKey: .iconStyle)) ?? standard.iconStyle
    }

    public var orderedDetails: [SidebarDetail] {
        SidebarDetail.allCases.filter(details.contains)
    }

    public var backgroundTheme: TerminalTheme? {
        backgroundThemeId.flatMap { id in TerminalTheme.all.first { $0.id == id } }
    }

    public mutating func setTitleSize(_ size: Double) {
        titleSize = Self.clamp(size, Self.titleSizeRange)
    }

    public mutating func setDetailSize(_ size: Double) {
        detailSize = Self.clamp(size, Self.detailSizeRange)
    }

    public mutating func show(_ detail: SidebarDetail, _ visible: Bool) {
        if visible { details.insert(detail) } else { details.remove(detail) }
    }

    public func detailLine(_ values: [SidebarDetail: String]) -> String {
        orderedDetails
            .compactMap { values[$0] }
            .map { $0.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: Self.separator)
    }

    private static func clamp(_ value: Double, _ range: ClosedRange<Double>) -> Double {
        min(max(value, range.lowerBound), range.upperBound)
    }
}
