import InnerTube
import SwiftUI

struct EntityScreen: View {
    let model: EntityModel

    @Environment(NavigationModel.self) private var navigation
    @State private var width = Metrics.defaultWindowWidth
    // Visual only for now; the selection bar arrives with 4.6.
    @State private var selected: Set<Int> = []

    private var isWide: Bool { width >= Metrics.widePageWidth }
    private var padding: CGFloat { isWide ? Metrics.space32 : Metrics.space24 }

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
            .task(id: model.loadKey) { await model.load() }
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
                .padding(.vertical, padding)
            }
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

    private func selection(_ index: Int) -> Binding<Bool> {
        Binding(
            get: { selected.contains(index) },
            set: { if $0 { selected.insert(index) } else { selected.remove(index) } })
    }

    // MARK: Album

    @ViewBuilder
    private func albumBody(_ album: AlbumPage, _ content: EntityModel.Content) -> some View {
        EntityHeader(model: model, header: album.header, isSaved: content.isSaved, showsShuffle: true, isWide: isWide)
            .padding(.horizontal, padding)
        VStack(spacing: 0) {
            ForEach(album.tracks.indices, id: \.self) { index in
                TrackRow(
                    song: album.tracks[index].song, density: .numbered, isSelected: selection(index), number: album.tracks[index].number)
            }
        }
        .padding(.horizontal, padding)
        if let summary = album.header.secondSubtitle {
            Text(summary)
                .font(.rwBody)
                .foregroundStyle(.textSecondary)
                .padding(.horizontal, padding)
        }
        shelves(album.shelves)
    }

    // MARK: Artist

    @ViewBuilder
    private func artistBody(_ artist: ArtistPage, _ content: EntityModel.Content) -> some View {
        ArtistHeader(model: model, artist: artist, isSubscribed: content.isSubscribed, width: width, inset: padding)
        shelves(artist.shelves, moreTitle: "Show all")
        ArtistAbout(artist: artist).padding(.horizontal, padding)
    }

    // MARK: Playlist

    @ViewBuilder
    private func playlistBody(_ playlist: PlaylistPage, _ content: EntityModel.Content) -> some View {
        EntityHeader(model: model, header: playlist.header, isSaved: content.isSaved, showsShuffle: false, isWide: isWide)
            .padding(.horizontal, padding)
        VStack(spacing: 0) {
            ForEach(content.tracks.indices, id: \.self) { index in
                TrackRow(song: content.tracks[index], density: .detailed, isSelected: selection(index))
                    .onAppear { if index >= content.tracks.count - 10 { model.loadMore() } }
            }
            footer(content, isOwned: playlist.isOwned)
        }
        .padding(.horizontal, padding)
        ForEach(content.sections.indices, id: \.self) { index in
            if model.canAddSuggestions {
                SuggestionsShelf(shelf: content.sections[index], onAdd: model.add).padding(.horizontal, padding)
            } else {
                ShelfView(shelf: content.sections[index]) { navigation.push(Route(target: $0)) }
                    .padding(.horizontal, padding)
            }
        }
    }

    @ViewBuilder
    private func footer(_ content: EntityModel.Content, isOwned: Bool) -> some View {
        switch content.paging {
        case .idle: Color.clear.frame(height: 1).onAppear { model.loadMore() }
        case .loading: ProgressView().frame(maxWidth: .infinity).controlSize(.small)
        case .failed: InlineErrorRow(onRetry: model.retryMore)
        case .done:
            if content.tracks.isEmpty && isOwned {
                Text("This playlist has no songs yet")
                    .font(.rwBody)
                    .foregroundStyle(.textSecondary)
                    .padding(.vertical, Metrics.space16)
            }
            Color.clear.frame(height: 1).onAppear { model.loadSections() }
        }
    }

    private func shelves(_ shelves: [Shelf], moreTitle: LocalizedStringKey = "More") -> some View {
        VStack(alignment: .leading, spacing: Metrics.space48) {
            ForEach(shelves.indices, id: \.self) { index in
                ShelfView(shelf: shelves[index], onMore: { navigation.push(Route(target: $0)) }, moreTitle: moreTitle)
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
                        Button { onAdd(song) } label: { InversePillLabel(title: "Add") }
                            .buttonStyle(.plain)
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
