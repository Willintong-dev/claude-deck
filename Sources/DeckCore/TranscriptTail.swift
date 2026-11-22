import Foundation

public enum TranscriptTail {
    public static func recentMessages(at url: URL, maximumBytes: UInt64 = 768 * 1024, limit: Int = 40) -> [TranscriptMessage] {
        let reader = TailReader(url: url, initialWindow: maximumBytes)
        let messages = reader.readNewLines().compactMap { TranscriptLine.parse($0)?.message }
        return Array(messages.suffix(limit))
    }
}
