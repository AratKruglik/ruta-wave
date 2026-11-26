import InnerTube
import SwiftUI

struct TimedLyricsView: View {
    let lyrics: TimedLyrics

    @Environment(NowPlayingModel.self) private var nowPlaying
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var currentIndex: Int?

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: Metrics.space24) {
                    LazyVStack(alignment: .leading, spacing: Metrics.space12) {
                        ForEach(Array(lyrics.lines.enumerated()), id: \.offset) { index, line in
                            lineButton(line, isCurrent: index == currentIndex)
                        }
                    }
                    if let source = lyrics.source {
                        Text(verbatim: source)
                            .font(.rwCaption)
                            .foregroundStyle(.textSecondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background { LyricsLineTracker(lyrics: lyrics, currentIndex: $currentIndex) }
            .onChange(of: currentIndex, initial: true) { _, index in
                guard let index else { return }
                withAnimation(Motion.animation(Motion.panel, reduceMotion: reduceMotion)) {
                    proxy.scrollTo(index, anchor: .center)
                }
            }
        }
    }

    private func lineButton(_ line: TimedLyrics.Line, isCurrent: Bool) -> some View {
        Button { nowPlaying.seek(to: line.start) } label: {
            Text(verbatim: line.text)
                .font(.rwBody)
                .fontWeight(isCurrent ? .semibold : .regular)
                .foregroundStyle(isCurrent ? .textPrimary : .textSecondary)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(nowPlaying.player.isAd)
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
    }
}

/// Reads `elapsed` here, not in the list, so the ticks re-run only this empty body.
private struct LyricsLineTracker: View {
    let lyrics: TimedLyrics
    @Binding var currentIndex: Int?
    @Environment(NowPlayingModel.self) private var nowPlaying

    var body: some View {
        Color.clear.onChange(of: nowPlaying.player.elapsed, initial: true) { _, elapsed in
            guard !nowPlaying.player.isAd else { return }
            let index = lyrics.lineIndex(at: elapsed)
            if index != currentIndex { currentIndex = index }
        }
    }
}

#if DEBUG
#Preview("Timed lyrics") {
    TimedLyricsView(
        lyrics: TimedLyrics(
            lines: (0..<8).map { TimedLyrics.Line(text: "Preview lyric line \($0 + 1)", start: Double($0) * 10 + 60) },
            source: "Source: Musixmatch")
    )
    .frame(width: 400, height: 500)
    .padding()
    .environment(PreviewFixtures.nowPlaying())
    .background(.themeBase)
}
#endif
