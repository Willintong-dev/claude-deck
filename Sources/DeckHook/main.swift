import DeckCore
import Foundation

let payload = FileHandle.standardInput.readDataToEndOfFile()

if CommandLine.arguments.dropFirst().first == "statusline" {
    if let line = StatusLine.line(for: payload, catalog: SessionCatalogStore.standard.load()) {
        FileHandle.standardOutput.write(Data(line.utf8))
    }
    exit(0)
}

let claudePid = ProcessTree.ancestor(of: getppid()) { ProcessTree.isClaudeExecutable($0.path) }

if let event = HookEvent.fromHookPayload(payload, timestamp: Date(), pid: claudePid) {
    try? EventLog.append(event, to: DeckPaths.standard.eventsFile)
    if event.event == "SessionStart",
       let output = HookOutput.sessionStartBrain(environment: ProcessInfo.processInfo.environment, source: event.source) {
        FileHandle.standardOutput.write(output)
    }
}
exit(0)
