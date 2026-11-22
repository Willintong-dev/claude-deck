import Darwin
import Foundation

public enum ProcessTree {
    public struct Entry: Equatable {
        public let pid: pid_t
        public let parent: pid_t
        public let path: String
        public let isZombie: Bool

        public var name: String { URL(fileURLWithPath: path).lastPathComponent }
    }

    public static func entry(of pid: pid_t) -> Entry? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, 4, &info, &size, nil, 0) == 0, size > 0 else { return nil }
        return Entry(
            pid: pid,
            parent: info.kp_eproc.e_ppid,
            path: executablePath(of: pid) ?? "",
            isZombie: info.kp_proc.p_stat == SZOMB
        )
    }

    public static func ancestor(of pid: pid_t, maximumDepth: Int = 8, matching predicate: (Entry) -> Bool) -> pid_t? {
        var current = pid
        for _ in 0..<maximumDepth {
            guard current > 1, let entry = entry(of: current) else { return nil }
            if predicate(entry) { return current }
            current = entry.parent
        }
        return nil
    }

    public static func isClaudeExecutable(_ path: String) -> Bool {
        let components = URL(fileURLWithPath: path).pathComponents
        if components.last == "claude" { return true }
        guard components.count >= 3 else { return false }
        return components[components.count - 2] == "versions" && components[components.count - 3] == "claude"
    }

    public static func isAlive(_ pid: pid_t) -> Bool {
        guard kill(pid, 0) == 0 || errno == EPERM else { return false }
        return entry(of: pid)?.isZombie != true
    }

    public static func ownerName(of pid: pid_t) -> String? {
        guard let parent = entry(of: pid)?.parent, parent > 1, let owner = entry(of: parent) else { return nil }
        let bundle = owner.path.components(separatedBy: "/").first { $0.hasSuffix(".app") }
        return bundle.map { String($0.dropLast(4)) } ?? owner.name
    }

    public static func terminate(_ pid: pid_t, gracePeriod: TimeInterval = 8, pollInterval: TimeInterval = 0.1) -> Bool {
        guard isAlive(pid) else { return true }
        kill(pid, SIGTERM)
        if waitForExit(pid, timeout: gracePeriod, pollInterval: pollInterval) { return true }
        kill(pid, SIGKILL)
        return waitForExit(pid, timeout: 2, pollInterval: pollInterval)
    }

    private static func waitForExit(_ pid: pid_t, timeout: TimeInterval, pollInterval: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if !isAlive(pid) { return true }
            Thread.sleep(forTimeInterval: pollInterval)
        }
        return !isAlive(pid)
    }

    private static func executablePath(of pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return nil }
        return String(decoding: buffer.prefix(Int(length)).map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }
}
