import AppKit
import SwiftUI

struct VolumeControl: View {
    @Environment(NowPlayingModel.self) private var nowPlaying
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false

    private static let sliderWidth: CGFloat = 80
    private static let preciseScrollPerStep: CGFloat = 12

    let alwaysShowsSlider: Bool

    var body: some View {
        let player = nowPlaying.player
        let level = player.isMuted ? 0 : player.volume
        HStack(spacing: Metrics.space4) {
            if alwaysShowsSlider { slider(level: level) }
            Button(action: nowPlaying.toggleMute) {
                Label(player.isMuted ? "Unmute" : "Mute", systemImage: symbol(level: level))
                    .labelStyle(.iconOnly)
                    .contentTransition(.symbolEffect(.replace))
                    .font(.rwIcon(Metrics.iconBar))
                    .foregroundStyle(.textSecondary)
                    .frame(width: Metrics.hitTarget, height: Metrics.hitTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(player.isMuted ? "Unmute" : "Mute")
            .accessibilityValue(Text(level, format: .percent))
            .accessibilityAdjustableAction { nowPlaying.adjustVolume(steps: $0 == .increment ? 1 : -1) }
        }
        .overlay(alignment: .leading) {
            if !alwaysShowsSlider, isHovering {
                slider(level: level)
                    .padding(.horizontal, Metrics.space8)
                    .background(.themeBase, in: Capsule())
                    .alignmentGuide(.leading) { $0[.trailing] + Metrics.space4 }
                    .transition(.opacity)
            }
        }
        .animation(Motion.animation(Motion.hover, reduceMotion: reduceMotion), value: isHovering)
        .onHover { isHovering = $0 }
        .background(ScrollWheelReader(preciseScrollPerStep: Self.preciseScrollPerStep) { nowPlaying.adjustVolume(steps: $0) })
        .accessibilityElement(children: .contain)
    }

    private func slider(level: Double) -> some View {
        Slider(value: Binding(get: { level }, set: { nowPlaying.setVolume($0) }), in: 0...1)
            .frame(width: Self.sliderWidth)
            .tint(.accentProgress)
            .accessibilityLabel("Volume")
    }

    private func symbol(level: Double) -> String {
        switch level {
        case 0: "speaker.slash.fill"
        case ..<0.34: "speaker.wave.1.fill"
        case ..<0.67: "speaker.wave.2.fill"
        default: "speaker.wave.3.fill"
        }
    }
}

private struct ScrollWheelReader: NSViewRepresentable {
    let preciseScrollPerStep: CGFloat
    let onSteps: @MainActor (Int) -> Void

    func makeNSView(context: Context) -> ReaderView { ReaderView() }

    func updateNSView(_ view: ReaderView, context: Context) {
        view.preciseScrollPerStep = preciseScrollPerStep
        view.onSteps = onSteps
    }

    final class ReaderView: NSView {
        var preciseScrollPerStep: CGFloat = 12
        var onSteps: @MainActor (Int) -> Void = { _ in }
        private var monitor: Any?
        private var accumulated: CGFloat = 0

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                nonisolated(unsafe) let event = event
                let isConsumed = MainActor.assumeIsolated { self?.handle(event) ?? false }
                return isConsumed ? nil : event
            }
        }

        private func handle(_ event: NSEvent) -> Bool {
            guard event.window === window, event.scrollingDeltaY != 0,
                  bounds.contains(convert(event.locationInWindow, from: nil)) else { return false }
            let steps: Int
            if event.hasPreciseScrollingDeltas {
                accumulated += event.scrollingDeltaY
                steps = Int(accumulated / preciseScrollPerStep)
                accumulated -= CGFloat(steps) * preciseScrollPerStep
            } else {
                steps = event.scrollingDeltaY > 0 ? 1 : -1
            }
            if steps != 0 { onSteps(steps) }
            return true
        }
    }
}

#if DEBUG
#Preview {
    VStack {
        VolumeControl(alwaysShowsSlider: true)
        VolumeControl(alwaysShowsSlider: false)
    }
    .environment(PreviewFixtures.nowPlaying())
    .padding()
    .background(.themeBase)
}
#endif
