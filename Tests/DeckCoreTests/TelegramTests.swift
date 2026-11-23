import Foundation
import Testing
@testable import DeckCore

struct TelegramTests {
    let directory = TemporaryDirectory()

    private func configured() -> TelegramSettings {
        var settings = TelegramSettings()
        settings.enabled = true
        settings.chatId = "123"
        settings.setIdleMinutes(5)
        return settings
    }

    @Test func sendsOnlyWhenOnAwayAndConfigured() {
        let settings = configured()
        #expect(settings.shouldSend(.permission, idleSeconds: 300, hasToken: true))
        #expect(!settings.shouldSend(.permission, idleSeconds: 299, hasToken: true))
        #expect(!settings.shouldSend(.permission, idleSeconds: 999, hasToken: false))
        #expect(!settings.shouldSend(.subagentFinished, idleSeconds: 999, hasToken: true))

        var off = settings
        off.enabled = false
        #expect(!off.shouldSend(.permission, idleSeconds: 999, hasToken: true))

        var noChat = settings
        noChat.chatId = "  "
        #expect(!noChat.shouldSend(.permission, idleSeconds: 999, hasToken: true))

        var always = settings
        always.setIdleMinutes(-3)
        #expect(always.idleMinutes == TelegramSettings.always)
        #expect(always.shouldSend(.turnFinished, idleSeconds: 0, hasToken: true))
    }

    @Test func buildsTheSendMessageRequest() throws {
        let request = TelegramAPI.sendMessageRequest(token: "1:ABC", chatId: "-100", text: "hola")
        #expect(request.url?.absoluteString == "https://api.telegram.org/bot1:ABC/sendMessage")
        #expect(request.httpMethod == "POST")
        let body = try #require(request.httpBody)
        let object = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        #expect(object?["chat_id"] as? String == "-100")
        #expect(object?["text"] as? String == "hola")
        #expect(TelegramAPI.updatesRequest(token: "1:ABC").url?.absoluteString == "https://api.telegram.org/bot1:ABC/getUpdates")
    }

    @Test func formatsTheMessageFromTheAlert() {
        let alert = DeckAlert(kind: .permission, sessionId: "s", title: "Guardia", body: "Necesita tu permiso: Bash", sound: "")
        #expect(TelegramAPI.text(for: alert) == "🟠 Guardia\nNecesita tu permiso: Bash")
        let bare = DeckAlert(kind: .turnFinished, sessionId: "s", title: "Uno", body: "", sound: "")
        #expect(TelegramAPI.text(for: bare) == "✅ Uno")
    }

    @Test func findsChatsNewestFirstWithoutDuplicates() {
        let updates = #"""
        {"ok":true,"result":[
          {"update_id":1,"message":{"chat":{"id":111,"first_name":"Ana","last_name":"Paz","type":"private"}}},
          {"update_id":2,"message":{"chat":{"id":-222,"title":"Equipo","type":"group"}}},
          {"update_id":3,"message":{"chat":{"id":111,"first_name":"Ana","type":"private"}}},
          {"update_id":4,"my_chat_member":{}}
        ]}
        """#
        let chats = TelegramAPI.chats(fromUpdates: Data(updates.utf8))
        #expect(chats == [TelegramChat(id: "111", name: "Ana"), TelegramChat(id: "-222", name: "Equipo")])
        #expect(TelegramAPI.chats(fromUpdates: Data("x".utf8)).isEmpty)
    }

    @Test func reportsTelegramFailures() {
        #expect(TelegramAPI.failure(from: Data(#"{"ok":true}"#.utf8), status: 200) == nil)
        #expect(TelegramAPI.failure(from: Data(#"{"ok":false,"description":"Unauthorized"}"#.utf8), status: 401) == "Unauthorized")
        #expect(TelegramAPI.failure(from: Data(), status: 502) == "Telegram respondió 502")
    }

    @Test func tokenIsPrivateAndCanBeRemoved() throws {
        let store = TelegramTokenStore(file: directory.url.appendingPathComponent("deck/telegram-token"))
        #expect(store.load().isEmpty)

        try store.save("  1:ABC \n")
        #expect(store.load() == "1:ABC")
        let permissions = try FileManager.default.attributesOfItem(atPath: store.file.path)[.posixPermissions] as? NSNumber
        #expect(permissions?.intValue == 0o600)

        try store.save("")
        #expect(!FileManager.default.fileExists(atPath: store.file.path))
    }

    @Test func settingsRoundTripAndOlderFilesGetDefaults() throws {
        let store = NotificationStore(file: directory.url.appendingPathComponent("deck/notifications.json"))
        var settings = NotificationSettings()
        settings.telegram = configured()
        settings.telegram.kinds = [.sessionEnded]
        try store.save(settings)
        #expect(store.load() == settings)

        write(#"{"enabled":true}"#, to: store.file)
        #expect(store.load().telegram == TelegramSettings())
        write(#"{"telegram":{"enabled":true,"kinds":["permission","raro"],"idleMinutes":900}}"#, to: store.file)
        #expect(store.load().telegram.kinds == [.permission])
        #expect(store.load().telegram.idleMinutes == TelegramSettings.idleRange.upperBound)
    }

    @Test func telegramIgnoresTheFloatingSwitches() {
        var settings = NotificationSettings()
        settings.enabled = false
        let trigger = AlertTrigger(kind: .turnFinished, sessionId: "s1", values: ["sesion": "Uno"])
        #expect(settings.alert(for: trigger) == nil)
        #expect(settings.rendered(trigger).title == "Uno")
        #expect(settings.rendered(trigger).body == "Terminó y espera tu respuesta")
    }
}
