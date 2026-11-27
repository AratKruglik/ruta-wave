import InnerTube
import SwiftUI

struct LibraryScreen: View {
    let model: LibraryModel

    @Environment(NavigationModel.self) private var navigation
    @Environment(NowPlayingModel.self) private var nowPlaying
    @State private var width = Metrics.defaultWindowWidth
    @State private var selection = TrackSelection()

    private var padding: CGFloat { width >= Metrics.widePageWidth ? Metrics.space32 : Metrics.space24 }

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.space16) {
            header
            if !model.sections.isEmpty {
                sectionPicker
            } else if case .loading = model.state {
                Picker("Library", selection: .constant(0)) {
                    ForEach(0..<4, id: \.self) { Text(verbatim: "Placeholder").tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .placeholderStyle()
            }
            pageBody
        }
        .padding([.horizontal, .top], padding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .task(id: model.loadKey) { await model.load() }
        .onReconnect { model.reloadIfFailed() }
    }

    private var header: some View {
        HStack(spacing: Metrics.space12) {
            Text("Library")
                .font(.rwShelfTitle)
                .foregroundStyle(.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: Metrics.space16)
            if !model.sortOptions.isEmpty { sortMenu }
            Button { navigation.push(.history) } label: { Label("History", systemImage: "clock") }
                .buttonStyle(PillButtonStyle())
                .help("History")
                .accessibilityLabel("History")
        }
    }

    private var sectionPicker: some View {
        let selection = Binding(
            get: { model.section },
            set: { id in if let chip = model.sections.first(where: { $0.target?.browseId == id }) { model.selectSection(chip) } }
        )
        return Picker("Library", selection: selection) {
            ForEach(model.sections, id: \.title) { chip in
                Text(chip.title).tag(chip.target?.browseId ?? chip.title)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()
    }

    private var sortMenu: some View {
        Menu {
            ForEach(model.sortOptions) { option in
                Button { model.selectSort(option) } label: {
                    if option.isSelected { Label(option.title, systemImage: "checkmark") } else { Text(option.title) }
                }
            }
        } label: {
            Label { model.sortOptions.first(where: \.isSelected).map { Text($0.title) } ?? Text("Sort") } icon: { Image(systemName: "arrow.up.arrow.down") }
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .buttonStyle(PillButtonStyle())
        .fixedSize()
        .help("Sort")
        .accessibilityLabel("Sort")
    }

    @ViewBuilder
    private var pageBody: some View {
        switch model.state {
        case .loading:
            ScrollView {
                skeleton
            }
            .scrollDisabled(true)
        case .failed:
            LoadErrorView(title: "Couldn't load your library", onRetry: model.retry)
        case .loaded(let content):
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Metrics.space16) {
                    loaded(content)
                    footer(content.paging)
                }
                .padding(.bottom, padding)
            }
        }
    }

    @ViewBuilder
    private var skeleton: some View {
        switch LibraryModel.kind(of: model.section) {
        case .songs:
            VStack(spacing: 0) {
                ForEach(0..<8, id: \.self) { _ in TrackRow(song: .placeholder, density: .detailed) }
            }
            .placeholderStyle()
        case .artists:
            VStack(spacing: 0) {
                ForEach(0..<8, id: \.self) { _ in ArtistRow(artist: .placeholder) }
            }
            .placeholderStyle()
        case .playlists, .albums:
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: Metrics.cardSize), spacing: Metrics.space16, alignment: .topLeading)],
                alignment: .leading, spacing: Metrics.space24
            ) {
                ForEach(0..<8, id: \.self) { _ in MusicCard(item: .placeholder) }
            }
            .placeholderStyle()
        }
    }

    @ViewBuilder
    private func loaded(_ content: LibraryModel.Content) -> some View {
        switch content.kind {
        case .playlists, .albums:
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: Metrics.cardSize), spacing: Metrics.space16, alignment: .topLeading)],
                alignment: .leading, spacing: Metrics.space24
            ) {
                if content.kind == .playlists { NewPlaylistCard { navigation.requestNewPlaylist() } }
                if let liked = content.likedMusic { MusicCard(item: .playlist(liked)) }
                ForEach(Array(content.items.enumerated()), id: \.element.libraryKey) { index, item in
                    MusicCard(item: item).onAppear { prefetch(index, of: content.items.count) }
                }
            }
            if content.kind == .albums, content.items.isEmpty { hint("Albums you save appear here") }
        case .songs:
            let songs = content.items.compactMap { if case .song(let song) = $0 { song } else { nil } }
            let order = songs.map(\.rowKey)
            if !songs.isEmpty { songActions }
            LazyVStack(spacing: 0) {
                ForEach(Array(content.items.enumerated()), id: \.element.libraryKey) { index, item in
                    if case .song(let song) = item {
                        TrackRow(song: song, density: .detailed, knownRating: .like, selection: $selection.row(for: song, order: order, songs: songs))
                            .onAppear { prefetch(index, of: content.items.count) }
                    }
                }
            }
            .trackSelection($selection, songs: songs)
            if content.items.isEmpty { hint("Songs you like appear here") }
        case .artists:
            LazyVStack(spacing: 0) {
                ForEach(Array(content.items.enumerated()), id: \.element.libraryKey) { index, item in
                    if case .artist(let artist) = item {
                        ArtistRow(artist: artist).onAppear { prefetch(index, of: content.items.count) }
                    }
                }
            }
            if content.items.isEmpty {
                if model.section == BrowseTarget.librarySubscriptions.browseId {
                    hint("Artists you subscribe to appear here")
                } else {
                    hint("Artists you listen to appear here")
                }
            }
        }
    }

    private var songActions: some View {
        let liked = MusicItem.playlist(Playlist(browseId: Route.likedMusicBrowseId, title: String(localized: "Liked music")))
        return HStack(spacing: Metrics.space12) {
            Button("Play") { nowPlaying.play(liked) }
                .buttonStyle(PillButtonStyle(isProminent: true))
            Button { nowPlaying.shuffle(liked) } label: { Label("Shuffle", systemImage: "shuffle") }
                .buttonStyle(PillButtonStyle())
        }
    }

    private func hint(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(.rwBody)
            .foregroundStyle(.textSecondary)
            .padding(.vertical, Metrics.space16)
    }

    private func prefetch(_ index: Int, of count: Int) {
        if index >= count - 10 { model.loadMore() }
    }

    @ViewBuilder
    private func footer(_ paging: LibraryModel.Paging) -> some View {
        switch paging {
        case .loading: ProgressView().frame(maxWidth: .infinity).controlSize(.small)
        case .failed: InlineErrorRow(onRetry: model.retryMore)
        case .idle: Color.clear.frame(height: 1).onAppear { model.loadMore() }
        case .done: EmptyView()
        }
    }
}

