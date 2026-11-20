import InnerTube
import PlayerEngine
import SwiftUI

struct PlayerBar: View {
    @Binding var isPlayerPagePresented: Bool
    @Environment(NowPlayingModel.self) private var nowPlaying
    @Environment(NavigationModel.self) private var navigation
    @Environment(\.requestSignIn) private var requestSignIn

    private var player: any PlayerControlling { nowPlaying.player }

    var body: some View {
        HStack(spacing: Metrics.space16) {
            transport
            Spacer(minLength: 0)
            nowPlayingInfo
                .frame(maxWidth: Metrics.playerBarCenterMaxWidth)
            Spacer(minLength: 0)
            options
        }
        .padding(.horizontal, Metrics.space16)
        .frame(height: Metrics.playerBarHeight)
        .background(.themeBase)
        .background(.surfaceRaised)
        .overlay(alignment: .top) { ProgressLine() }
        .task(id: player.song?.videoId) {
            guard let song = player.song else { return }
            await nowPlaying.loadDetails(for: song)
        }
    }

    private var transport: some View {
        HStack(spacing: Metrics.space4) {
            BarIconButton(symbol: "backward.fill", size: Metrics.iconTransport - 8, label: "Previous", action: nowPlaying.previous)
            Button(action: nowPlaying.togglePlay) {
                Group {
                    if player.isBuffering {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: player.isPaused ? "play.fill" : "pause.fill")
                            .font(.rwIcon(Metrics.iconPlay - 12))
                    }
                }
                .foregroundStyle(.textPrimary)
                .frame(width: Metrics.iconPlay, height: Metrics.iconPlay)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(player.isPaused ? "Play" : "Pause")
            .accessibilityLabel(player.isPaused ? "Play" : "Pause")
            BarIconButton(symbol: "forward.fill", size: Metrics.iconTransport - 8, label: "Next", action: nowPlaying.next)
                .disabled(player.isAd)
            TimeLabel()
                .padding(.leading, Metrics.space8)
        }
    }

    private var nowPlayingInfo: some View {
        HStack(spacing: Metrics.space12) {
            Button { isPlayerPagePresented.toggle() } label: {
                Artwork(url: player.song?.artworkURL, isVideo: isVideo)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Open player page")
            .accessibilityLabel("Open player page")
            VStack(alignment: .leading, spacing: 0) {
                Button { isPlayerPagePresented.toggle() } label: {
                    if player.isAd {
                        Text("Ad").font(.rwTitle).foregroundStyle(.textPrimary)
                    } else {
                        Text(verbatim: player.song?.title ?? "")
                            .font(.rwTitle)
                            .foregroundStyle(.textPrimary)
                            .lineLimit(1)
                    }
                }
                .buttonStyle(.plain)
                .help("Open player page")
                subtitle
            }
            .layoutPriority(1)
            ratings
        }
    }

    private var isVideo: Bool {
        nowPlaying.details?.videoId == player.song?.videoId && nowPlaying.details?.isVideo == true
    }

    @ViewBuilder private var subtitle: some View {
        if !player.isAd, let song = player.song {
            SubtitleLinks(song: song, details: currentDetails) { navigation.push($0) }
        }
    }

    private var currentDetails: TrackDetails? {
        nowPlaying.details.flatMap { $0.videoId == player.song?.videoId ? $0 : nil }
    }

    private var ratings: some View {
        HStack(spacing: 0) {
            BarIconButton(
                symbol: player.like == .like ? "hand.thumbsup.fill" : "hand.thumbsup", size: Metrics.iconBar,
                label: "Like", isOn: player.like == .like, action: nowPlaying.toggleLike)
                .guestPrompt(isPresented: promptBinding(.like), reason: "Sign in to like songs", onSignIn: requestSignIn.perform)
            BarIconButton(
                symbol: player.like == .dislike ? "hand.thumbsdown.fill" : "hand.thumbsdown", size: Metrics.iconBar,
                label: "Dislike", isOn: player.like == .dislike, action: nowPlaying.toggleDislike)
                .guestPrompt(isPresented: promptBinding(.dislike), reason: "Sign in to dislike songs", onSignIn: requestSignIn.perform)
            moreMenu
        }
    }

    private func promptBinding(_ prompt: NowPlayingModel.LikePrompt) -> Binding<Bool> {
        Binding(
            get: { nowPlaying.likePrompt == prompt },
            set: { if !$0, nowPlaying.likePrompt == prompt { nowPlaying.likePrompt = nil } })
    }

    private var moreMenu: some View {
        Menu {
            if let artist = currentDetails?.artists.first?.browseId {
                Button("Go to artist") { navigation.push(.artist(channelId: artist)) }
            }
            if let album = currentDetails?.album?.browseId {
                Button("Go to album") { navigation.push(.album(browseId: album)) }
            }
            Button("Open player page") { isPlayerPagePresented = true }
        } label: {
            Image(systemName: "ellipsis")
                .font(.rwIcon(Metrics.iconBar))
                .foregroundStyle(.textSecondary)
                .frame(width: Metrics.hitTarget, height: Metrics.hitTarget)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)

        .help("More")
        .accessibilityLabel("More")
    }

    private var options: some View {
        HStack(spacing: Metrics.space4) {
            VolumeControl()
            BarIconButton(
                symbol: player.repeatMode == .one ? "repeat.1" : "repeat", size: Metrics.iconBar, label: "Repeat",
                isOn: player.repeatMode != .off, action: nowPlaying.cycleRepeat)
                .accessibilityValue(repeatValue)
            BarIconButton(
                symbol: "shuffle", size: Metrics.iconBar, label: "Shuffle", isOn: player.isShuffled,
                action: nowPlaying.toggleShuffle)
            BarIconButton(
                symbol: isPlayerPagePresented ? "chevron.down" : "chevron.up", size: Metrics.iconBar,
                label: isPlayerPagePresented ? "Close player page" : "Open player page",
                action: { isPlayerPagePresented.toggle() })
        }
    }

    private var repeatValue: Text {
        switch player.repeatMode {
        case .off: Text("Off")
        case .all: Text("All")
        case .one: Text("One")
        }
    }
}

private struct Artwork: View {
    let url: URL?
    let isVideo: Bool

