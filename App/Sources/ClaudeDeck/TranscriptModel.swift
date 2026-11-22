import DeckCore
import Foundation
import Observation

@MainActor
@Observable
final class TranscriptModel {
    private(set) var messages: [TranscriptMessage] = []
    @ObservationIgnored private var loadedURL: URL?

    func load(_ url: URL?) async {
        guard let url else {
            messages = []
            loadedURL = nil
            return
        }
        if loadedURL == url {
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
        }
        let loaded = await Task.detached(priority: .utility) {
            TranscriptTail.recentMessages(at: url)
        }.value
        guard !Task.isCancelled else { return }
        if loaded != messages { messages = loaded }
        loadedURL = url
    }
}
