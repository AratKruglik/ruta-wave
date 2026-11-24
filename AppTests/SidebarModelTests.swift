import InnerTube
import Testing

private struct Failure: Error {}

private let signedIn = Credentials(cookies: [], authUserIndex: 0)

private func playlist(_ id: String, title: String = "T") -> Playlist { Playlist(browseId: id, title: title) }

private extension SidebarLoader {
    static let stub = SidebarLoader(
        playlists: { _ in [] }, create: { _, _ in "NEW" }, edit: { _, _, _ in [] }, delete: { _, _ in }, removeFromLibrary: { _, _ in },
        isOwned: { _, _ in false })
}

@MainActor
private func makeModel(_ loader: SidebarLoader, signedIn isSignedIn: Bool = true, toasts: ToastCenter = ToastCenter()) -> SidebarModel {
    SidebarModel(loader: loader, credentials: { isSignedIn ? signedIn : nil }, toasts: toasts)
}

@MainActor
private func ids(_ model: SidebarModel) -> [String] {
    if case .loaded(let playlists) = model.state { playlists.map(\.browseId) } else { [] }
}

@MainActor
struct SidebarModelTests {
    @Test func guestLoadsEmptyList() async {
        let model = makeModel(.stub, signedIn: false)
        await model.load()
        guard case .loaded(let playlists) = model.state else { Issue.record("expected loaded"); return }
        #expect(playlists.isEmpty)
    }

    @Test func pinsLikedMusicFirstWithoutDuplicating() {
        let other = playlist("VLother")
        let liked = Playlist(browseId: Route.likedMusicBrowseId, title: "Liked")
        #expect(SidebarModel.pinningLikedMusic([other, liked]) == [liked, other])
    }

    @Test func addsLikedMusicWhenMissing() {
        let other = playlist("VLother")
        let result = SidebarModel.pinningLikedMusic([other])
        #expect(result.count == 2)
        #expect(result[0].browseId == Route.likedMusicBrowseId)
        #expect(result[1] == other)
    }

    @Test func failureShowsFailedAndRefreshFailureKeepsTheList() async {
        var loader = SidebarLoader.stub
        loader.playlists = { _ in throw Failure() }
        let model = makeModel(loader)
        await model.load()
        guard case .failed = model.state else { Issue.record("expected failed"); return }

        let counter = CallLog()
        loader.playlists = { _ in
            counter.record("x")
            if counter.all.count > 1 { throw Failure() }
            return [playlist("VL1")]
        }
        let second = makeModel(loader)
        await second.load()
        await second.load()
        #expect(ids(second) == ["VLLM", "VL1"])
    }

    @Test func refreshKeepsTheLoadedListVisible() async {
        var loader = SidebarLoader.stub
        loader.playlists = { _ in
            try await Task.sleep(for: .milliseconds(40))
            return [playlist("VL1")]
        }
        let model = makeModel(loader)
        await model.load()
        let refresh = Task { await model.load() }
        try? await Task.sleep(for: .milliseconds(10))
        #expect(ids(model) == ["VLLM", "VL1"])
        await refresh.value
    }

    @Test func createInsertsUnderLikedMusicAndSurvivesALaggingList() async {
        var loader = SidebarLoader.stub
        loader.playlists = { _ in [playlist("VL1")] }
        loader.create = { _, _ in "NEW" }
        let model = makeModel(loader)
        await model.load()
        let result = await model.create(NewPlaylistDraft(title: "  Road trip  "))
        #expect(result == .created("VLNEW"))
        #expect(ids(model) == ["VLLM", "VLNEW", "VL1"])
        guard case .loaded(let list) = model.state else { return }
        #expect(list[1].title == "Road trip")
        await model.load()
        #expect(ids(model) == ["VLLM", "VLNEW", "VL1"])
        #expect(model.ownership(of: "VLNEW") == true)
    }

    @Test func pendingInsertIsDroppedOnceTheServerListHasIt() async {
        var loader = SidebarLoader.stub
        loader.playlists = { _ in [playlist("VLNEW", title: "Server name")] }
        let synced = makeModel(loader)
        await synced.load()
        _ = await synced.create(NewPlaylistDraft(title: "A"))
        await synced.load()
        guard case .loaded(let list) = synced.state else { return }
        #expect(list.map(\.browseId) == ["VLLM", "VLNEW"])
        #expect(list[1].title == "Server name")
    }

