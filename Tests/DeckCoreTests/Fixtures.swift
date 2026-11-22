import Foundation
@testable import DeckCore

final class TemporaryDirectory {
    let url: URL

    init() {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("claude-deck-tests-\(UUID().uuidString)")
            .resolvingSymlinksInPath()
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }

    func file(_ relativePath: String) -> URL {
        let file = url.appendingPathComponent(relativePath)
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        return file
    }
}

func write(_ text: String, to url: URL) {
    try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try? Data(text.utf8).write(to: url)
}

func append(_ text: String, to url: URL) {
    guard let handle = try? FileHandle(forWritingTo: url) else {
        write(text, to: url)
        return
    }
    defer { try? handle.close() }
    _ = try? handle.seekToEnd()
    try? handle.write(contentsOf: Data(text.utf8))
}

enum Lines {
    static func title(_ title: String, session: String = "s1") -> String {
        #"{"type":"ai-title","aiTitle":"\#(title)","sessionId":"\#(session)"}"# + "\n"
    }

    static func user(_ text: String, at timestamp: String, uuid: String = UUID().uuidString, cwd: String = "/repo/app", branch: String = "main") -> String {
        #"{"type":"user","uuid":"\#(uuid)","timestamp":"\#(timestamp)","cwd":"\#(cwd)","gitBranch":"\#(branch)","isSidechain":false,"message":{"role":"user","content":"\#(text)"}}"# + "\n"
    }

    static func assistant(_ text: String, at timestamp: String, uuid: String = UUID().uuidString) -> String {
        #"{"type":"assistant","uuid":"\#(uuid)","timestamp":"\#(timestamp)","message":{"role":"assistant","content":[{"type":"thinking","thinking":"x"},{"type":"text","text":"\#(text)"}]}}"# + "\n"
    }

    static func toolResult(at timestamp: String) -> String {
        #"{"type":"user","uuid":"\#(UUID().uuidString)","timestamp":"\#(timestamp)","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"t1","content":"ok"}]}}"# + "\n"
    }
}

func date(_ iso: String) -> Date {
    try! Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(iso)
}
