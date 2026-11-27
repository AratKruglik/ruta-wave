import Foundation
import InnerTube
import Testing

private final class Recorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recordedInputs: [String] = []
    private var recordedTokens: [String] = []

    var inputs: [String] { lock.withLock { recordedInputs } }
    var tokens: [String] { lock.withLock { recordedTokens } }
    func record(input: String) { lock.withLock { recordedInputs.append(input) } }
    func record(token: String) { lock.withLock { recordedTokens.append(token) } }
}

private struct Failure: Error {}

private let signedIn = Credentials(cookies: [])

private func entry(_ query: String) -> SearchHistoryEntry { SearchHistoryEntry(query: query, feedbackToken: "t-\(query)") }

@MainActor
private func makeModel(
    _ recorder: Recorder, credentials: Credentials? = signedIn, toasts: ToastCenter = ToastCenter(),
    suggestions: @escaping @Sendable (String) async throws -> SearchSuggestions = { _ in SearchSuggestions() },
    feedback: @escaping @Sendable (String) async throws -> Void = { _ in }
) -> SearchFieldModel {
    SearchFieldModel(
        loader: SearchLoader(
            suggestions: { input, _ in
                recorder.record(input: input)
                return try await suggestions(input)
            },
            search: { _, _, _ in throw Failure() }, more: { _, _ in throw Failure() },
            feedback: { token, _ in
                recorder.record(token: token)
                try await feedback(token)
            },
            subscribe: { _, _, _ in }),
        credentials: { credentials }, toasts: toasts, sleep: { _ in })
}

@MainActor
private func waitUntil(_ condition: () -> Bool) async -> Bool {
    let deadline = ContinuousClock.now + .seconds(3)
    while ContinuousClock.now < deadline {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(10))
    }
    return condition()
}

private func rich(_ history: [String] = [], queries: [String] = [], items: [MusicItem] = []) -> SearchSuggestions {
    SearchSuggestions(queries: queries, items: items, history: history.map(entry))
}

@MainActor
struct SearchFieldModelTests {
    @Test func aSupersededKeystrokeNeverRequestsOrShows() async {
        let recorder = Recorder()
        let model = makeModel(recorder, suggestions: { input in
            if input == "ra" { try await Task.sleep(for: .milliseconds(50)) }
            return rich(queries: [input])
        })
        model.edit("ra")
        let first = Task { await model.suggest() }
        try? await Task.sleep(for: .milliseconds(10))
        model.edit("rad")
        first.cancel()
        await model.suggest()
        await first.value
        #expect(model.rows == [.query("rad")])
        #expect(recorder.inputs.last == "rad")
    }

    @Test func aGuestWithEmptyTextSendsNothingAndShowsNoDropdown() async {
        let recorder = Recorder()
        let model = makeModel(recorder, credentials: nil, suggestions: { _ in rich(["x"]) })
        model.open()
        await model.suggest()
        #expect(recorder.inputs.isEmpty)
        #expect(model.rows.isEmpty)
        #expect(!model.isDropdownVisible)
    }

    @Test func signedInEmptyTextShowsAtMostSevenHistoryRowsFirst() async {
        let model = makeModel(Recorder(), suggestions: { _ in
            rich((1...9).map { "h\($0)" }, queries: ["q"])
        })
        model.open()
        await model.suggest()
        #expect(model.rows.count == SearchFieldModel.historyLimit + 1)
        #expect(model.rows.first == .history(entry("h1")))
        #expect(model.rows.last == .query("q"))
    }

    @Test func suggestionErrorsAndEmptyResponsesCloseSilently() async {
        let toasts = ToastCenter()
        let failing = makeModel(Recorder(), toasts: toasts, suggestions: { _ in throw Failure() })
        failing.edit("a")
        await failing.suggest()
        #expect(!failing.isDropdownVisible)
        let empty = makeModel(Recorder(), toasts: toasts)
        empty.edit("a")
        await empty.suggest()
        #expect(!empty.isDropdownVisible)
        #expect(toasts.message == nil)
    }

    @Test func highlightWalksHistoryThenQueriesThenItemsAndWraps() async {
        let model = makeModel(Recorder(), suggestions: { _ in
            rich(["h"], queries: ["q"], items: [.artist(Artist(browseId: "UC1", name: "A"))])
        })
        model.edit("a")
        await model.suggest()
        model.moveHighlight(1)
        #expect(model.highlighted == 0)
        model.moveHighlight(1)
        model.moveHighlight(1)
        #expect(model.highlighted == 2)
        model.moveHighlight(1)
        #expect(model.highlighted == 0)
        model.moveHighlight(-1)
        #expect(model.highlighted == 2)
    }

    @Test func submitRunsTheHighlightOrTheTrimmedQuery() async {
        let model = makeModel(Recorder(), suggestions: { _ in rich(queries: ["radiohead"]) })
        model.edit("  rad ")
        await model.suggest()
        model.moveHighlight(1)
        #expect(model.submit() == .search("radiohead"))
        model.edit("radiohead")
        #expect(!model.isOpen)
        model.edit("  rad ")
        #expect(model.submit() == .search("rad"))
        model.edit("   ")
        #expect(model.submit() == nil)
    }

