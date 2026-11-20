import SwiftUI

struct TimeLabel: View {
    @Environment(NowPlayingModel.self) private var nowPlaying

    var body: some View {
        let elapsed = nowPlaying.player.elapsed
        let duration = nowPlaying.player.song?.duration ?? 0
        let text = "\(PlaybackRules.formatTime(elapsed)) / "
            + (nowPlaying.timeShowsRemaining
                ? PlaybackRules.formatRemaining(elapsed, duration: duration) : PlaybackRules.formatTime(duration))
        Button { nowPlaying.timeShowsRemaining.toggle() } label: {
            Text(verbatim: text)
                .font(.rwCaption)
                .monospacedDigit()
                .foregroundStyle(.textSecondary)
                .lineLimit(1)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Show remaining time")
        .accessibilityLabel("Playback time")
        .accessibilityValue(Text(verbatim: text))
    }
}
