import Darwin
import Foundation

public enum ClaudeProcesses {
    private static let sessionFlags: Set<String> = ["--session-id", "--resume", "-r"]

    public static func sessionId(fromArguments arguments: [String]) -> String? {
        for (index, argument) in arguments.enumerated() {
            if sessionFlags.contains(argument), index + 1 < arguments.count, isSessionId(arguments[index + 1]) {
                return arguments[index + 1]
            }
            for flag in sessionFlags where argument.hasPrefix(flag + "=") {
                let value = String(argument.dropFirst(flag.count + 1))
                if isSessionId(value) { return value }
            }
        }
        return nil
    }

    public static func isSessionId(_ value: String) -> Bool {
        UUID(uuidString: value) != nil
    }

    public static func running() -> [Int32: String] {
        var result: [Int32: String] = [:]
        for pid in allPids() where pid > 1 {
            guard let path = ProcessTree.entry(of: pid)?.path,
                  ProcessTree.isClaudeExecutable(path),
                  let arguments = arguments(of: pid),
                  let sessionId = sessionId(fromArguments: arguments)
            else { continue }
            result[pid] = sessionId.lowercased()
        }
        return result
    }

    public static func sessionId(of pid: pid_t) -> String? {
        arguments(of: pid).flatMap(sessionId(fromArguments:))?.lowercased()
    }

    public static func arguments(of pid: pid_t) -> [String]? {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > MemoryLayout<Int32>.size else { return nil }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &buffer, &size, nil, 0) == 0 else { return nil }
        return parseProcArgs(Array(buffer.prefix(size)))
    }

    static func parseProcArgs(_ buffer: [UInt8]) -> [String]? {
        guard buffer.count > MemoryLayout<Int32>.size else { return nil }
        let argc = buffer.withUnsafeBytes { Int($0.loadUnaligned(as: Int32.self)) }
        var index = MemoryLayout<Int32>.size
        while index < buffer.count, buffer[index] != 0 { index += 1 }
        while index < buffer.count, buffer[index] == 0 { index += 1 }
        var arguments: [String] = []
        while arguments.count < argc, index < buffer.count {
            let start = index
            while index < buffer.count, buffer[index] != 0 { index += 1 }
            arguments.append(String(decoding: buffer[start..<index], as: UTF8.self))
            index += 1
        }
        return arguments
    }

    private static func allPids() -> [pid_t] {
        let capacity = proc_listallpids(nil, 0)
        guard capacity > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(capacity) + 64)
        let count = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size))
        guard count > 0 else { return [] }
        return Array(pids.prefix(Int(count)))
    }
}
