import Foundation

public enum EventLog {
    public static let rotationThreshold: UInt64 = 2 * 1024 * 1024

    public static func append(_ event: HookEvent, to url: URL) throws {
        guard let line = event.encodedLine() else { return }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let descriptor = open(url.path, O_WRONLY | O_APPEND | O_CREAT, 0o600)
        guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        defer { close(descriptor) }
        _ = line.withUnsafeBytes { write(descriptor, $0.baseAddress, $0.count) }
    }

    public static func rotateIfNeeded(_ url: URL) {
        guard TailReader.fileSize(of: url) > rotationThreshold else { return }
        let archive = url.deletingPathExtension().appendingPathExtension("1.jsonl")
        try? FileManager.default.removeItem(at: archive)
        try? FileManager.default.moveItem(at: url, to: archive)
    }
}
