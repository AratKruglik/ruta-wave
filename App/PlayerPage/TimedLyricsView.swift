import AppSettings
import InnerTube
import SwiftUI

struct TimedLyricsView: View {
    let lyrics: TimedLyrics

    @Environment(NowPlayingModel.self) private var nowPlaying
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var currentIndex: Int?
    @State private var karaoke = Preferences().karaokeEnabled

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.space12) {
            header
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: Metrics.space24) {
                        LazyVStack(alignment: .leading, spacing: Metrics.space12) {
                            ForEach(Array(lyrics.lines.enumerated()), id: \.offset) { index, line in
                                row(line, isCurrent: index == currentIndex)
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
                .background { LyricsLineTracker(lyrics: lyrics, karaoke: karaoke, currentIndex: $currentIndex) }
                .onChange(of: currentIndex, initial: true) { _, index in
                    guard let index else { return }
                    withAnimation(Motion.animation(Motion.panel, reduceMotion: reduceMotion)) {
                        proxy.scrollTo(index, anchor: .center)
                    }
                }
            }
        }
    }

    private var header: some View {
        HStack(spacing: Metrics.space12) {
            Toggle("Karaoke", isOn: $karaoke)
                .toggleStyle(.switch)
                .controlSize(.small)
                .onChange(of: karaoke) { _, isOn in Preferences().karaokeEnabled = isOn }
            if karaoke && lyrics.timing == .estimated {
                Text("Estimated timing")
                    .font(.rwCaption)
                    .foregroundStyle(.textTertiary)
                    .help("Word timing is estimated from line timing")
            }
        }
    }

    @ViewBuilder
    private func row(_ line: TimedLyrics.Line, isCurrent: Bool) -> some View {
        if karaoke && !line.words.isEmpty {
            if isCurrent {
                ExtrapolatedClock(karaoke: karaoke) { time in karaokeLine(line, isCurrent: true, time: time) }
            } else {
                karaokeLine(line, isCurrent: false, time: nil)
            }
        } else {
            lineButton(line, isCurrent: isCurrent)
        }
    }

    private func karaokeLine(_ line: TimedLyrics.Line, isCurrent: Bool, time: TimeInterval?) -> some View {
        WordFlow {
            ForEach(Array(line.words.enumerated()), id: \.offset) { _, word in
                KaraokeWord(word: word, progress: progress(of: word, at: time))
                    .contentShape(Rectangle())
                    .onTapGesture { seek(to: word.start) }
            }
        }
        .font(.rwBody)
        .fontWeight(isCurrent ? .semibold : .regular)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture { seek(to: line.start) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: line.text))
        .accessibilityAddTraits(isCurrent ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction { seek(to: line.start) }
    }

    private func progress(of word: TimedLyrics.Word, at time: TimeInterval?) -> Double {
        guard let time else { return 0 }
        let value = word.progress(at: time)
        return reduceMotion ? value.rounded(.up) : value
    }

    private func seek(to time: TimeInterval) {
        guard !nowPlaying.player.isAd else { return }
        nowPlaying.seek(to: time)
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

private struct KaraokeWord: View {
    let word: TimedLyrics.Word
    let progress: Double

    var body: some View {
        Text(verbatim: word.text)
            .foregroundStyle(.textSecondary)
            .overlay(alignment: .leading) {
                Text(verbatim: word.text)
                    .foregroundStyle(.textPrimary)
                    .mask(alignment: .leading) { Rectangle().scaleEffect(x: progress, anchor: .leading) }
            }
    }
}

/// Wraps its subviews left to right; a word wider than the row wraps inside itself.
private struct WordFlow: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(width: proposal.width ?? .infinity, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let placed = arrange(width: bounds.width, subviews: subviews)
        for (subview, frame) in zip(subviews, placed.frames) {
            subview.place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY), proposal: ProposedViewSize(frame.size))
        }
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> (frames: [CGRect], size: CGSize) {
        var frames: [CGRect] = []
        var origin = CGPoint.zero
        var rowHeight: CGFloat = 0
        var usedWidth: CGFloat = 0
        for subview in subviews {
            var size = subview.sizeThatFits(.unspecified)
            if origin.x > 0, origin.x + size.width > width {
                origin = CGPoint(x: 0, y: origin.y + rowHeight)
                rowHeight = 0
            }
            if size.width > width { size = subview.sizeThatFits(ProposedViewSize(width: width, height: nil)) }
            frames.append(CGRect(origin: origin, size: size))
            origin.x += size.width + Metrics.space4
            rowHeight = max(rowHeight, size.height)
            usedWidth = max(usedWidth, origin.x - Metrics.space4)
        }
        return (frames, CGSize(width: usedWidth, height: origin.y + rowHeight))
    }
}

/// Playback time extended past the last `elapsed` tick; runs a display-linked timeline only while karaoke is on and the track plays.
private struct ExtrapolatedClock<Content: View>: View {
    let karaoke: Bool
    @ViewBuilder let content: (TimeInterval) -> Content
    @Environment(NowPlayingModel.self) private var nowPlaying
    @State private var anchor: (elapsed: TimeInterval, date: Date) = (0, .now)

    var body: some View {
        let player = nowPlaying.player
        let running = karaoke && !player.isPaused && !player.isAd && !player.isBuffering
        TimelineView(.animation(paused: !running)) { context in
            content(PlaybackRules.extrapolatedElapsed(anchor.elapsed, since: anchor.date, now: context.date, isRunning: running))
        }
        .onChange(of: player.elapsed, initial: true) { _, elapsed in
            if !player.isAd { anchor = (elapsed, .now) }
        }
        .onChange(of: player.isPaused) { _, _ in
            if !player.isAd { anchor = (player.elapsed, .now) }
        }
    }
}

/// Reads `elapsed` here, not in the list, so the ticks re-run only this empty body.
private struct LyricsLineTracker: View {
    let lyrics: TimedLyrics
    let karaoke: Bool
    @Binding var currentIndex: Int?

    var body: some View {
        ExtrapolatedClock(karaoke: karaoke) { time in
            Color.clear.onChange(of: lyrics.lineIndex(at: time), initial: true) { _, index in
                if index != currentIndex { currentIndex = index }
            }
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
