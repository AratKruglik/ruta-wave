import SwiftUI

struct ProgressLine: View {
    @Environment(NowPlayingModel.self) private var nowPlaying
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.themeBase) private var themeBase
    @State private var hoverX: CGFloat?
    @State private var dragFraction: Double?

    private static let hitHeight: CGFloat = 16
    private static let knobSize: CGFloat = 12
    private static let skipSeconds = 10.0

    var body: some View {
        let player = nowPlaying.player
        let duration = player.song?.duration ?? 0
        let playedFraction = duration > 0 ? min(max(player.elapsed / duration, 0), 1) : 0
        let fraction = dragFraction ?? playedFraction
        let isEnabled = duration > 0 && !player.isAd
        let isActive = isEnabled && (hoverX != nil || dragFraction != nil)

        GeometryReader { geometry in
            let width = geometry.size.width
            ZStack(alignment: .topLeading) {
                Rectangle()
                    .fill(.strokeSubtle)
                    .frame(height: isActive ? Metrics.progressHoverHeight : Metrics.progressHeight)
                Rectangle()
                    .fill(.accentProgress)
                    .frame(width: width * fraction, height: isActive ? Metrics.progressHoverHeight : Metrics.progressHeight)
                if isActive {
                    Circle()
                        .fill(.accentProgress)
                        .frame(width: Self.knobSize, height: Self.knobSize)
                        .offset(x: width * fraction - Self.knobSize / 2, y: (Metrics.progressHoverHeight - Self.knobSize) / 2)
                }
                if isActive, let hoverX {
                    Text(verbatim: PlaybackRules.formatTime(duration * min(max(hoverX / max(width, 1), 0), 1)))
                        .font(.rwCaption)
                        .monospacedDigit()
                        .foregroundStyle(.textPrimary)
                        .padding(.horizontal, Metrics.space8)
                        .padding(.vertical, Metrics.space4)
                        .background(.surfaceRaised, in: RoundedRectangle(cornerRadius: Metrics.radiusThumb))
                        .background(themeBase, in: RoundedRectangle(cornerRadius: Metrics.radiusThumb))
                        .fixedSize()
                        .offset(x: min(max(hoverX - 20, 0), max(width - 48, 0)), y: -28)
                        .allowsHitTesting(false)
                }
            }
            .frame(width: width, height: Self.hitHeight, alignment: .topLeading)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard isEnabled else { return }
                        hoverX = value.location.x
                        dragFraction = min(max(value.location.x / max(width, 1), 0), 1)
                    }
                    .onEnded { value in
                        guard isEnabled else { return }
                        nowPlaying.seek(to: duration * min(max(value.location.x / max(width, 1), 0), 1))
                        dragFraction = nil
                    }
            )
            .onContinuousHover { phase in
                switch phase {
                case .active(let location): hoverX = location.x
                case .ended: hoverX = nil
                }
            }
        }
        .frame(height: Self.hitHeight)
        .animation(Motion.animation(Motion.hover, reduceMotion: reduceMotion), value: isActive)
        .accessibilityElement()
        .accessibilityLabel("Playback position")
        .accessibilityValue(Text(verbatim: PlaybackRules.formatTime(player.elapsed)))
        .accessibilityAdjustableAction { direction in
            guard isEnabled else { return }
            nowPlaying.skip(by: direction == .increment ? Self.skipSeconds : -Self.skipSeconds)
        }
    }
}
