import PlayerEngine
import AppKit
import SwiftUI

struct MiniPlayerView: View {
    let nowPlaying: NowPlayingModel
    let showMainWindow: () -> Void
    @State private var isHovering = false

    private var player: any PlayerControlling { nowPlaying.player }

    var body: some View {
        HStack(spacing: Metrics.space12) {
            Button(action: showMainWindow) {
                ArtworkImage(url: player.song?.artworkURL, width: Metrics.miniPlayerArtworkSize, height: artworkHeight)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Show RutaWave")
            .accessibilityLabel("Show RutaWave")
            VStack(alignment: .leading, spacing: Metrics.space4) {
                titles
                    .accessibilityElement(children: .combine)
                transport
            }
            Spacer(minLength: 0)
        }
        .padding(Metrics.space12)
        .frame(width: Metrics.miniPlayerWidth)
        .overlay(alignment: .bottom) { MiniProgress(nowPlaying: nowPlaying) }
        .windowBackdrop()
        .preferredColorScheme(.dark)
        .noInitialFocus()
        .onHover { isHovering = $0 }
        .background(WindowLevel(isFloating: true))
        .background(MiniWindowChrome(showsButtons: isHovering))
    }

    private var artworkHeight: CGFloat {
        nowPlaying.details?.isVideo == true ? Metrics.miniPlayerArtworkSize * 9 / 16 : Metrics.miniPlayerArtworkSize
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
            BarIconButton(
                symbol: player.like == .like ? "hand.thumbsup.fill" : "hand.thumbsup", size: Metrics.iconTransport - 8,
                label: "Like", isOn: player.like == .like, action: nowPlaying.toggleLike)
                .disabled(!hasSong || player.isAd || !nowPlaying.isSignedIn)
        }
    }
}

/// Reads `elapsed` here so the per-tick updates re-run only this view.
private struct MiniProgress: View {
    let nowPlaying: NowPlayingModel

    var body: some View {
        let player = nowPlaying.player
        let duration = player.song?.duration ?? 0
        let fraction = duration > 0 ? min(max(player.elapsed / duration, 0), 1) : 0
        Rectangle()
            .fill(.strokeSubtle)
            .frame(height: Metrics.progressHeight)
            .overlay(alignment: .leading) {
                GeometryReader { geometry in
                    Rectangle().fill(.accentProgress).frame(width: geometry.size.width * fraction)
                }
            }
            .accessibilityElement()
            .accessibilityLabel("Playback position")
            .accessibilityValue(Text(verbatim: PlaybackRules.formatTime(player.elapsed)))
    }
}

/// Shows the traffic lights only while the pointer is over the window; the scene style hides the title.
private struct MiniWindowChrome: NSViewRepresentable {
    let showsButtons: Bool

    func makeNSView(context: Context) -> ChromeView { ChromeView() }

    func updateNSView(_ view: ChromeView, context: Context) {
        view.showsButtons = showsButtons
    }

    final class ChromeView: NSView {
        var showsButtons = false {
            didSet { apply() }
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            apply()
        }

        private func apply() {
            guard let window else { return }
            window.isMovableByWindowBackground = true
            for kind in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
                window.standardWindowButton(kind)?.isHidden = !showsButtons
            }
        }
    }
}

#if DEBUG
#Preview("Playing") {
    MiniPlayerView(nowPlaying: PreviewFixtures.nowPlaying(), showMainWindow: {})
}

#Preview("Not playing") {
    let player = PreviewPlayer()
    player.song = nil
    return MiniPlayerView(nowPlaying: PreviewFixtures.nowPlaying(player), showMainWindow: {})
}
#endif
