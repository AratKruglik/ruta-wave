import InnerTube
import Testing

private struct Failure: Error {}

private let credentials = Credentials(cookies: [], authUserIndex: 0)

private func entry(_ id: String, token: String? = "tok") -> HistoryEntry {
    HistoryEntry(song: Song(videoId: id, title: id), feedbackToken: token.map { "\($0)-\(id)" })
}

@MainActor
private func makeModel(_ loader: LibraryLoader, toasts: ToastCenter = ToastCenter()) -> HistoryModel {
    HistoryModel(loader: loader, credentials: { credentials }, toasts: toasts)
}

@MainActor
private func days(_ model: HistoryModel) -> [HistoryDay] {
    if case .loaded(let days) = model.state { days } else { [] }
}

@MainActor
private func waitUntil(_ condition: () -> Bool) async -> Bool {
    for _ in 0..<200 {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(10))
    }
    return condition()
}

@MainActor
struct HistoryModelTests {
    private func loaded(
        feedback: @escaping @Sendable (String, Credentials?) async throws -> Void = { _, _ in },
        toasts: ToastCenter = ToastCenter()
    ) async -> HistoryModel {
        var loader = LibraryLoader.stub
        loader.history = { _ in
            [HistoryDay(title: "Today", entries: [entry("a"), entry("b"), entry("c", token: nil)]),
             HistoryDay(title: "Yesterday", entries: [entry("d")]),
             HistoryDay(title: "Empty", entries: [])]
        }
        loader.feedback = feedback
        let model = makeModel(loader, toasts: toasts)
        await model.load()
        return model
    }

    @Test func daysWithoutEntriesAreDropped() async {
        let model = await loaded()
        #expect(days(model).map(\.title) == ["Today", "Yesterday"])
    }

    @Test func noDaysIsEmptyAndAFailureCanBeRetried() async {
        var loader = LibraryLoader.stub
        loader.history = { _ in [] }
        let model = makeModel(loader)
        await model.load()
        guard case .empty = model.state else { Issue.record("expected empty"); return }

        let calls = CallLog()
        loader.history = { _ in
            calls.record("history")
            if calls.all.count == 1 { throw Failure() }
            return [HistoryDay(title: "Today", entries: [entry("a")])]
        }
        let retried = makeModel(loader)
        await retried.load()
        guard case .failed = retried.state else { Issue.record("expected failed"); return }
        retried.retry()
        await retried.load()
        #expect(days(retried).count == 1)
    }

    @Test func removalIsOptimisticAndSendsTheToken() async {
        let sent = CallLog()
        let model = await loaded(feedback: { token, _ in sent.record(token) })
        model.remove(entry("a"))
        #expect(days(model)[0].entries.map(\.song.videoId) == ["b", "c"])
        #expect(await waitUntil { sent.all == ["tok-a"] })
    }

    @Test func removingTheLastRowOfADayDropsTheHeader() async {
        let model = await loaded()
        model.remove(entry("d"))
        #expect(days(model).map(\.title) == ["Today"])
    }

    @Test func removingEverythingShowsTheEmptyState() async {
        var loader = LibraryLoader.stub
        loader.history = { _ in [HistoryDay(title: "Today", entries: [entry("a")])] }
        let model = makeModel(loader)
        await model.load()
        model.remove(entry("a"))
        guard case .empty = model.state else { Issue.record("expected empty"); return }
    }

    @Test func aFailureRestoresTheRowInPlaceWithAToast() async {
        let toasts = ToastCenter()
        let model = await loaded(feedback: { _, _ in throw Failure() }, toasts: toasts)
        model.remove(entry("b"))
        #expect(await waitUntil { toasts.message != nil })
        #expect(days(model)[0].entries.map(\.song.videoId) == ["a", "b", "c"])
    }

    @Test func aFailureRestoresADroppedDayAtItsPosition() async {
        let toasts = ToastCenter()
        let model = await loaded(feedback: { _, _ in throw Failure() }, toasts: toasts)
        model.remove(entry("d"))
        #expect(await waitUntil { toasts.message != nil })
        #expect(days(model).map(\.title) == ["Today", "Yesterday"])
        #expect(days(model)[1].entries.map(\.song.videoId) == ["d"])
    }

    @Test func aRowWithoutATokenIsNotRemovable() async {
        let sent = CallLog()
        let model = await loaded(feedback: { token, _ in sent.record(token) })
        model.remove(entry("c", token: nil))
        #expect(days(model)[0].entries.count == 3)
        #expect(sent.all.isEmpty)
    }

    @Test func theSameRowIsNotSentTwiceWhilePending() async {
        let sent = CallLog()
        let model = await loaded(feedback: { token, _ in
            sent.record(token)
            try await Task.sleep(for: .milliseconds(30))
        })
        model.remove(entry("a"))
        model.remove(entry("a"))
        #expect(await waitUntil { sent.all.count == 1 })
        try? await Task.sleep(for: .milliseconds(50))
        #expect(sent.all.count == 1)
    }

    @Test func anIdentityChangeWhileAFailureIsPendingAppliesNothing() async {
        let toasts = ToastCenter()
        let model = await loaded(feedback: { _, _ in
            try await Task.sleep(for: .milliseconds(30))
            throw Failure()
        }, toasts: toasts)
        model.remove(entry("a"))
        model.cancelInFlight()
        try? await Task.sleep(for: .milliseconds(80))
        #expect(toasts.message == nil)
        #expect(days(model)[0].entries.map(\.song.videoId) == ["b", "c"])
        model.remove(entry("b"))
        #expect(days(model)[0].entries.count == 2)
    }

    @Test func aRetiredModelDoesNotLoad() async {
        var loader = LibraryLoader.stub
        loader.history = { _ in [HistoryDay(title: "Today", entries: [entry("a")])] }
        let model = makeModel(loader)
        model.cancelInFlight()
        await model.load()
        guard case .loading = model.state else { Issue.record("a retired model must not load"); return }
    }
}
