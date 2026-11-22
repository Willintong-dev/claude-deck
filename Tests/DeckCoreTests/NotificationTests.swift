import Foundation
import Testing
@testable import DeckCore

struct NotificationSettingsTests {
    let directory = TemporaryDirectory()

    @Test func everyKindHasADefaultRuleUntilItIsChanged() {
        var settings = NotificationSettings()
        #expect(settings.rule(for: .permission).sound == "Hero")
        #expect(settings.rule(for: .subagentFinished).enabled == false)

        settings.update(.permission) { $0.sound = "Glass" }
        #expect(settings.rule(for: .permission).sound == "Glass")
        #expect(settings.rule(for: .turnFinished) == NotificationKind.turnFinished.defaultRule)

        settings.update(.permission) { $0.sound = "Hero" }
        #expect(settings == NotificationSettings())

        settings.update(.permission) { $0.enabled = false }
        settings.resetRule(.permission)
        #expect(settings.rule(for: .permission).enabled)
    }

    @Test func rendersPlaceholdersAndDropsDanglingSeparators() {
        let values = ["sesion": "Guardia pagos", "mensaje": ""]
        #expect(NotificationTemplate.render("{sesion} pide algo", values) == "Guardia pagos pide algo")
        #expect(NotificationTemplate.render("Necesita tu permiso: {mensaje}", values) == "Necesita tu permiso")
        #expect(NotificationTemplate.render("Hola {nadie}", values) == "Hola")
    }

    @Test func buildsAlertsOnlyForEnabledKinds() {
        var settings = NotificationSettings()
        let trigger = AlertTrigger(kind: .permission, sessionId: "s1", values: ["sesion": "Uno", "mensaje": "usar Bash"])

        let alert = settings.alert(for: trigger)
        #expect(alert?.title == "Uno")
        #expect(alert?.body == "Necesita tu permiso: usar Bash")
        #expect(alert?.sound == "Hero")

        settings.update(.permission) { $0.title = "" }
        #expect(settings.alert(for: trigger)?.title == "Uno")

        settings.update(.permission) { $0.enabled = false }
        #expect(settings.alert(for: trigger) == nil)

        settings.resetRule(.permission)
        settings.enabled = false
        #expect(settings.alert(for: trigger) == nil)
    }

    @Test func previewWorksEvenForDisabledKindsWithSampleValues() {
        var settings = NotificationSettings()
        settings.enabled = false
        settings.update(.subagentFinished) { $0.sound = "Pop" }

        let alert = settings.preview(.subagentFinished)

        #expect(alert.title == "Sesión de ejemplo")
        #expect(alert.body == "Subagente listo: Buscar logs del pago")
        #expect(alert.sound == "Pop")
        #expect(alert.sessionId.isEmpty)
    }

    @Test func clampsDurationAndVolume() {
        var settings = NotificationSettings()
        settings.setDuration(99)
        settings.setVolume(-1)
        #expect(settings.duration == NotificationSettings.durationRange.upperBound)
        #expect(settings.volume == 0)
    }

    @Test func storeRoundTripsAndFallsBackOnBadFiles() throws {
        let store = NotificationStore(file: directory.url.appendingPathComponent("deck/notifications.json"))
        #expect(store.load() == NotificationSettings())

        var settings = NotificationSettings()
        settings.position = .bottomCenter
        settings.screen = .pointer
        settings.setDuration(0)
        settings.update(.turnFinished) { $0.body = "Listo en {proyecto}" }
        try store.save(settings)
        #expect(store.load() == settings)

        write(#"{"position":"rara","duration":500,"rules":{"permission":{"enabled":false,"sound":"","title":"x","body":"y"}}}"#, to: store.file)
        let loaded = store.load()
        #expect(loaded.position == .topRight)
        #expect(loaded.duration == 30)
        #expect(loaded.rule(for: .permission).enabled == false)
    }
}

struct NotificationDetectorTests {
    private func session(_ id: String, _ status: SessionStatus, message: String? = nil, cwd: String = "/repos/pagos") -> SessionState {
        var state = SessionState(id: id, project: "proj")
        state.live.status = status
        state.live.message = message
        state.summary.cwd = cwd
        return state
    }

    private func finishedSubagent(_ id: String, of sessionId: String, description: String) -> SubagentState {
        var subagent = SubagentState(id: id, sessionId: sessionId)
        subagent.meta = SubagentMeta(agentType: "general-purpose", description: description, finished: true, spawnDepth: 1)
        return subagent
    }

    private func detect(_ detector: inout NotificationDetector, _ sessions: [SessionState]) -> [AlertTrigger] {
        detector.triggers(in: Dictionary(uniqueKeysWithValues: sessions.map { ($0.id, $0) })) { "Título \($0.id)" }
    }

    @Test func theFirstSnapshotOnlySetsTheBaseline() {
        var detector = NotificationDetector()
        #expect(detect(&detector, [session("s1", .waiting)]).isEmpty)
        #expect(detect(&detector, [session("s1", .waiting)]).isEmpty)
    }

    @Test func detectsPermissionTurnAndEndTransitions() {
        var detector = NotificationDetector()
        _ = detect(&detector, [session("s1", .working), session("s2", .working), session("s3", .idle)])

        let triggers = detect(&detector, [
            session("s1", .waiting, message: "Claude needs your permission to use Bash"),
            session("s2", .idle),
            session("s3", .ended),
        ])

        #expect(triggers.map(\.kind) == [.permission, .turnFinished, .sessionEnded])
        #expect(triggers[0].values["mensaje"] == "Claude needs your permission to use Bash")
        #expect(triggers[0].values["sesion"] == "Título s1")
        #expect(triggers[0].values["proyecto"] == "pagos")
    }

    @Test func ignoresSessionsItHasNotSeenBeforeAndRepeatedStates() {
        var detector = NotificationDetector()
        _ = detect(&detector, [session("s1", .idle)])

        #expect(detect(&detector, [session("s1", .idle), session("nueva", .waiting)]).isEmpty)
        #expect(detect(&detector, [session("s1", .idle), session("nueva", .waiting)]).isEmpty)
        #expect(detect(&detector, [session("s1", .ended), session("nueva", .ended)]).map(\.kind) == [.sessionEnded, .sessionEnded])
    }

    @Test func approvingAPermissionAndThenFinishingCountsAsATurnFinished() {
        var detector = NotificationDetector()
        _ = detect(&detector, [session("s1", .waiting)])
        #expect(detect(&detector, [session("s1", .idle)]).map(\.kind) == [.turnFinished])
        #expect(detect(&detector, [session("s1", .open)]).isEmpty)
    }

    @Test func announcesEachFinishedSubagentOnce() {
        var detector = NotificationDetector()
        var parent = session("s1", .working)
        parent.subagents["old"] = finishedSubagent("old", of: "s1", description: "Viejo")
        _ = detect(&detector, [parent])

        var running = SubagentState(id: "a1", sessionId: "s1")
        running.meta = SubagentMeta(agentType: nil, description: "Buscar logs", finished: false, spawnDepth: 1)
        parent.subagents["a1"] = running
        #expect(detect(&detector, [parent]).isEmpty)

        parent.subagents["a1"] = finishedSubagent("a1", of: "s1", description: "Buscar logs")
        let triggers = detect(&detector, [parent])
        #expect(triggers.map(\.kind) == [.subagentFinished])
        #expect(triggers.first?.values["subagente"] == "Buscar logs")

        #expect(detect(&detector, [parent]).isEmpty)
    }
}
