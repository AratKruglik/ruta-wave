import PlayerEngine
import SwiftUI

struct MiniPlayerView: View {
    let nowPlaying: NowPlayingModel

    private var player: any PlayerControlling { nowPlaying.player }

    var body: some View {
        HStack(spacing: Metrics.space12) {
            ArtworkImage(
                url: player.song?.artworkURL, width: Metrics.miniPlayerArtworkSize, height: Metrics.miniPlayerArtworkSize)
            VStack(alignment: .leading, spacing: Metrics.space4) {
                titles
                    .accessibilityElement(children: .combine)
                transport
            }
            Spacer(minLength: 0)
        }
        .padding(Metrics.space12)
        .frame(width: Metrics.miniPlayerWidth)
        .windowBackdrop()
        .preferredColorScheme(.dark)
        .background(WindowLevel(isFloating: true))
    }

    private var titles: some View {
        VStack(alignment: .leading, spacing: 0) {
            if player.isAd {
                Text("Ad").font(.rwTitle).foregroundStyle(.textPrimary)
            } else if let song = player.song {
                Text(verbatim: song.title).font(.rwTitle).foregroundStyle(.textPrimary).lineLimit(1)
                Text(verbatim: song.artist).font(.rwCaption).foregroundStyle(.textSecondary).lineLimit(1)
            } else {
                Text("Not playing").font(.rwTitle).foregroundStyle(.textSecondary)
            }
        }
    }

    private var transport: some View {
        let hasSong = player.song != nil
        return HStack(spacing: Metrics.space4) {
            BarIconButton(symbol: "backward.fill", size: Metrics.iconTransport - 8, label: "Previous", action: nowPlaying.previous)
                .disabled(!hasSong)
            Button(action: nowPlaying.togglePlay) {
                Group {
                    if player.isBuffering {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: player.isPaused ? "play.fill" : "pause.fill")
                            .font(.rwIcon(Metrics.iconPlay - 12))
                    }
                }
                .foregroundStyle(hasSong ? .textPrimary : .textDisabled)
                .frame(width: Metrics.iconPlay, height: Metrics.iconPlay)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!hasSong)
            .help(player.isPaused ? "Play" : "Pause")
            .accessibilityLabel(player.isPaused ? "Play" : "Pause")
            BarIconButton(symbol: "forward.fill", size: Metrics.iconTransport - 8, label: "Next", action: nowPlaying.next)
                .disabled(!hasSong || player.isAd)
        }
    }
}

#if DEBUG
#Preview("Playing") {
    MiniPlayerView(nowPlaying: PreviewFixtures.nowPlaying())
}

#Preview("Not playing") {
    let player = PreviewPlayer()
    player.song = nil
    return MiniPlayerView(nowPlaying: PreviewFixtures.nowPlaying(player))
}
#endif
