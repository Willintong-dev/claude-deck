import Foundation
import Testing
@testable import DeckCore

struct ReadStateTests {
    let directory = TemporaryDirectory()

    private func session(_ id: String, _ status: SessionStatus, since: String?) -> SessionState {
        var state = SessionState(id: id, project: "proj")
        state.live.status = status
        state.live.since = since.map(date)
        return state
    }

    @Test func sessionsThatAnsweredBeforeTheFirstLaunchCountAsSeen() {
        let read = ReadState(baseline: date("2026-11-22T10:00:00.000Z"))
        #expect(read.attention(for: session("s1", .idle, since: "2026-11-22T09:00:00.000Z")) == .seen)
        #expect(read.attention(for: session("s2", .idle, since: "2026-11-22T10:05:00.000Z")) == .unread)
        #expect(read.attention(for: session("s3", .ended, since: "2026-11-22T10:05:00.000Z")) == .unread)
        #expect(read.attention(for: session("s4", .idle, since: nil)) == .seen)
    }

    @Test func waitingAndWorkingWinOverReadState() {
        var read = ReadState(baseline: date("2026-11-22T10:00:00.000Z"))
        let waiting = session("s1", .waiting, since: "2026-11-22T10:05:00.000Z")
        read.markSeen(waiting, at: date("2026-11-22T10:06:00.000Z"))
        #expect(read.attention(for: waiting) == .needsYou)
        #expect(read.attention(for: session("s2", .working, since: "2026-11-22T10:05:00.000Z")) == .working)
        #expect(read.attention(for: session("s3", .open, since: "2026-11-22T10:05:00.000Z")) == .seen)
    }

    @Test func lookingAtASessionClearsItUntilItAnswersAgain() {
        var read = ReadState(baseline: date("2026-11-22T10:00:00.000Z"))
        var current = session("s1", .idle, since: "2026-11-22T10:05:00.000Z")
        #expect(read.unreadCount(in: [current]) == 1)

        let firstLook = read.markSeen(current, at: date("2026-11-22T10:06:00.000Z"))
        #expect(firstLook)
        #expect(read.attention(for: current) == .seen)
        let secondLook = read.markSeen(current, at: date("2026-11-22T10:07:00.000Z"))
        #expect(!secondLook)

        current.live.status = .working
        current.live.since = date("2026-11-22T10:08:00.000Z")
        #expect(read.attention(for: current) == .working)

        current.live.status = .idle
        current.live.since = date("2026-11-22T10:09:00.000Z")
        #expect(read.attention(for: current) == .unread)
    }

    @Test func seenTimeNeverGoesBeforeTheAnswerItCovers() {
        var read = ReadState(baseline: date("2026-11-22T10:00:00.000Z"))
        let answered = session("s1", .idle, since: "2026-11-22T10:05:00.000Z")
        read.markSeen(answered, at: date("2026-11-22T10:04:59.000Z"))
        #expect(read.attention(for: answered) == .seen)
    }

    @Test func canBeMarkedUnreadAgainAndForgotten() {
        var read = ReadState(baseline: date("2026-11-22T10:00:00.000Z"))
        let answered = session("s1", .idle, since: "2026-11-22T09:00:00.000Z")
        read.markUnread("s1")
        #expect(read.attention(for: answered) == .unread)
        read.forget("s1")
        #expect(read.attention(for: answered) == .seen)
    }

    @Test func storeKeepsTheBaselineAndSeenTimes() throws {
        let store = ReadStateStore(file: directory.url.appendingPathComponent("deck/read.json"))
        let fresh = store.load(now: date("2026-11-22T10:00:00.000Z"))
        #expect(fresh.baseline == date("2026-11-22T10:00:00.000Z"))

        var read = fresh
        read.markSeen(session("s1", .idle, since: "2026-11-22T10:05:00.000Z"), at: date("2026-11-22T10:06:00.000Z"))
        try store.save(read)
        #expect(store.load(now: date("2030-01-01T00:00:00.000Z")) == read)

        write("no es json", to: store.file)
        #expect(store.load(now: date("2026-11-23T00:00:00.000Z")).baseline == date("2026-11-23T00:00:00.000Z"))
    }
}