private struct NewPlaylistCard: View {
    let action: () -> Void

    @State private var isHovering = false
    @FocusState private var isFocused: Bool

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: Metrics.space8) {
                Image(systemName: "plus")
                    .font(.rwIcon(Metrics.iconPlay))
                    .foregroundStyle(.textPrimary)
                    .frame(width: Metrics.cardSize, height: Metrics.cardSize)
                    .background(isHovering || isFocused ? Color.surfaceRaised : .surfaceFill, in: RoundedRectangle(cornerRadius: Metrics.radiusCard))
                    .overlay { RoundedRectangle(cornerRadius: Metrics.radiusCard).stroke(.strokeFocus, lineWidth: isFocused ? 2 : 0) }
                Text("New playlist")
                    .font(.rwTitle)
                    .foregroundStyle(.textPrimary)
                    .lineLimit(1)
            }
            .frame(width: Metrics.cardSize, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focused($isFocused)
        .onHover { isHovering = $0 }
        .accessibilityLabel("New playlist")
    }
}

struct LibraryGuestView: View {
    let onSignIn: () -> Void

    var body: some View {
        VStack(spacing: Metrics.space12) {
            Text("Enjoy your favourite music")
                .font(.rwShelfTitle)
                .foregroundStyle(.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Text("Sign in to see your playlists, songs, albums and artists in one place.")
                .font(.rwBody)
                .foregroundStyle(.textSecondary)
                .multilineTextAlignment(.center)
            Button("Sign in", action: onSignIn)
                .buttonStyle(PillButtonStyle())
        }
        .padding(Metrics.space24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private extension MusicItem {
    var libraryKey: String {
        switch self {
        case .song(let song): song.videoId
        case .album(let album): album.browseId
        case .playlist(let playlist): playlist.browseId
        case .artist(let artist): artist.browseId
        case .link(let link): link.title
        }
    }
}

#if DEBUG
#Preview("Playlists") { LibraryPreview(.playlists) }
#Preview("Songs") { LibraryPreview(.songs) }
#Preview("Albums") { LibraryPreview(.albums) }
#Preview("Artists") { LibraryPreview(.artists) }
#Preview("Empty section") { LibraryPreview(.empty) }
#Preview("Loading") { LibraryPreview(.loading) }
#Preview("Failed") { LibraryPreview(.failed) }
#Preview("Guest") {
    LibraryGuestView(onSignIn: {}).frame(width: 900, height: 500).background(.themeBase)
}

private struct LibraryPreview: View {
    let variant: PreviewFixtures.LibraryVariant
    @State private var model: LibraryModel

    init(_ variant: PreviewFixtures.LibraryVariant) {
        self.variant = variant
        _model = State(initialValue: PreviewFixtures.libraryModel(variant))
    }

    var body: some View {
        LibraryScreen(model: model)
            .frame(width: 1100, height: 800)
            .environment(NavigationModel())
            .environment(PreviewFixtures.nowPlaying())
            .environment(ToastCenter())
            .background(.themeBase)
    }
}
#endif