    @Test func networkErrorOnCreateMeansItMayExistAndIsNeverResent() async {
        let calls = CallLog()
        var loader = SidebarLoader.stub
        loader.create = { _, _ in
            calls.record("create")
            throw InnerTubeError.network(.timedOut)
        }
        let model = makeModel(loader)
        await model.load()
        #expect(await model.create(NewPlaylistDraft(title: "A")) == .mayExist)
        #expect(calls.all == ["create"])
        #expect(ids(model) == ["VLLM"])
    }

    @Test(arguments: [InnerTubeError.unexpectedResponse, .httpStatus(502)])
    func ambiguousServerErrorsOnCreateMeanItMayExist(error: InnerTubeError) async {
        var loader = SidebarLoader.stub
        loader.create = { _, _ in throw error }
        let model = makeModel(loader)
        await model.load()
        #expect(await model.create(NewPlaylistDraft(title: "A")) == .mayExist)
    }

    @Test func clientErrorOnCreateFails() async {
        var loader = SidebarLoader.stub
        loader.create = { _, _ in throw InnerTubeError.httpStatus(400) }
        let model = makeModel(loader)
        await model.load()
        #expect(await model.create(NewPlaylistDraft(title: "A")) == .failed)
    }

    @Test func otherCreateErrorsFail() async {
        var loader = SidebarLoader.stub
        loader.create = { _, _ in throw Failure() }
        let model = makeModel(loader)
        await model.load()
        #expect(await model.create(NewPlaylistDraft(title: "A")) == .failed)
    }

    @Test func deleteIsNotUndoneByALaggingList() async {
        var loader = SidebarLoader.stub
        loader.playlists = { _ in [playlist("VL1"), playlist("VL2")] }
        let model = makeModel(loader)
        await model.load()
        #expect(await model.delete("VL1"))
        #expect(ids(model) == ["VLLM", "VL2"])
        await model.load()
        #expect(ids(model) == ["VLLM", "VL2"])
        loader.playlists = { _ in [playlist("VL2")] }
        let fresh = makeModel(loader)
        await fresh.load()
        #expect(ids(fresh) == ["VLLM", "VL2"])
    }

    @Test func failedDeleteAndRemoveRollBackWithAToast() async {
        var loader = SidebarLoader.stub
        loader.playlists = { _ in [playlist("VL1"), playlist("VL2")] }
        loader.delete = { _, _ in throw Failure() }
        loader.removeFromLibrary = { _, _ in throw Failure() }
        let toasts = ToastCenter()
        let model = makeModel(loader, toasts: toasts)
        await model.load()
        #expect(await model.delete("VL1") == false)
        #expect(ids(model) == ["VLLM", "VL1", "VL2"])
        #expect(toasts.message != nil)
        #expect(await model.removeFromLibrary("VL2") == false)
        #expect(ids(model) == ["VLLM", "VL1", "VL2"])
    }

    @Test func removeFromLibrarySendsTheBrowseId() async {
        let calls = CallLog()
        var loader = SidebarLoader.stub
        loader.playlists = { _ in [playlist("VL1")] }
        loader.removeFromLibrary = { id, _ in calls.record(id) }
        let model = makeModel(loader)
        await model.load()
        #expect(await model.removeFromLibrary("VL1"))
        #expect(calls.all == ["VL1"])
        #expect(ids(model) == ["VLLM"])
    }

    @Test func applyLibraryChangeInsertsAndRemoves() async {
        var loader = SidebarLoader.stub
        loader.playlists = { _ in [playlist("VL1")] }
        let model = makeModel(loader)
        await model.load()
        model.applyLibraryChange(playlist("VL9"), saved: true)
        #expect(ids(model) == ["VLLM", "VL9", "VL1"])
        model.applyLibraryChange(playlist("VL1"), saved: false)
        #expect(ids(model) == ["VLLM", "VL9"])
        model.applyLibraryChange(playlist("VL1"), saved: true)
        #expect(ids(model) == ["VLLM", "VL9", "VL1"])
    }

