import Foundation
import InnerTube
import Testing

private final class Calls: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [String] = []

    var all: [String] { lock.withLock { recorded } }
    func record(_ call: String) { lock.withLock { recorded.append(call) } }
}

private struct Failure: Error {}

extension EntityLoader {
    static let stub = EntityLoader(
        album: { _, _ in throw Failure() }, artist: { _, _ in throw Failure() }, playlist: { _, _ in throw Failure() },
        moreTracks: { _, _ in throw Failure() }, sections: { _, _ in throw Failure() }, save: { _, _, _ in },
        subscribe: { _, _, _ in }, edit: { _, _, _ in [] })
}

private func song(_ id: String) -> Song { Song(videoId: id, title: id) }

private func playlistPage(
    _ ids: [String] = ["a", "b"], next: String? = nil, sections: String? = nil, owned: Bool = false, saved: Bool = false,
    play: WatchTarget? = nil
) -> PlaylistPage {
    PlaylistPage(
        header: PageHeader(title: "P", play: play, isSaved: saved), tracks: Page(items: ids.map(song), continuation: next),
        sectionsContinuation: sections, isOwned: owned)
}

private func albumPage(audio: String? = "OLAK1", saved: Bool = false) -> AlbumPage {
    AlbumPage(
        header: PageHeader(title: "A", play: WatchTarget(playlistId: "OLAK1"), isSaved: saved), type: "Album", year: "1997",
        audioPlaylistId: audio, tracks: [], shelves: [])
}

private func artistPage(subscribed: Bool? = false, channel: String? = "UCchan") -> ArtistPage {
    ArtistPage(
        name: "N", thumbnailURL: nil, subscriberCountText: nil, isSubscribed: subscribed, channelId: channel,
        shuffle: WatchTarget(playlistId: "RDshuffle"), radio: nil, shelves: [], description: nil, viewCountText: nil)
}

private func ownPage(_ ids: [String], privacy: PlaylistPrivacy? = .private) -> PlaylistPage {
    PlaylistPage(
        header: PageHeader(title: "Mine", description: "d"),
        tracks: Page(items: ids.map { Song(videoId: $0, title: $0, playlistSetVideoId: "s" + $0) }, continuation: nil),
        sectionsContinuation: nil, isOwned: true, privacy: privacy)
}

