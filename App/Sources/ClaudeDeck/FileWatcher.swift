import CoreServices
import Foundation

final class FileWatcher {
    enum Change {
        case files([URL])
        case rescanRequired
    }

    private var stream: FSEventStreamRef?
    private let handler: (Change) -> Void

    init(paths: [URL], latency: TimeInterval, queue: DispatchQueue, handler: @escaping (Change) -> Void) {
        self.handler = handler
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        let flags = UInt32(
            kFSEventStreamCreateFlagFileEvents
                | kFSEventStreamCreateFlagUseCFTypes
                | kFSEventStreamCreateFlagNoDefer
                | kFSEventStreamCreateFlagIgnoreSelf
        )
        stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            Self.callback,
            &context,
            paths.map(\.path) as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            latency,
            flags
        )
        guard let stream else { return }
        FSEventStreamSetDispatchQueue(stream, queue)
        FSEventStreamStart(stream)
    }

    deinit {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
    }

    private static let rescanFlags = UInt32(
        kFSEventStreamEventFlagMustScanSubDirs
            | kFSEventStreamEventFlagUserDropped
            | kFSEventStreamEventFlagKernelDropped
            | kFSEventStreamEventFlagRootChanged
    )

    private static let callback: FSEventStreamCallback = { _, info, count, rawPaths, rawFlags, _ in
        guard let info else { return }
        let watcher = Unmanaged<FileWatcher>.fromOpaque(info).takeUnretainedValue()
        let paths = Unmanaged<CFArray>.fromOpaque(rawPaths).takeUnretainedValue() as? [String] ?? []
        let flags = UnsafeBufferPointer(start: rawFlags, count: count)
        if flags.contains(where: { $0 & rescanFlags != 0 }) {
            watcher.handler(.rescanRequired)
            return
        }
        let unique = Array(Set(paths)).map { URL(fileURLWithPath: $0) }
        watcher.handler(.files(unique))
    }
}
