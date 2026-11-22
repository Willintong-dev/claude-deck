import Foundation

final class ProcessWatcher {
    private var sources: [Int32: DispatchSourceProcess] = [:]
    private let queue: DispatchQueue
    private let onExit: (Int32) -> Void

    init(queue: DispatchQueue, onExit: @escaping (Int32) -> Void) {
        self.queue = queue
        self.onExit = onExit
    }

    func watch(_ pids: Set<Int32>) {
        for pid in Set(sources.keys).subtracting(pids) {
            sources.removeValue(forKey: pid)?.cancel()
        }
        for pid in pids.subtracting(sources.keys) {
            let source = DispatchSource.makeProcessSource(identifier: pid, eventMask: .exit, queue: queue)
            source.setEventHandler { [weak self] in
                self?.sources.removeValue(forKey: pid)?.cancel()
                self?.onExit(pid)
            }
            sources[pid] = source
            source.resume()
        }
    }
}
