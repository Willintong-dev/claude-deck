import Foundation

public struct LineBuffer {
    private var pending = Data()

    public init() {}

    public mutating func append(_ data: Data) -> [Data] {
        pending.append(data)
        var lines: [Data] = []
        var start = pending.startIndex
        while let newline = pending[start...].firstIndex(of: 0x0A) {
            if newline > start {
                lines.append(Data(pending[start..<newline]))
            }
            start = pending.index(after: newline)
        }
        pending = Data(pending[start...])
        return lines
    }
}
