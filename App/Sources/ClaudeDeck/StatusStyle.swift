import DeckCore
import SwiftUI

extension SessionStatus {
    var label: String {
        switch self {
        case .waiting: return "Esperando permiso"
        case .working: return "Trabajando"
        case .idle: return "En espera"
        case .open: return "Abierta"
        case .ended: return "Terminada"
        case .unknown: return "Sin estado"
        }
    }

    var color: Color {
        switch self {
        case .waiting: return .orange
        case .working: return .green
        case .idle: return .blue
        case .open: return .teal
        case .ended, .unknown: return .secondary
        }
    }

    var symbolName: String {
        switch self {
        case .waiting: return "exclamationmark.circle.fill"
        case .working: return "circle.fill"
        case .idle: return "pause.circle"
        case .open: return "circle.circle"
        case .ended: return "stop.circle"
        case .unknown: return "circle.dotted"
        }
    }
}

@MainActor
enum RelativeTime {
    private static let formatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "es")
        formatter.unitsStyle = .short
        return formatter
    }()

    static func describe(_ date: Date?, relativeTo now: Date) -> String {
        guard let date else { return "" }
        if now.timeIntervalSince(date) < 60 { return "ahora" }
        return formatter.localizedString(for: date, relativeTo: now)
    }
}
