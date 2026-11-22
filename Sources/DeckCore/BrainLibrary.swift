import CryptoKit
import Foundation

public struct SavedBrain: Codable, Equatable, Sendable, Identifiable {
    public var slug: String
    public var name: String
    public var createdAt: Date
    public var updatedAt: Date
    public var sessionIds: [String]

    public var id: String { slug }
}

public struct WorkingBrain: Codable, Equatable, Sendable {
    public var sessionId: String
    public var baseSlug: String?
    public var initialHash: String
    public var createdAt: Date
}

public enum BrainLibraryError: Error, Equatable {
    case missingWorkingBrain(String)
    case missingSavedBrain(String)
    case emptyName
}

public final class BrainLibrary: @unchecked Sendable {
    public static let maximumCharacters = 8000

    public let root: URL
    private let fileManager = FileManager.default
    private let now: () -> Date

    public init(root: URL, now: @escaping () -> Date = Date.init) {
        self.root = root
        self.now = now
    }

    public static var standard: BrainLibrary {
        BrainLibrary(root: DeckPaths.standard.deckDirectory.appendingPathComponent("brains"))
    }

    var savedDirectory: URL { root.appendingPathComponent("saved") }
    var sessionsDirectory: URL { root.appendingPathComponent("sessions") }

    public func savedBrainFile(_ slug: String) -> URL {
        savedDirectory.appendingPathComponent(slug).appendingPathComponent("BRAIN.md")
    }

    public func workingDirectory(_ sessionId: String) -> URL {
        sessionsDirectory.appendingPathComponent(sessionId)
    }

    public func workingBrainFile(_ sessionId: String) -> URL {
        workingDirectory(sessionId).appendingPathComponent("BRAIN.md")
    }

    public func systemPromptFile(_ sessionId: String) -> URL {
        workingDirectory(sessionId).appendingPathComponent("system-prompt.md")
    }

    public func savedBrains() -> [SavedBrain] {
        let directories = (try? fileManager.contentsOfDirectory(at: savedDirectory, includingPropertiesForKeys: nil)) ?? []
        return directories
            .compactMap { read(SavedBrain.self, from: $0.appendingPathComponent("meta.json")) }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    public func savedBrain(_ slug: String) -> SavedBrain? {
        read(SavedBrain.self, from: savedDirectory.appendingPathComponent(slug).appendingPathComponent("meta.json"))
    }

    public func workingBrain(_ sessionId: String) -> WorkingBrain? {
        read(WorkingBrain.self, from: workingDirectory(sessionId).appendingPathComponent("meta.json"))
    }

    public func workingSessionIds() -> [String] {
        ((try? fileManager.contentsOfDirectory(at: sessionsDirectory, includingPropertiesForKeys: nil)) ?? [])
            .map(\.lastPathComponent)
            .filter { workingBrain($0) != nil }
    }

    public func content(of file: URL) -> String {
        (try? String(contentsOf: file, encoding: .utf8)) ?? ""
    }

    @discardableResult
    public func prepareWorkingBrain(sessionId: String, baseSlug: String?, title: String?) throws -> WorkingBrain {
        if let existing = workingBrain(sessionId) { return existing }
        let content: String
        if let baseSlug {
            guard savedBrain(baseSlug) != nil else { throw BrainLibraryError.missingSavedBrain(baseSlug) }
            content = self.content(of: savedBrainFile(baseSlug))
        } else {
            content = Self.template(title: title)
        }
        try fileManager.createDirectory(at: workingDirectory(sessionId), withIntermediateDirectories: true)
        try content.write(to: workingBrainFile(sessionId), atomically: true, encoding: .utf8)
        let brain = WorkingBrain(sessionId: sessionId, baseSlug: baseSlug, initialHash: Self.hash(content), createdAt: now())
        try write(brain, to: workingDirectory(sessionId).appendingPathComponent("meta.json"))
        return brain
    }

    public func writeSystemPrompt(sessionId: String) throws -> URL {
        guard workingBrain(sessionId) != nil else { throw BrainLibraryError.missingWorkingBrain(sessionId) }
        let prompt = BrainPrompt.instructions(brainPath: workingBrainFile(sessionId).path)
        let file = systemPromptFile(sessionId)
        try prompt.write(to: file, atomically: true, encoding: .utf8)
        return file
    }

    public func isModified(_ sessionId: String) -> Bool {
        guard let brain = workingBrain(sessionId) else { return false }
        return Self.hash(content(of: workingBrainFile(sessionId))) != brain.initialHash
    }

    @discardableResult
    public func save(sessionId: String, name: String) throws -> SavedBrain {
        guard workingBrain(sessionId) != nil else { throw BrainLibraryError.missingWorkingBrain(sessionId) }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw BrainLibraryError.emptyName }
        let slug = Self.slug(for: trimmed)
        let directory = savedDirectory.appendingPathComponent(slug)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        try content(of: workingBrainFile(sessionId)).write(to: savedBrainFile(slug), atomically: true, encoding: .utf8)
        var saved = savedBrain(slug) ?? SavedBrain(slug: slug, name: trimmed, createdAt: now(), updatedAt: now(), sessionIds: [])
        saved.name = trimmed
        saved.updatedAt = now()
        if !saved.sessionIds.contains(sessionId) { saved.sessionIds.append(sessionId) }
        try write(saved, to: directory.appendingPathComponent("meta.json"))
        try discard(sessionId: sessionId)
        return saved
    }

