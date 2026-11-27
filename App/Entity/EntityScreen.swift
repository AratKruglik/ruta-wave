import InnerTube
import SwiftUI

struct EntityScreen: View {
    let model: EntityModel

    @Environment(NavigationModel.self) private var navigation
    @State private var width = Metrics.defaultWindowWidth
    @State private var selection = TrackSelection()

    private var isWide: Bool { width >= Metrics.widePageWidth }
    private var padding: CGFloat { isWide ? Metrics.space32 : Metrics.space24 }

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
            .task(id: model.loadKey) { await model.load() }
            .onReconnect { model.reloadIfFailed() }
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .loading:
            ScrollView {
                VStack(alignment: .leading, spacing: Metrics.space24) {
                    SkeletonEntityHeader(isArtist: isArtist, isWide: isWide)
                    SkeletonRows(count: 8)
                }
                .padding(isArtist ? .vertical : .all, padding)
            }
            .scrollDisabled(true)
        case .notAvailable:
            UnavailableView(title: unavailableTitle, onBack: navigation.back)
        case .failed:
            PageErrorView(onRetry: model.retry)
        case .loaded(let content):
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Metrics.space24) {
                    switch content.entity {
                    case .album(let album): albumBody(album, content)
                    case .artist(let artist): artistBody(artist, content)
                    case .playlist(let playlist): playlistBody(playlist, content)
                    }
                }
                .padding(.bottom, padding)
                // The artist photo runs under the bar to the window top, like the header gradient of the other pages.
                .padding(.top, isArtist ? -Metrics.topBarHeight : padding)
                .background(alignment: .top) {
                    if !isArtist { ThemeHeaderGradient().padding(.top, -Metrics.topBarHeight) }
                }
            }
            .trackSelection(
                $selection, songs: selectableSongs(content), onRemove: model.canEdit ? { model.removeRows($0) } : nil,
                onMove: model.canEdit ? { from, to in moveRows(from: from, to: to, in: content.tracks.map(\.rowKey)) } : nil)
        }
    }

    private func selectableSongs(_ content: EntityModel.Content) -> [Song] {
        switch content.entity {
        case .album(let album): album.tracks.map(\.song)
        case .playlist: content.tracks
        case .artist: []
        }
    }

    private var isArtist: Bool {
        if case .artist = model.kind { true } else { false }
    }

    private var unavailableTitle: LocalizedStringKey {
        switch model.kind {
        case .album: "This album isn't available"
        case .artist: "This artist isn't available"
        case .playlist: "This playlist isn't available"
        }
    }

    // MARK: Album

    @ViewBuilder
    private func albumBody(_ album: AlbumPage, _ content: EntityModel.Content) -> some View {
        EntityHeader(model: model, header: album.header, isSaved: content.isSaved, showsShuffle: true, isWide: isWide)
            .padding(.horizontal, padding)
        let order = album.tracks.map(\.song.rowKey)
        VStack(spacing: 0) {
            ForEach(album.tracks.indices, id: \.self) { index in
                let song = album.tracks[index].song
                TrackRow(
                    song: song, density: .numbered, selection: $selection.row(for: song, order: order, songs: album.tracks.map(\.song)), number: album.tracks[index].number)
            }
        }
        .padding(.horizontal, padding)
        if album.tracks.isEmpty { emptyNote("This album has no songs available") }
        shelves(album.shelves)
    }

    // MARK: Artist

    @ViewBuilder
    private func artistBody(_ artist: ArtistPage, _ content: EntityModel.Content) -> some View {
        ArtistHeader(model: model, artist: artist, isSubscribed: content.isSubscribed, width: width, inset: padding)
        if artist.shelves.isEmpty { emptyNote("Nothing from this artist yet") }
        shelves(artist.shelves, moreTitle: "Show all")
        ArtistAbout(artist: artist).padding(.horizontal, padding)
    }

    // MARK: Playlist

    @ViewBuilder
    private func playlistBody(_ playlist: PlaylistPage, _ content: EntityModel.Content) -> some View {
        EntityHeader(model: model, header: playlist.header, isSaved: content.isSaved, showsShuffle: false, isWide: isWide)
            .padding(.horizontal, padding)
        let order = content.tracks.map(\.rowKey)
        LazyVStack(spacing: 0) {
            ForEach(content.tracks.indices, id: \.self) { index in
                let song = content.tracks[index]
                TrackRow(
                    song: song, density: .detailed, selection: $selection.row(for: song, order: order, songs: content.tracks),
                    place: model.canEdit ? .ownPlaylistRow : .plain, sourcePlaylistId: model.canEdit ? model.playlistBrowseId : nil,
                    onAction: { if $0 == .removeFromPlaylist { model.removeRows([song.rowKey]) } })
                    .dropDestination(for: TrackDrag.self) { drags, _ in reorder(drags, before: song) }
                    .onAppear { if index >= content.tracks.count - 10 { model.loadMore() } }
            }
            footer(content, isOwned: playlist.isOwned)
        }
        .padding(.horizontal, padding)
        ForEach(content.sections.indices, id: \.self) { index in
            if model.canAddSuggestions {
                SuggestionsShelf(shelf: content.sections[index], onAdd: model.add).padding(.horizontal, padding)
            } else {
                ShelfView(shelf: content.sections[index], onMore: { navigation.push(Route(target: $0)) }, pageMargin: padding)
                    .padding(.horizontal, padding)
            }
        }
    }

    /// A neighbour hops over the selected block: up lands it after the block, down lands it before the block.
    private func moveRows(from: Int, to: Int, in order: [String]) {
        guard order.indices.contains(from), order.indices.contains(to) else { return }
        if from < to {
            model.moveRow(order[from], before: to + 1 < order.count ? order[to + 1] : nil)
        } else {
            model.moveRow(order[from], before: order[to])
        }
    }

    /// Only rows dragged from this same own playlist reorder it; the drop lands before the row it is released on.
    private func reorder(_ drags: [TrackDrag], before song: Song) -> Bool {
        guard model.canEdit, let id = model.playlistBrowseId else { return false }
        let keys = drags.filter { $0.sourcePlaylistId == id }.flatMap(\.setVideoIds)
        guard !keys.isEmpty else { return false }
        for key in keys { model.moveRow(key, before: song.rowKey) }
        return true
    }

    @ViewBuilder
    private func footer(_ content: EntityModel.Content, isOwned: Bool) -> some View {
        switch content.paging {
        case .idle: Color.clear.frame(height: 1).onAppear { model.loadMore() }
        case .loading: ProgressView().frame(maxWidth: .infinity).controlSize(.small)
        case .failed: InlineErrorRow(onRetry: model.retryMore)
        case .done:
            if content.tracks.isEmpty {
                if isOwned {
                    emptyNote("This playlist has no songs yet")
                } else {
                    emptyNote("This playlist is empty", message: "Songs added to it will show up here.")
                }
            }
            Color.clear.frame(height: 1).onAppear { model.loadSections() }
        }
    }

    private func emptyNote(_ title: LocalizedStringKey, message: LocalizedStringKey? = nil) -> some View {
        VStack(spacing: Metrics.space4) {
            Text(title).font(.rwBody).foregroundStyle(.textPrimary)
            if let message { Text(message).font(.rwCaption).foregroundStyle(.textSecondary) }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Metrics.space16)
        .accessibilityElement(children: .combine)
    }

    private func shelves(_ shelves: [Shelf], moreTitle: LocalizedStringKey = "More") -> some View {
        VStack(alignment: .leading, spacing: Metrics.space48) {
            ForEach(shelves.indices, id: \.self) { index in
                ShelfView(shelf: shelves[index], onMore: { navigation.push(Route(target: $0)) }, moreTitle: moreTitle, pageMargin: padding)
            }
        }
        .padding(.horizontal, padding)
    }
}

