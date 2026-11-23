import CoreGraphics
import DeckCore
import Foundation

enum TelegramSender {
    static func send(_ text: String, token: String, chatId: String, completion: @escaping @Sendable (String?) -> Void) {
        perform(TelegramAPI.sendMessageRequest(token: token, chatId: chatId, text: text)) { data, status, error in
            completion(error ?? TelegramAPI.failure(from: data, status: status))
        }
    }

    static func detectChats(token: String, completion: @escaping @Sendable (Result<[TelegramChat], TelegramError>) -> Void) {
        perform(TelegramAPI.updatesRequest(token: token)) { data, status, error in
            if let message = error ?? TelegramAPI.failure(from: data, status: status) {
                completion(.failure(TelegramError(message: message)))
            } else {
                completion(.success(TelegramAPI.chats(fromUpdates: data)))
            }
        }
    }

    static var idleSeconds: TimeInterval {
        CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
    }

    private static func perform(_ request: URLRequest, completion: @escaping @Sendable (Data, Int, String?) -> Void) {
        URLSession.shared.dataTask(with: request) { data, response, error in
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            completion(data ?? Data(), status, error.map { _ in "No pude conectar con Telegram" })
        }.resume()
    }
}

struct TelegramError: Error {
    let message: String
}