    var body: some View {
        AsyncImage(url: url) { image in
            image.resizable().scaledToFill()
        } placeholder: {
            Rectangle().fill(.surfaceFill)
        }
        .frame(width: isVideo ? Metrics.videoArtworkWidth : Metrics.artworkSize, height: Metrics.artworkSize)
        .clipShape(RoundedRectangle(cornerRadius: Metrics.radiusThumb))
        .accessibilityHidden(true)
    }
}

private struct SubtitleLinks: View {
    let song: SongInfo
    let details: TrackDetails?
    let onOpen: (Route) -> Void

    var body: some View {
        HStack(spacing: 0) {
            if let details {
                ForEach(Array(details.artists.enumerated()), id: \.offset) { index, artist in
                    if index > 0 { separator(", ") }
                    link(artist) { .artist(channelId: $0) }
                }
                if let album = details.album {
                    separator(" • ")
                    link(album) { .album(browseId: $0) }
                }
            } else {
                Text(verbatim: [song.artist, song.album].compactMap { $0 }.joined(separator: " • "))
                    .font(.rwBody)
                    .foregroundStyle(.textSecondary)
            }
        }
        .lineLimit(1)

    }

    private func separator(_ text: String) -> some View {
        Text(verbatim: text).font(.rwBody).foregroundStyle(.textSecondary)
    }

    @ViewBuilder private func link(_ ref: ItemRef, route: @escaping (String) -> Route) -> some View {
        if let id = ref.browseId {
            LinkText(name: ref.name) { onOpen(route(id)) }
        } else {
            Text(verbatim: ref.name).font(.rwBody).foregroundStyle(.textSecondary)
        }
    }
}

private struct LinkText: View {
    let name: String
    let action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Text(verbatim: name)
                .font(.rwBody)
                .foregroundStyle(.textSecondary)
                .underline(isHovering)
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}

#if DEBUG
#Preview("Playing") {
    PlayerBarPreview(player: PreviewPlayer())
}

#Preview("Paused, liked, repeat one") {
    let player = PreviewPlayer()
    player.isPaused = true
    player.like = .like
    player.repeatMode = .one
    player.isShuffled = true
    return PlayerBarPreview(player: player)
}

#Preview("Buffering") {
    let player = PreviewPlayer()
    player.isBuffering = true
    return PlayerBarPreview(player: player)
}

#Preview("Ad") {
    let player = PreviewPlayer()
    player.isAd = true
    return PlayerBarPreview(player: player)
}

#Preview("Guest") {
    PlayerBarPreview(player: PreviewPlayer(), signedIn: false)
}

private struct PlayerBarPreview: View {
    let player: PreviewPlayer
    var signedIn = true

    var body: some View {
        let model = PreviewFixtures.nowPlaying(player, signedIn: signedIn)
        model.details = PreviewFixtures.details()
        return PlayerBar(isPlayerPagePresented: .constant(false))
            .environment(model)
            .environment(NavigationModel())
            .frame(width: 1100)
    }
}
#endif
