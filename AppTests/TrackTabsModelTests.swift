import Foundation
import InnerTube
import Testing

@MainActor
private final class TabsCallLog {
    var lyrics: [(id: String, signedIn: Bool)] = []
    var related: [String] = []
}

private struct Boom: Error {}

private let tabsCredentials = Credentials(cookies: [], authUserIndex: 0)

@MainActor
private func makeModel(
    log: TabsCallLog = TabsCallLog(), signedIn: Bool = false,
    lyrics: @escaping @Sendable (String) async throws -> Lyrics? = { _ in Lyrics(text: "la", source: nil) },
    related: @escaping @Sendable (String) async throws -> BrowsePage = { _ in page() }
) -> TrackTabsModel {
    TrackTabsModel(
        loader: TrackTabsLoader(
            lyrics: { id, credentials in
                await MainActor.run { log.lyrics.append((id: id, signedIn: credentials != nil)) }
                return try await lyrics(id)
            },
            related: { id, _ in
                await MainActor.run { log.related.append(id) }
                return try await related(id)
            }),
        credentials: { signedIn ? tabsCredentials : nil })
}

private func page(shelves: Int = 1, about: String? = nil) -> BrowsePage {
    BrowsePage(
        title: nil, chips: [],
        shelves: Page(items: (0..<shelves).map { _ in Shelf(title: "S", layout: .cards, items: []) }, continuation: nil),
        about: about.map { DescriptionShelf(title: "About", text: $0) })
}

@MainActor
struct TrackTabsModelTests {
    @Test func guestAndSignedInCredentialsArePassedThrough() async {
        let log = TabsCallLog()
        await makeModel(log: log).loadLyrics("a")
        await makeModel(log: log, signedIn: true).loadLyrics("a")
        #expect(log.lyrics.map(\.signedIn) == [false, true])
    }

    @Test func missingLyricsAreEmpty() async {
        let model = makeModel(lyrics: { _ in nil })
        await model.loadLyrics("a")
        guard case .empty = model.lyrics?.phase else { Issue.record("expected empty"); return }
    }

    @Test func aFailureCanBeRetried() async {
        let calls = Counter()
        let model = makeModel(lyrics: { _ in
            if await calls.next() == 1 { throw Boom() }
            return Lyrics(text: "la", source: "src")
        })
        await model.loadLyrics("a")
        guard case .failed = model.lyrics?.phase else { Issue.record("expected failed"); return }
        await model.loadLyrics("a")
        guard case .loaded(let lyrics) = model.lyrics?.phase else { Issue.record("expected loaded"); return }
        #expect(lyrics.source == "src")
    }

    @Test func aLateResponseForAnotherTrackIsDropped() async {
        let gate = Gate()
        let model = makeModel(lyrics: { id in
            if id == "A" { await gate.wait() }
            return Lyrics(text: id, source: nil)
        })
        let first = Task { await model.loadLyrics("A") }
        await Task.yield()
        await model.loadLyrics("B")
        await gate.open()
        await first.value
        #expect(model.lyrics?.id == "B")
        guard case .loaded(let lyrics) = model.lyrics?.phase else { Issue.record("expected loaded"); return }
        #expect(lyrics.text == "B")
    }

    @Test func aSettledTrackIsNotFetchedTwice() async {
        let log = TabsCallLog()
        let model = makeModel(log: log)
        await model.loadLyrics("a")
        await model.loadLyrics("a")
        await model.loadRelated("a")
        await model.loadRelated("a")
        #expect(log.lyrics.count == 1 && log.related.count == 1)
    }

    @Test func relatedWithNothingToShowIsEmpty() async {
        let model = makeModel(related: { _ in page(shelves: 0) })
        await model.loadRelated("a")
        guard case .empty = model.related?.phase else { Issue.record("expected empty"); return }
    }

    @Test func relatedWithOnlyAboutIsLoaded() async {
        let model = makeModel(related: { _ in page(shelves: 0, about: "bio") })
        await model.loadRelated("a")
        guard case .loaded = model.related?.phase else { Issue.record("expected loaded"); return }
    }

    @Test func resetDropsALateResponseAndBumpsTheGeneration() async {
        let gate = Gate()
        let model = makeModel(lyrics: { _ in
            await gate.wait()
            return Lyrics(text: "late", source: nil)
        })
        let task = Task { await model.loadLyrics("a") }
        await Task.yield()
        let before = model.generation
        model.reset()
        await gate.open()
        await task.value
        #expect(model.lyrics == nil && model.generation == before + 1)
    }
}

private actor Counter {
    private var value = 0
    func next() -> Int {
        value += 1
        return value
    }
}

private actor Gate {
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
