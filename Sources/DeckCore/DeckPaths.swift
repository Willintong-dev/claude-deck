import Foundation

public struct DeckPaths: Sendable {
    public let projectsDirectory: URL
    public let deckDirectory: URL

    public init(projectsDirectory: URL, deckDirectory: URL) {
        self.projectsDirectory = projectsDirectory.resolvingSymlinksInPath()
        self.deckDirectory = deckDirectory.resolvingSymlinksInPath()
    }

    public var eventsFile: URL { deckDirectory.appendingPathComponent("events.jsonl") }

    public static var standard: DeckPaths {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return DeckPaths(
            projectsDirectory: home.appendingPathComponent(".claude/projects"),
            deckDirectory: home.appendingPathComponent(".claude-deck")
        )
    }
}