@MainActor
private func makeModel(
    _ kind: EntityModel.Kind = .playlist(browseId: "VLPL1"), loader: EntityLoader, signedIn: Bool = true,
    toasts: ToastCenter = ToastCenter(), onLibraryChange: @escaping @MainActor (EntityModel.LibraryChange) -> Void = { _ in }
) -> EntityModel {
    EntityModel(
        kind: kind, loader: loader, credentials: { signedIn ? Credentials(cookies: [], authUserIndex: 0) : nil }, toasts: toasts,
        onLibraryChange: onLibraryChange)
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
private func content(_ model: EntityModel) -> EntityModel.Content? {
    if case .loaded(let content) = model.state { content } else { nil }
}

@MainActor
private func trackIds(_ model: EntityModel) -> [String] { content(model)?.tracks.map(\.videoId) ?? [] }

@MainActor
struct EntityModelTests {
    @Test func albumArtistAndPlaylistMapTheirPages() async {
        var loader = EntityLoader.stub
        loader.album = { _, _ in albumPage(saved: true) }
        loader.artist = { _, _ in artistPage(subscribed: true) }
        loader.playlist = { _, _ in playlistPage(next: "t1") }
        let album = makeModel(.album(BrowseTarget(browseId: "MPREb1")), loader: loader)
        await album.load()
        #expect(content(album)?.isSaved == true)
        let artist = makeModel(.artist(browseId: "UC1"), loader: loader)
        await artist.load()
        #expect(content(artist)?.isSubscribed == true)
        let playlist = makeModel(loader: loader)
        await playlist.load()
        #expect(trackIds(playlist) == ["a", "b"])
        #expect(content(playlist)?.paging == .idle)
    }

    @Test func unavailableAndFailedPagesAreDistinctAndRetryReloads() async {
        let calls = Calls()
        var loader = EntityLoader.stub
        loader.playlist = { id, _ in
            calls.record(id)
            throw calls.all.count == 1 ? InnerTubeError.notAvailable : Failure()
        }
        let gone = makeModel(loader: loader)
        await gone.load()
        guard case .notAvailable = gone.state else {
            Issue.record("expected notAvailable")
            return
        }
        loader.playlist = { id, _ in
            calls.record(id)
            if calls.all.count == 2 { throw Failure() }
            return playlistPage()
        }
        let model = makeModel(loader: loader)
        await model.load()
        guard case .failed = model.state else {
            Issue.record("expected failed")
            return
        }
        model.retry()
        await model.load()
        #expect(trackIds(model) == ["a", "b"])
    }

    @Test func notReadyMakesNoRequest() async {
        let calls = Calls()
        var loader = EntityLoader.stub
        loader.playlist = { id, _ in
            calls.record(id)
            return playlistPage()
        }
        let model = makeModel(loader: loader)
        model.isReady = false
        await model.load()
        #expect(calls.all.isEmpty)
        model.isReady = true
        await model.load()
        #expect(calls.all == ["VLPL1"])
    }

    @Test func pagingAppendsAndStopsOnARepeatedPage() async {
        var loader = EntityLoader.stub
        loader.playlist = { _, _ in playlistPage(["a", "b"], next: "t1") }
        loader.moreTracks = { token, _ in token == "t1" ? Page(items: [song("c")], continuation: "t2") : Page(items: [song("c")], continuation: "t3") }
        let model = makeModel(loader: loader)
        await model.load()
        model.loadMore()
        #expect(await waitUntil { content(model)?.paging == .idle && trackIds(model).count == 3 })
        model.loadMore()
        #expect(await waitUntil { content(model)?.paging == .done })
        #expect(trackIds(model) == ["a", "b", "c"])
    }

    @Test func aBurstOfLoadMoreSendsOneRequest() async {
        let calls = Calls()
        var loader = EntityLoader.stub
        loader.playlist = { _, _ in playlistPage(["a"], next: "t1") }
        loader.moreTracks = { _, _ in
            calls.record("more")
            try? await Task.sleep(for: .milliseconds(50))
            return Page(items: [song("b")], continuation: nil)
        }
        let model = makeModel(loader: loader)
        await model.load()
        for _ in 0..<10 { model.loadMore() }
        #expect(await waitUntil { content(model)?.paging == .done })
        #expect(calls.all == ["more"])
    }

    @Test func guestPageOneRepeatEndsPaging() async {
        var loader = EntityLoader.stub
        loader.playlist = { _, _ in playlistPage(["a", "b"], next: "t1") }
        loader.moreTracks = { _, _ in Page(items: [song("a"), song("b")], continuation: "t2") }
        let model = makeModel(loader: loader)
        await model.load()
        model.loadMore()
        #expect(await waitUntil { content(model)?.paging == .done })
        #expect(trackIds(model) == ["a", "b"])
    }

    @Test func aFailedPageKeepsTheRowsAndRetryAsksForTheSameToken() async {
        let calls = Calls()
        var loader = EntityLoader.stub
        loader.playlist = { _, _ in playlistPage(["a"], next: "t1") }
        loader.moreTracks = { token, _ in
            calls.record(token)
            if calls.all.count == 1 { throw Failure() }
            return Page(items: [song("b")], continuation: nil)
        }
        let model = makeModel(loader: loader)
        await model.load()
        model.loadMore()
        #expect(await waitUntil { content(model)?.paging == .failed })
        #expect(trackIds(model) == ["a"])
        model.retryMore()
        #expect(await waitUntil { content(model)?.paging == .done })
        #expect(calls.all == ["t1", "t1"])
        #expect(trackIds(model) == ["a", "b"])
    }

    @Test func sectionsLoadOnlyAfterTheLastPage() async {
        let calls = Calls()
        var loader = EntityLoader.stub
        loader.playlist = { _, _ in playlistPage(["a"], next: "t1", sections: "s1") }
        loader.moreTracks = { _, _ in Page(items: [], continuation: nil) }
        loader.sections = { token, _ in
            calls.record(token)
            return Page(items: [Shelf(title: "Related", layout: .cards, items: [])], continuation: nil)
        }
        let model = makeModel(loader: loader)
        await model.load()
        model.loadSections()
        #expect(calls.all.isEmpty)
        model.loadMore()
        #expect(await waitUntil { content(model)?.paging == .done })
        model.loadSections()
        model.loadSections()
        #expect(await waitUntil { content(model)?.sections.count == 1 })
        #expect(calls.all == ["s1"])
    }

    @Test func savingSendsTheBareIdOrTheAudioPlaylistAndRevertsOnFailure() async {
        let calls = Calls()
        var loader = EntityLoader.stub
        loader.playlist = { _, _ in playlistPage() }
        loader.album = { _, _ in albumPage() }
        loader.save = { id, saved, _ in
            calls.record("\(id) \(saved)")
            if id == "PL1" { throw Failure() }
        }
        let toasts = ToastCenter()
        let album = makeModel(.album(BrowseTarget(browseId: "MPREb1")), loader: loader, toasts: toasts)
        await album.load()
        album.toggleSaved()
        #expect(content(album)?.isSaved == true)
        let playlist = makeModel(loader: loader, toasts: toasts)
        await playlist.load()
        playlist.toggleSaved()
        #expect(content(playlist)?.isSaved == true)
        #expect(await waitUntil { content(playlist)?.isSaved == false })
        #expect(toasts.message != nil)
        #expect(Set(calls.all) == ["OLAK1 true", "PL1 true"])
        #expect(content(album)?.isSaved == true)
    }

    @Test func guestMutationsMakeNoRequestAndLeaveStateUntouched() async {
        let calls = Calls()
        var loader = EntityLoader.stub
        loader.playlist = { _, _ in playlistPage() }
        loader.save = { _, _, _ in calls.record("save") }
        loader.edit = { _, _, _ in calls.record("add"); return [] }
        let model = makeModel(loader: loader, signedIn: false)
        await model.load()
        model.toggleSaved()
        model.add(song("z"))
        #expect(content(model)?.isSaved == false)
        #expect(await waitUntil { !calls.all.isEmpty } == false)
    }

    @Test func theLastSaveIntentWinsOverAnOlderFailure() async {
        let calls = Calls()
        var loader = EntityLoader.stub
        loader.playlist = { _, _ in playlistPage() }
        loader.save = { _, _, _ in
            calls.record("save")
            if calls.all.count == 1 {
                try await Task.sleep(for: .milliseconds(50))
                throw Failure()
            }
        }
        let toasts = ToastCenter()
        let model = makeModel(loader: loader, toasts: toasts)
        await model.load()
        model.toggleSaved()
        model.toggleSaved()
        model.toggleSaved()
        try? await Task.sleep(for: .milliseconds(150))
        #expect(content(model)?.isSaved == true)
        #expect(toasts.message == nil)
    }

    @Test func subscribingUsesTheChannelIdAndRevertsOnFailure() async {
        let calls = Calls()
        var loader = EntityLoader.stub
        loader.artist = { _, _ in artistPage() }
        loader.subscribe = { id, subscribed, _ in
            calls.record("\(id) \(subscribed)")
            if calls.all.count == 2 { throw Failure() }
        }
        let toasts = ToastCenter()
        let model = makeModel(.artist(browseId: "UCpage"), loader: loader, toasts: toasts)
        await model.load()
        model.toggleSubscribed()
        #expect(content(model)?.isSubscribed == true)
        model.toggleSubscribed()
        #expect(await waitUntil { calls.all.count == 2 && toasts.message != nil })
        #expect(calls.all == ["UCchan true", "UCchan false"])
        #expect(content(model)?.isSubscribed == true)
    }

    @Test func addingASuggestionRemovesItAndToasts() async {
        let calls = Calls()
        var loader = EntityLoader.stub
        loader.playlist = { _, _ in playlistPage(["a"], sections: "s1", owned: true) }
        loader.sections = { _, _ in
            Page(items: [Shelf(title: "Suggestions", layout: .list, items: [.song(song("x")), .song(song("y"))])], continuation: nil)
        }
        loader.edit = { id, edits, _ in
            guard case .add(let videoId) = edits[0] else { return [] }
            calls.record("\(id) \(videoId)")
            if videoId == "y" { throw Failure() }
            return []
        }
        let toasts = ToastCenter()
        let model = makeModel(loader: loader, toasts: toasts)
        await model.load()
        model.loadSections()
        #expect(await waitUntil { content(model)?.sections.count == 1 })
        model.add(song("y"))
        #expect(await waitUntil { calls.all.count == 1 && toasts.message != nil })
        #expect(content(model)?.sections[0].items.count == 2)
        model.add(song("x"))
        #expect(await waitUntil { content(model)?.sections[0].items.count == 1 })
        #expect(calls.all == ["VLPL1 y", "VLPL1 x"])
        #expect(trackIds(model) == ["a"])
    }

    @Test func cancelInFlightDropsALateResponse() async {
        var loader = EntityLoader.stub
        loader.playlist = { _, _ in
            try await Task.sleep(for: .milliseconds(50))
            return playlistPage()
        }
        let model = makeModel(loader: loader)
        let task = Task { await model.load() }
        try? await Task.sleep(for: .milliseconds(10))
        model.cancelInFlight()
        await task.value
        guard case .loading = model.state else {
            Issue.record("a late response must be dropped")
            return
        }
    }

    @Test func shareURLsFollowThePageKind() async {
        var loader = EntityLoader.stub
        loader.album = { _, _ in albumPage() }
        loader.artist = { _, _ in artistPage() }
        loader.playlist = { _, _ in playlistPage() }
        let album = makeModel(.album(BrowseTarget(browseId: "MPREb1")), loader: loader)
        await album.load()
        #expect(album.shareURL?.absoluteString == "https://music.youtube.com/playlist?list=OLAK1")
        let artist = makeModel(.artist(browseId: "UC1"), loader: loader)
        await artist.load()
        #expect(artist.shareURL?.absoluteString == "https://music.youtube.com/channel/UC1")
        let playlist = makeModel(loader: loader)
        await playlist.load()
        #expect(playlist.shareURL?.absoluteString == "https://music.youtube.com/playlist?list=PL1")
        let liked = makeModel(.playlist(browseId: "VLLM"), loader: loader)
        await liked.load()
        #expect(liked.shareURL == nil)
        loader.album = { _, _ in albumPage(audio: nil) }
        let bare = makeModel(.album(BrowseTarget(browseId: "MPREb2")), loader: loader)
        await bare.load()
        #expect(bare.shareURL == nil)
    }

    @Test func saveIsHiddenForLikedMusicAndOwnPlaylists() async {
        var loader = EntityLoader.stub
        loader.playlist = { id, _ in playlistPage(owned: id == "VLOWN") }
        let liked = makeModel(.playlist(browseId: "VLLM"), loader: loader)
        await liked.load()
        let own = makeModel(.playlist(browseId: "VLOWN"), loader: loader)
        await own.load()
        let other = makeModel(loader: loader)
        await other.load()
        #expect(!liked.canSave)
        #expect(!own.canSave && own.canAddSuggestions)
        #expect(other.canSave && !other.canAddSuggestions)
    }

    @Test func aPlaylistWithoutAPlayButtonPlaysItsOwnId() async {
        var loader = EntityLoader.stub
        loader.playlist = { _, _ in playlistPage() }
        let model = makeModel(.playlist(browseId: "VLOLAK1"), loader: loader)
        await model.load()
        #expect(model.playTarget == WatchTarget(playlistId: "OLAK1"))
        #expect(model.shuffleTarget == WatchTarget(playlistId: "OLAK1"))
    }

    @Test func storeCachesResetsAndPropagatesReadiness() {
        let store = BrowseStore(
            loader: BrowseLoader(page: { _, _ in throw Failure() }, more: { _, _ in throw Failure() }),
            searchLoader: .stub, entityLoader: .stub, libraryLoader: .stub, toasts: ToastCenter(), credentials: { nil })
        let route = Route.album(browseId: "MPREb1")
        let model = store.entityModel(for: route)
        #expect(model != nil)
        #expect(store.entityModel(for: route) === model)
        #expect(store.entityModel(for: .history) == nil)
        store.setReady(false)
        #expect(model?.isReady == false)
        store.reset()
        #expect(store.entityModel(for: route) !== model)
    }

    @Test func resetBumpsTheStoreGeneration() {
        let store = BrowseStore(
            loader: BrowseLoader(page: { _, _ in throw Failure() }, more: { _, _ in throw Failure() }),
            searchLoader: .stub, entityLoader: .stub, libraryLoader: .stub, toasts: ToastCenter(), credentials: { nil })
        let before = store.generation
        store.reset()
        #expect(store.generation == before + 1)
    }

    @Test func aRetiredModelIgnoresLateResultsAndMutations() async {
        let calls = Calls()
        var loader = EntityLoader.stub
        loader.playlist = { _, _ in
            try await Task.sleep(for: .milliseconds(50))
            return playlistPage()
        }
        loader.save = { id, _, _ in calls.record(id) }
        let model = makeModel(loader: loader)
        let task = Task { await model.load() }
        try? await Task.sleep(for: .milliseconds(10))
        model.cancelInFlight()
        await task.value
        await model.load()
        model.toggleSaved()
        model.add(song("z"))
        try? await Task.sleep(for: .milliseconds(80))
        guard case .loading = model.state else {
            Issue.record("a retired model must not load")
            return
        }
        #expect(calls.all.isEmpty)
    }

    @Test func savingAPlaylistReportsTheChangeOnlyAfterSuccess() async {
        let changes = Changes()
        var loader = EntityLoader.stub
        loader.playlist = { _, _ in playlistPage() }
        let model = makeModel(loader: loader, onLibraryChange: { changes.record($0) })
        await model.load()
        model.toggleSaved()
        #expect(await waitUntil { changes.all.count == 1 })
        #expect(changes.all == [.playlist(Playlist(browseId: "VLPL1", title: "P"), saved: true)])
    }

    @Test func savingAnAlbumReportsAnAlbumChange() async {
        let changes = Changes()
        var loader = EntityLoader.stub
        loader.album = { _, _ in albumPage() }
        let model = makeModel(.album(BrowseTarget(browseId: "MPREb1")), loader: loader, onLibraryChange: { changes.record($0) })
        await model.load()
        model.toggleSaved()
        #expect(await waitUntil { changes.all == [.album] })
    }

    @Test func aFailedSaveReportsNothing() async {
        let changes = Changes()
        let toasts = ToastCenter()
        var loader = EntityLoader.stub
        loader.playlist = { _, _ in playlistPage() }
        loader.save = { _, _, _ in throw Failure() }
        let model = makeModel(loader: loader, toasts: toasts, onLibraryChange: { changes.record($0) })
        await model.load()
        model.toggleSaved()
        #expect(await waitUntil { toasts.message != nil })
        #expect(changes.all.isEmpty)
    }

    @Test func aDeletedPlaylistIsNotAvailableAndCannotBeEdited() async {
        let calls = Calls()
        var loader = EntityLoader.stub
        loader.playlist = { _, _ in playlistPage() }
        loader.save = { id, _, _ in calls.record(id) }
        let model = makeModel(loader: loader)
        await model.load()
        model.playlistRemoved(deleted: true)
        guard case .notAvailable = model.state else { Issue.record("expected notAvailable"); return }
        model.toggleSaved()
        model.add(song("z"))
        try? await Task.sleep(for: .milliseconds(30))
        #expect(calls.all.isEmpty)
    }

    @Test func aRemovedPlaylistShowsAsUnsaved() async {
        var loader = EntityLoader.stub
        loader.playlist = { _, _ in playlistPage(saved: true) }
        let model = makeModel(loader: loader)
        await model.load()
        model.playlistRemoved(deleted: false)
        guard case .loaded(let content) = model.state else { Issue.record("expected loaded"); return }
        #expect(!content.isSaved)
    }

    @Test func storeReplacesAndCancelsTheLibraryModelsOnReset() {
        let store = BrowseStore(
            loader: BrowseLoader(page: { _, _ in throw Failure() }, more: { _, _ in throw Failure() }),
            searchLoader: .stub, entityLoader: .stub, libraryLoader: .stub, toasts: ToastCenter(), credentials: { nil })
        let library = store.library
        let history = store.history
        store.reset()
        #expect(store.library !== library)
        #expect(store.history !== history)
    }

    @Test func storeForwardsAPlaylistSaveAndRemovalToTheSidebarChannel() async {
        var entityLoader = EntityLoader.stub
        entityLoader.playlist = { _, _ in playlistPage() }
        let store = BrowseStore(
            loader: BrowseLoader(page: { _, _ in throw Failure() }, more: { _, _ in throw Failure() }),
            searchLoader: .stub, entityLoader: entityLoader, libraryLoader: .stub, toasts: ToastCenter(),
            credentials: { Credentials(cookies: [], authUserIndex: 0) })
        let route = Route.playlist(browseId: "VLPL1")
        let model = store.entityModel(for: route)
        await model?.load()
        model?.toggleSaved()
        #expect(await waitUntil { store.lastPlaylistChange?.saved == true })
        let first = store.lastPlaylistChange?.id
        model?.toggleSaved()
        #expect(await waitUntil { store.lastPlaylistChange?.id != first })
        store.playlistRemoved("VLPL1", deleted: true)
        guard case .notAvailable = model?.state else { Issue.record("expected notAvailable"); return }
    }
}

@MainActor
private final class Changes {
    private(set) var all: [EntityModel.LibraryChange] = []
    func record(_ change: EntityModel.LibraryChange) { all.append(change) }

    @Test func editDetailsSendsOnlyChangedFieldsAndUndoSendsThePreviousValues() async {
        let calls = Calls()
        var loader = EntityLoader.stub
        loader.playlist = { _, _ in ownPage(["a"]) }
        loader.edit = { _, edits, _ in calls.record("\(edits)"); return [] }
        let toasts = ToastCenter()
        let model = makeModel(loader: loader, toasts: toasts)
        await model.load()
        var draft = model.editDraft ?? NewPlaylistDraft()
        draft.title = "Renamed"
        draft.privacy = .public
        #expect(await model.editDetails(draft))
        #expect(calls.all == ["[InnerTube.PlaylistEdit.rename(\"Renamed\"), InnerTube.PlaylistEdit.setPrivacy(InnerTube.PlaylistPrivacy.public)]"])
        toasts.undo()
        #expect(await waitUntil { calls.all.count == 2 })
        #expect(calls.all[1].contains("rename(\"Mine\")") && calls.all[1].contains("private"))
    }

    @Test func removeRowsIsOptimisticAndRollsBackOnFailure() async {
        var loader = EntityLoader.stub
        loader.playlist = { _, _ in ownPage(["a", "b", "c"]) }
        loader.edit = { _, _, _ in throw Failure() }
        let toasts = ToastCenter()
        let model = makeModel(loader: loader, toasts: toasts)
        await model.load()
        model.removeRows(["sb"])
        #expect(trackIds(model) == ["a", "c"])
        #expect(await waitUntil { trackIds(model) == ["a", "b", "c"] && toasts.message != nil })
    }

    @Test func removeUndoReAddsThenMovesEachRowBeforeItsSurvivingSuccessor() async {
        let calls = Calls()
        var loader = EntityLoader.stub
        loader.playlist = { _, _ in ownPage(["a", "b", "c", "d"]) }
        loader.edit = { _, edits, _ in
            calls.record("\(edits)")
            return edits.compactMap { if case .add(let id) = $0 { AddedPlaylistRow(videoId: id, setVideoId: "n" + id) } else { nil } }
        }
        let toasts = ToastCenter()
        let model = makeModel(loader: loader, toasts: toasts)
        await model.load()
        model.removeRows(["sb", "sc"])
        #expect(await waitUntil { toasts.toast?.undo != nil })
        toasts.undo()
        #expect(await waitUntil { calls.all.count == 3 })
        #expect(calls.all[2].contains("move(setVideoId: \"nb\", before: Optional(\"sd\"))"))
        #expect(calls.all[2].contains("move(setVideoId: \"nc\", before: Optional(\"sd\"))"))
        #expect(calls.all[2].range(of: "nb")!.lowerBound < calls.all[2].range(of: "nc")!.lowerBound)
    }

    @Test func moveRowReordersOptimisticallyAndRollsBack() async {
        var loader = EntityLoader.stub
        loader.playlist = { _, _ in ownPage(["a", "b", "c"]) }
        loader.edit = { _, _, _ in throw Failure() }
        let model = makeModel(loader: loader)
        await model.load()
        model.moveRow("sc", before: "sa")
        #expect(trackIds(model) == ["c", "a", "b"])
        #expect(await waitUntil { trackIds(model) == ["a", "b", "c"] })
    }

    @Test func guestOrNonOwnerCannotEdit() async {
        var loader = EntityLoader.stub
        loader.playlist = { _, _ in playlistPage() }
        let model = makeModel(loader: loader)
        await model.load()
        #expect(!model.canEdit)
        model.removeRows(["a"])
        #expect(trackIds(model) == ["a", "b"])
    }

    @Test func allTrackIdsPagesToTheEnd() async {
        var loader = EntityLoader.stub
        loader.playlist = { _, _ in playlistPage(["a", "b"], next: "t1") }
        loader.moreTracks = { _, _ in Page(items: [song("c"), song("a")], continuation: nil) }
        let model = makeModel(loader: loader)
        await model.load()
        #expect(await model.allTrackIds() == ["a", "b", "c"])
    }

    @Test func allTrackIdsIsEmptyWhenRetiredWhilePaging() async {
        var loader = EntityLoader.stub
        loader.playlist = { _, _ in playlistPage(["a", "b"], next: "t1") }
        var model: EntityModel!
        loader.moreTracks = { _, _ in
            await MainActor.run { model.cancelInFlight() }
            return Page(items: [song("c")], continuation: nil)
        }
        model = makeModel(loader: loader)
        await model.load()
        #expect(await model.allTrackIds().isEmpty)
    }
}
