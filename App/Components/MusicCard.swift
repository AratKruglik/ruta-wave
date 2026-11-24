import InnerTube
import SwiftUI

extension MusicItem {
    var cardTitle: String {
        switch self {
        case .song(let song): song.title
        case .album(let album): album.title
        case .artist(let artist): artist.name
        case .playlist(let playlist): playlist.title
        case .link(let link): link.title
        }
    }

    var cardSubtitle: String? {
        switch self {
        case .song(let song): song.subtitle
        case .album(let album): album.subtitle
        case .artist(let artist): artist.subtitle
        case .playlist(let playlist): playlist.subtitle
        case .link: nil
        }
    }

    var thumbnailURL: URL? {
        switch self {
        case .song(let song): song.thumbnailURL
        case .album(let album): album.thumbnailURL
        case .artist(let artist): artist.thumbnailURL
        case .playlist(let playlist): playlist.thumbnailURL
        case .link: nil
        }
    }

    var isExplicit: Bool {
        switch self {
        case .song(let song): song.isExplicit
        case .album(let album): album.isExplicit
        default: false
        }
    }

    var isVideoCard: Bool {
        if case .song(let song) = self { song.isVideo } else { false }
    }

    var isArtist: Bool {
        if case .artist = self { true } else { false }
    }
}

struct MusicCard: View {
    let item: MusicItem

    private enum Field: Hashable { case main, play, menu }

    @Environment(NavigationModel.self) private var navigation
    @Environment(NowPlayingModel.self) private var nowPlaying
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false
    @State private var popover: ItemPopover?
    @FocusState private var focus: Field?

    private var width: CGFloat { item.isVideoCard ? Metrics.videoCardWidth : Metrics.cardSize }
    private var height: CGFloat { item.isVideoCard ? Metrics.videoCardHeight : Metrics.cardSize }
    private var showsControls: Bool { isHovering || focus != nil }

    var body: some View {
        VStack(alignment: item.isArtist ? .center : .leading, spacing: Metrics.space8) {
            artwork
            texts
        }
        .frame(width: width)
        .onHover { isHovering = $0 }
        .animation(Motion.animation(Motion.hover, reduceMotion: reduceMotion), value: showsControls)
    }

    private var artwork: some View {
        ZStack {
            Button { activate(item, navigation: navigation, nowPlaying: nowPlaying) } label: {
                ArtworkImage(url: item.thumbnailURL, width: width, height: height, isCircle: item.isArtist)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .focused($focus, equals: .main)
            .accessibilityLabel(accessibilityLabel)

            if item.canPlay {
                Button { nowPlaying.play(item) } label: {
                    Image(systemName: "play.fill")
                        .font(.rwIcon(Metrics.iconBar))
                        .foregroundStyle(.textOnInverse)
                        .frame(width: Metrics.cardPlayButton, height: Metrics.cardPlayButton)
                        .background(.surfaceInverse, in: Circle())
                }
                .buttonStyle(.plain)
                .focused($focus, equals: .play)
                .opacity(showsControls ? 1 : 0)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                .padding(Metrics.space8)
                .help("Play")
                .accessibilityLabel("Play")
            }

            Menu { ItemMenu(item: item, popover: $popover) } label: {
                Image(systemName: "ellipsis")
                    .font(.rwIcon(Metrics.iconRow))
                    .foregroundStyle(.textPrimary)
                    .frame(width: Metrics.hitTarget, height: Metrics.hitTarget)
                    .background(.scrim, in: Circle())
            }
            .menuStyle(.button)
            .menuIndicator(.hidden)
            .buttonStyle(.plain)
            .focused($focus, equals: .menu)
            .opacity(showsControls ? 1 : 0)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            .padding(Metrics.space8)
            .help("More actions")
            .accessibilityLabel("More actions")

            if nowPlaying.isPlaying(item) {
                Image(systemName: "waveform")
                    .symbolEffect(.variableColor.iterative, isActive: !reduceMotion && !nowPlaying.player.isPaused)
                    .font(.rwIcon(Metrics.iconRow))
                    .foregroundStyle(.textPrimary)
                    .padding(Metrics.space8)
                    .background(.scrim, in: Circle())
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(Metrics.space8)
                    .accessibilityHidden(true)
            }
        }
        .frame(width: width, height: height)
        .draggable(dragPayload)
        .contextMenu { ItemMenu(item: item, popover: $popover) }
        .itemPopover($popover)
    }

    private var texts: some View {
        VStack(alignment: item.isArtist ? .center : .leading, spacing: 2) {
            HStack(spacing: Metrics.space4) {
                Text(item.cardTitle)
                    .font(.rwTitle)
                    .foregroundStyle(.textPrimary)
                    .lineLimit(1)
                if item.isExplicit { ExplicitBadge() }
            }
            if let subtitle = item.cardSubtitle {
                Text(subtitle)
                    .font(.rwCaption)
                    .foregroundStyle(.textSecondary)
                    .lineLimit(2)
            }
        }
        .multilineTextAlignment(item.isArtist ? .center : .leading)
        .contentShape(Rectangle())
        .onTapGesture { activate(item, navigation: navigation, nowPlaying: nowPlaying) }
        .accessibilityHidden(true)
    }

    private var dragPayload: TrackDrag {
        switch item {
        case .song(let song): TrackDrag(videoIds: [song.videoId])
        case .album(let album): TrackDrag(playlistId: album.playTarget?.playlistId)
        case .playlist(let playlist): TrackDrag(playlistId: playlist.playTarget?.playlistId ?? playlist.browseId.removingVLPrefix)
        case .artist, .link: TrackDrag()
        }
    }

    private var accessibilityLabel: String {
        [item.cardTitle, item.cardSubtitle, nowPlaying.isPlaying(item) ? String(localized: "Now playing") : nil]
            .compactMap { $0 }.joined(separator: ", ")
    }
}

struct ExplicitBadge: View {
    var body: some View {
        Text(verbatim: "E")
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(.textOnInverse)
            .frame(width: Metrics.explicitBadge, height: Metrics.explicitBadge)
            .background(.textTertiary, in: RoundedRectangle(cornerRadius: 2))
            .accessibilityLabel("Explicit")
    }
}

#if DEBUG
#Preview("Cards") {
    HStack(alignment: .top, spacing: Metrics.space16) {
        ForEach(Array(PreviewFixtures.cardItems.enumerated()), id: \.offset) { _, item in MusicCard(item: item) }
    }
    .padding()
    .environment(NavigationModel())
    .environment(PreviewFixtures.nowPlaying())
    .environment(ToastCenter())
    .background(.themeBase)
}
#endif

extension String {
    fileprivate var removingVLPrefix: String { hasPrefix("VL") ? String(dropFirst(2)) : self }
}