    @Test func entityRowsMapToOpenRadioOrPlay() {
        let model = makeModel(Recorder())
        let artist = MusicItem.artist(Artist(browseId: "UC1", name: "A"))
        let album = MusicItem.album(Album(browseId: "MPREb1", title: "B"))
        let song = Song(videoId: "v", title: "S")
        let mix = MusicItem.playlist(Playlist(browseId: "RDCLAK1", title: "Mix"))
        #expect(model.activate(.item(artist)) == .open(.artist(channelId: "UC1")))
        #expect(model.activate(.item(album)) == .open(.album(browseId: "MPREb1")))
        #expect(model.activate(.item(.song(song))) == .radio(song))
        #expect(model.activate(.item(mix)) == .play(mix))
    }

    @Test func escapeClosesThenClearsThenGivesUp() async {
        let model = makeModel(Recorder(), suggestions: { _ in rich(queries: ["q"]) })
        model.edit("abc")
        await model.suggest()
        #expect(model.escape())
        #expect(!model.isDropdownVisible)
        #expect(model.text == "abc")
        #expect(model.escape())
        #expect(model.text.isEmpty)
        #expect(!model.escape())
    }

    @Test func removalSendsOneTokenAndStaysOptimistic() async {
        let recorder = Recorder()
        let model = makeModel(recorder, suggestions: { _ in rich(["a", "b"]) }, feedback: { _ in
            try await Task.sleep(for: .milliseconds(50))
        })
        model.open()
        await model.suggest()
        model.remove(entry("a"))
        model.remove(entry("a"))
        #expect(model.rows == [.history(entry("b"))])
        await model.suggest()
        #expect(model.rows == [.history(entry("b"))])
        try? await Task.sleep(for: .milliseconds(120))
        #expect(recorder.tokens == ["t-a"])
        #expect(model.rows == [.history(entry("b"))])
    }

    @Test func failedRemovalRestoresTheRowInPlaceWithAToast() async {
        let toasts = ToastCenter()
        let model = makeModel(Recorder(), toasts: toasts, suggestions: { _ in rich(["a", "b"]) }, feedback: { _ in throw Failure() })
        model.open()
        await model.suggest()
        model.remove(entry("a"))
        #expect(await waitUntil { model.rows.count == 2 })
        #expect(model.rows.first == .history(entry("a")))
        #expect(toasts.message != nil)
    }

    @Test func aRefetchDuringAFailingRemovalDoesNotDuplicateTheRow() async {
        let model = makeModel(
            Recorder(), suggestions: { _ in rich(["a", "b"]) },
            feedback: { _ in
                try await Task.sleep(for: .milliseconds(50))
                throw Failure()
            })
        model.open()
        await model.suggest()
        model.remove(entry("a"))
        await model.suggest()
        #expect(model.rows == [.history(entry("b"))])
        #expect(await waitUntil { model.rows.count == 2 })
        #expect(model.rows == [.history(entry("a")), .history(entry("b"))])
    }

    @Test func resetMidFlightNeitherRestoresNorToasts() async {
        let toasts = ToastCenter()
        let recorder = Recorder()
        let model = makeModel(recorder, toasts: toasts, suggestions: { _ in rich(["a"]) }, feedback: { _ in
            try await Task.sleep(for: .milliseconds(50))
            throw Failure()
        })
        model.open()
        await model.suggest()
        model.remove(entry("a"))
        model.reset()
        #expect(await waitUntil { recorder.tokens == ["t-a"] })
        try? await Task.sleep(for: .milliseconds(120))
        #expect(model.rows.isEmpty)
        #expect(toasts.message == nil)
        #expect(model.text.isEmpty)
    }

    @Test func aLateResponseCannotReopenAClosedDropdown() async {
        let (started, startedSignal) = AsyncStream<Void>.makeStream()
        let model = makeModel(Recorder(), suggestions: { _ in
            startedSignal.yield()
            try await Task.sleep(for: .milliseconds(50))
            return rich(queries: ["q"])
        })
        model.edit("a")
        let task = Task { await model.suggest() }
        for await _ in started { break }
        model.close()
        await task.value
        #expect(!model.isDropdownVisible)
        #expect(model.rows.isEmpty)
    }

    @Test func focusOpensTheDropdownOnlyWithThePointerOverTheField() {
        let model = makeModel(Recorder())
        model.focusChanged(true)
        #expect(!model.isOpen)
        model.isPointerOverField = true
        model.focusChanged(true)
        #expect(model.isOpen)
    }

    @Test func movingTheHighlightOpensAClosedDropdown() {
        let model = makeModel(Recorder())
        model.moveHighlight(1)
        #expect(model.isOpen)
    }
}
