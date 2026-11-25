import Foundation
import PlayerEngine
import Testing

@testable import SystemKit

actor FakePosting: NotificationPosting {
    var status: NotificationAuthorization
    var grants: Bool
    private(set) var posts: [(title: String, attachment: URL?)] = []
    private(set) var requests = 0

    init(status: NotificationAuthorization = .authorized, grants: Bool = true) {
        self.status = status
        self.grants = grants
    }

    func authorizationStatus() -> NotificationAuthorization { status }

    func requestAuthorization() -> Bool {
        requests += 1
        status = grants ? .authorized : .denied
        return grants
    }

    func post(identifier: String, title: String, body: String, attachmentURL: URL?) {
        posts.append((title, attachmentURL))
    }
}

@MainActor
struct TrackNotifierTests {
    private func song(_ id: String, title: String) -> SongInfo {
        SongInfo(
            videoId: id, title: title, artist: "A", artworkURL: URL(string: "https://i.ytimg.com/\(id).jpg"),
            duration: 200, url: URL(string: "https://music.youtube.com/watch?v=\(id)")!)
    }

    private func notifier(
        _ posting: FakePosting, frontmost: Bool = false, artwork: @escaping @Sendable (URL) async -> URL? = { _ in nil }
    ) -> TrackNotifier {
        TrackNotifier(posting: posting, isEnabled: { true }, isFrontmost: { frontmost }, loadArtwork: artwork)
    }

    @Test func aLateArtworkForAnEarlierTrackNeverReplacesTheNewerOne() async {
        let posting = FakePosting()
        let gate = Gate()
        let started = Gate()
        let notifier = notifier(posting) { url in
            guard url.lastPathComponent == "a.jpg" else { return nil }
            await started.open()
            await gate.wait()
            return nil
        }
        notifier.handle(.songChanged(song("a", title: "A")))
        let earlier = notifier.currentPostTask
        await started.wait()
        notifier.handle(.songChanged(song("b", title: "B")))
        await gate.open()
        await earlier?.value
        await notifier.waitForPost()
        #expect(await posting.posts.map(\.title) == ["B"])
    }

    @Test func aStopCancelsAnInFlightPost() async {
        let posting = FakePosting()
        let gate = Gate()
        let started = Gate()
        let notifier = notifier(posting) { _ in
            await started.open()
            await gate.wait()
            return nil
        }
        notifier.handle(.songChanged(song("a", title: "A")))
        let inFlight = notifier.currentPostTask
        await started.wait()
        notifier.handle(.stopped)
        await gate.open()
        await inFlight?.value
        #expect(await posting.posts.isEmpty)
    }

    @Test func aFailedArtworkStillPosts() async {
        let posting = FakePosting()
        let notifier = notifier(posting)
        notifier.handle(.songChanged(song("a", title: "A")))
        await notifier.waitForPost()
        let posts = await posting.posts
        #expect(posts.count == 1)
        #expect(posts.first?.attachment == nil)
    }

    @Test func permissionIsRequestedOnceAtTheFirstAnnounce() async {
        let posting = FakePosting(status: .notDetermined)
        let notifier = notifier(posting)
        notifier.handle(.songChanged(song("a", title: "A")))
        await notifier.waitForPost()
        notifier.handle(.songChanged(song("b", title: "B")))
        await notifier.waitForPost()
        #expect(await posting.requests == 1)
        #expect(await posting.posts.count == 2)
    }

    @Test func aDeniedPermissionPostsNothing() async {
        let posting = FakePosting(status: .notDetermined, grants: false)
        let notifier = notifier(posting)
        notifier.handle(.songChanged(song("a", title: "A")))
        await notifier.waitForPost()
        #expect(await posting.posts.isEmpty)
    }

    @Test func aFrontmostAppPostsNothingAndDoesNotAsk() async {
        let posting = FakePosting(status: .notDetermined)
        let notifier = notifier(posting, frontmost: true)
        notifier.handle(.songChanged(song("a", title: "A")))
        await notifier.waitForPost()
        #expect(await posting.posts.isEmpty)
        #expect(await posting.requests == 0)
    }

    @Test func theRestoredTrackIsNotPosted() async {
        let posting = FakePosting()
        let notifier = notifier(posting)
        notifier.skipRestored(videoId: "a")
        notifier.handle(.songChanged(song("a", title: "A")))
        await notifier.waitForPost()
        #expect(await posting.posts.isEmpty)
    }

    @Test func aDisabledSettingPostsNothingAndDoesNotAsk() async {
        let posting = FakePosting(status: .notDetermined)
        let notifier = TrackNotifier(posting: posting, isEnabled: { false }, isFrontmost: { false }, loadArtwork: { _ in nil })
        notifier.handle(.songChanged(song("a", title: "A")))
        await notifier.waitForPost()
        #expect(await posting.posts.isEmpty)
        #expect(await posting.requests == 0)
    }

    @Test func anAdPostsNothingUntilItEnds() async {
        let posting = FakePosting()
        let notifier = notifier(posting)
        notifier.handle(.adChanged(true))
        notifier.handle(.songChanged(song("a", title: "A")))
        await notifier.waitForPost()
        #expect(await posting.posts.isEmpty)
        notifier.handle(.adChanged(false))
        await notifier.waitForPost()
        #expect(await posting.posts.map(\.title) == ["A"])
    }

    @Test func aLoadedArtworkIsAttached() async {
        let posting = FakePosting()
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).jpg")
        let notifier = notifier(posting) { _ in file }
        notifier.handle(.songChanged(song("a", title: "A")))
        await notifier.waitForPost()
        #expect(await posting.posts.first?.attachment == file)
    }
}

actor Gate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func open() {
        isOpen = true
        waiters.forEach { $0.resume() }
        waiters = []
    }
}
