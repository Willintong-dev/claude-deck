import Foundation

public final class TailReader {
    public let url: URL
    public private(set) var offset: UInt64
    private var buffer = LineBuffer()
    private var skipsPartialFirstLine: Bool

    public init(url: URL, initialWindow: UInt64) {
        self.url = url
        let size = Self.fileSize(of: url)
        offset = size > initialWindow ? size - initialWindow : 0
        skipsPartialFirstLine = offset > 0
    }

    public func readNewLines() -> [Data] {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return [] }
        defer { try? handle.close() }
        let end = (try? handle.seekToEnd()) ?? 0
        if end < offset {
            offset = 0
            buffer = LineBuffer()
            skipsPartialFirstLine = false
        }
        guard end > offset else { return [] }
        try? handle.seek(toOffset: offset)
        let data = (try? handle.read(upToCount: Int(end - offset))) ?? Data()
        offset += UInt64(data.count)
        var lines = buffer.append(data)
        if skipsPartialFirstLine, !lines.isEmpty {
            lines.removeFirst()
            skipsPartialFirstLine = false
        }
        return lines
    }

    static func fileSize(of url: URL) -> UInt64 {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes?[.size] as? NSNumber)?.uint64Value ?? 0
    }
}