    public func discard(sessionId: String) throws {
        let directory = workingDirectory(sessionId)
        if fileManager.fileExists(atPath: directory.path) {
            try fileManager.removeItem(at: directory)
        }
    }

    public func deleteSaved(_ slug: String) throws {
        let directory = savedDirectory.appendingPathComponent(slug)
        guard fileManager.fileExists(atPath: directory.path) else { throw BrainLibraryError.missingSavedBrain(slug) }
        try fileManager.removeItem(at: directory)
    }

    public static func slug(for name: String) -> String {
        let folded = name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "es"))
        let pieces = folded.lowercased().split { !$0.isLetter && !$0.isNumber }
        let slug = pieces.joined(separator: "-")
        return slug.isEmpty ? "cerebro" : String(slug.prefix(60))
    }

    public static func template(title: String?) -> String {
        """
        # \(title?.isEmpty == false ? title! : "Cerebro sin nombre")

        ## Propósito

        ## Contexto clave

        ## Decisiones

        ## Hallazgos y trampas

        ## Pendientes

        """
    }

    static func hash(_ content: String) -> String {
        SHA256.hash(data: Data(content.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private func read<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? Self.decoder.decode(type, from: data)
    }

    private func write<T: Encodable>(_ value: T, to url: URL) throws {
        try Self.encoder.encode(value).write(to: url, options: .atomic)
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

public enum BrainPrompt {
    public static let environmentKey = "CLAUDE_DECK_BRAIN"
    public static let contextThreshold = 100_000

    public static let finalUpdateRequest = "Vamos a cerrar esta sesión. Actualiza ahora tu cerebro (BRAIN.md) con lo que valga la pena conservar de esta sesión, compáctalo y no hagas nada más."
    public static let refreshRequest = "Vamos a liberar contexto. Actualiza ahora tu cerebro (BRAIN.md) con todo lo que haya que conservar de esta sesión, incluida la tarea en curso y el siguiente paso; compáctalo y no hagas nada más."
    public static let compactCommand = "/compact El conocimiento duradero de esta sesión ya está en el cerebro (BRAIN.md), que se recarga solo después de compactar. Resume en máximo 10 líneas solo la tarea en curso, el último estado y el siguiente paso."

    public static func instructions(brainPath: String) -> String {
        """
        # Cerebro de esta sesión

        Esta sesión tiene un cerebro persistente en `\(brainPath)`. Su contenido se te carga al iniciar, al reanudar y después de cada compactación. Sirve para que esta sesión, y las futuras que lo reutilicen, se especialicen sin tener que releer transcripts.

        Reglas:
        - Cuando termines una tarea o descubras algo que valga la pena recordar, actualiza ese archivo con la herramienta Edit. Hazlo sin pedir permiso y sin anunciarlo.
        - Si necesitas recordar algo de antes en esta misma sesión, búscalo primero en tu cerebro. No releas el transcript ni los archivos de la sesión para eso.
        - Guarda solo conocimiento reutilizable: propósito, contexto del dominio, decisiones y su porqué, hallazgos y trampas, rutas y comandos útiles, la tarea en curso y los pendientes.
        - Nunca guardes transcripts, logs largos, secretos, tokens ni datos personales.
        - Mantenlo por debajo de \(BrainLibrary.maximumCharacters) caracteres: reescribe y compacta en vez de solo agregar, y borra lo que quedó obsoleto.
        - Lo que dice el cerebro es contexto con fecha, no verdad: verifícalo contra el estado real antes de afirmarlo.
        """
    }

    public static func loadedContext(brainPath: String, content: String, source: String?) -> String {
        let moment: String
        switch source {
        case "compact": moment = "después de compactar"
        case "resume": moment = "al reanudar"
        case "clear": moment = "después de limpiar el contexto"
        default: moment = "al iniciar"
        }
        return "Contenido de tu cerebro (`\(brainPath)`), cargado \(moment):\n\n\(content)"
    }
}

public enum HookOutput {
    public static func additionalContext(event: String, text: String) -> Data? {
        let payload: [String: Any] = [
            "hookSpecificOutput": [
                "hookEventName": event,
                "additionalContext": text,
            ],
        ]
        return try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
    }

    public static func sessionStartBrain(environment: [String: String], source: String?) -> Data? {
        guard let path = environment[BrainPrompt.environmentKey],
              let content = try? String(contentsOfFile: path, encoding: .utf8),
              !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return nil }
        let text = BrainPrompt.loadedContext(brainPath: path, content: content, source: source)
        return additionalContext(event: "SessionStart", text: text)
    }
}