private struct SuggestionsShelf: View {
    let shelf: Shelf
    let onAdd: (Song) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.space16) {
            Text("Suggestions")
                .font(.rwShelfTitle)
                .foregroundStyle(.textPrimary)
                .accessibilityAddTraits(.isHeader)
            ForEach(Array(shelf.items.enumerated()), id: \.offset) { _, item in
                if case .song(let song) = item {
                    HStack(spacing: Metrics.space12) {
                        TrackRow(song: song, density: .detailed)
                        Button("Add") { onAdd(song) }
                            .buttonStyle(PillButtonStyle())
                            .accessibilityLabel("Add \(song.title)")
                    }
                }
            }
        }
    }
}

#if DEBUG
#Preview("Album") { EntityPreview(.album) }
#Preview("Artist") { EntityPreview(.artist) }
#Preview("Playlist") { EntityPreview(.playlist) }
#Preview("Playlist, narrow") { EntityPreview(.playlist, width: 960) }
#Preview("Own playlist") { EntityPreview(.ownPlaylist) }
#Preview("Guest") { EntityPreview(.guest) }
#Preview("Loading") { EntityPreview(.loading) }
#Preview("Not available") { EntityPreview(.notAvailable) }
#Preview("Partial error") { EntityPreview(.partialError) }

private struct EntityPreview: View {
    let variant: PreviewFixtures.EntityVariant
    let width: CGFloat
    @State private var model: EntityModel

    init(_ variant: PreviewFixtures.EntityVariant, width: CGFloat = 1100) {
        self.variant = variant
        self.width = width
        _model = State(initialValue: PreviewFixtures.entityModel(variant))
    }

    var body: some View {
        EntityScreen(model: model)
            .frame(width: width, height: 800)
            .environment(NavigationModel())
            .environment(PreviewFixtures.nowPlaying(signedIn: variant != .guest))
            .environment(ToastCenter())
            .background(.themeBase)
    }
}
#endif