    @Test func ownershipPrefixRulesAndCache() async {
        let calls = CallLog()
        var loader = SidebarLoader.stub
        loader.isOwned = { id, _ in
            calls.record(id)
            return id == "VLmine"
        }
        let model = makeModel(loader)
        #expect(model.ownership(of: Route.likedMusicBrowseId) == nil)
        #expect(model.ownership(of: "VLRDCLAK1") == false)
        #expect(model.ownership(of: "VLOLAK5uy_x") == false)
        #expect(model.ownership(of: "VLRDEM1") == false)
        #expect(model.ownership(of: "VLmine") == nil)
        await model.resolveOwnership("VLmine")
        await model.resolveOwnership("VLmine")
        await model.resolveOwnership("VLsaved")
        await model.resolveOwnership("VLRDCLAK1")
        await model.resolveOwnership(Route.likedMusicBrowseId)
        #expect(model.ownership(of: "VLmine") == true)
        #expect(model.ownership(of: "VLsaved") == false)
        #expect(calls.all == ["VLmine", "VLsaved"])
    }

    @Test func failedOwnershipLookupStaysUnknown() async {
        var loader = SidebarLoader.stub
        loader.isOwned = { _, _ in throw Failure() }
        let model = makeModel(loader)
        await model.resolveOwnership("VL1")
        #expect(model.ownership(of: "VL1") == nil)
    }

    @Test func resetDropsInFlightResultsAndTheCaches() async {
        var loader = SidebarLoader.stub
        loader.playlists = { _ in
            try await Task.sleep(for: .milliseconds(40))
            return [playlist("VLold")]
        }
        let model = makeModel(loader)
        _ = await model.create(NewPlaylistDraft(title: "A"))
        let task = Task { await model.load() }
        try? await Task.sleep(for: .milliseconds(10))
        model.reset()
        await task.value
        guard case .loading = model.state else { Issue.record("expected loading"); return }
        #expect(model.ownership(of: "VLNEW") == nil)
        loader.playlists = { _ in [playlist("VLnew")] }
        let next = makeModel(loader)
        await next.load()
        #expect(ids(next) == ["VLLM", "VLnew"])
    }

    @Test func loadAfterResetEndsLoaded() async {
        var loader = SidebarLoader.stub
        loader.playlists = { _ in [playlist("VL1")] }
        let model = makeModel(loader)
        model.reset()
        await model.load()
        #expect(ids(model) == ["VLLM", "VL1"])
    }

    @Test func mutationResultAfterResetIsDiscarded() async {
        var loader = SidebarLoader.stub
        loader.create = { _, _ in
            try await Task.sleep(for: .milliseconds(40))
            return "NEW"
        }
        let model = makeModel(loader)
        await model.load()
        let task = Task { await model.create(NewPlaylistDraft(title: "A")) }
        try? await Task.sleep(for: .milliseconds(10))
        model.reset()
        #expect(await task.value == .discarded)
    }

    @Test func addSendsOneBatchedEditAndUndoRemovesTheAddedRows() async {
        let calls = CallLog()
        var loader = SidebarLoader.stub
        loader.playlists = { _ in [playlist("VL1", title: "Mix")] }
        loader.edit = { id, edits, _ in
            calls.record("\(id) \(edits)")
            return edits.contains { if case .add = $0 { true } else { false } } ? [AddedPlaylistRow(videoId: "a", setVideoId: "s1")] : []
        }
        let toasts = ToastCenter()
        let model = makeModel(loader, toasts: toasts)
        await model.load()
        await model.add(videoIds: ["a", "b"], to: "VL1")
        #expect(calls.all.count == 1)
        #expect(model.ownership(of: "VL1") == true)
        toasts.undo()
        for _ in 0..<20 { await Task.yield() }
        #expect(calls.all.last?.contains("remove") == true)
    }

    @Test func addingNothingNewReportsAlreadyThere() async {
        let toasts = ToastCenter()
        let model = makeModel(.stub, toasts: toasts)
        await model.add(videoIds: ["a"], to: "VL1")
        #expect(toasts.toast != nil && toasts.toast?.undo == nil)
    }

    @Test func failedAddShowsAnErrorWithoutUndo() async {
        var loader = SidebarLoader.stub
        loader.edit = { _, _, _ in throw Failure() }
        let toasts = ToastCenter()
        let model = makeModel(loader, toasts: toasts)
        await model.add(videoIds: ["a"], to: "VL1")
        #expect(toasts.toast != nil && toasts.toast?.undo == nil)
        #expect(model.ownership(of: "VL1") == nil)
    }
}
