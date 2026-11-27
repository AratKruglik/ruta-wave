import InnerTube
import SwiftUI

struct TabLoadKey: Hashable {
    let id: String
    let generation: Int
    let attempt: Int
}

struct PanelMessage: View {
    let text: LocalizedStringKey
    var message: LocalizedStringKey?

    var body: some View {
        VStack(spacing: Metrics.space8) {
            Text(text)
                .font(.rwTitle)
                .foregroundStyle(.textSecondary)
            if let message {
                Text(message)
                    .font(.rwBody)
                    .foregroundStyle(.textTertiary)
            }
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }
}

enum LyricsStyle {
    static let size: CGFloat = 18
    static let currentSize: CGFloat = 20
    static let lineSpacing: CGFloat = 8
    static let fadeHeight = Metrics.space48
}

extension View {
    /// Fades the scroll area out at the bottom so the last line never meets a hard edge above the player bar.
    func lyricsBottomFade() -> some View {
        contentMargins(.bottom, LyricsStyle.fadeHeight + Metrics.space24, for: .scrollContent)
            .mask {
                VStack(spacing: 0) {
                    Color.black
                    LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                        .frame(height: LyricsStyle.fadeHeight)
                }
            }
    }
}

struct LyricsView: View {
    let browseId: String

    @Environment(TrackTabsModel.self) private var trackTabs
    @State private var attempt = 0

    private var phase: TrackTabsModel.Phase<TrackTabsModel.LyricsContent> { trackTabs.lyricsPhase(browseId) }

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .task(id: TabLoadKey(id: browseId, generation: trackTabs.generation, attempt: attempt)) {
                await trackTabs.loadLyrics(browseId)
            }
            .onReconnect { if case .failed = phase { attempt += 1 } }
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .loading: skeleton
        case .loaded(let content): loaded(content)
        case .empty: PanelMessage(text: "Lyrics aren't available")
        case .failed: PageErrorView { attempt += 1 }
        }
    }

    @ViewBuilder
    private func loaded(_ content: TrackTabsModel.LyricsContent) -> some View {
        if let timed = content.timed {
            TimedLyricsView(lyrics: timed).id(browseId)
        } else if let plain = content.plain {
            plainLyrics(plain)
        }
    }

    private func plainLyrics(_ lyrics: Lyrics) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Metrics.space24) {
                Text(verbatim: lyrics.text)
                    .font(.system(size: LyricsStyle.size))
                    .lineSpacing(LyricsStyle.lineSpacing)
                    .foregroundStyle(.textPrimary)
                    .textSelection(.enabled)
                if let source = lyrics.source {
                    Text(verbatim: source)
                        .font(.rwCaption)
                        .foregroundStyle(.textSecondary)
                        .textSelection(.enabled)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .lyricsBottomFade()
    }

    private var skeleton: some View {
        VStack(alignment: .leading, spacing: Metrics.space12) {
            ForEach([260, 200, 240, 160, 220, 180], id: \.self) { width in
                Capsule().fill(.surfaceFill).frame(width: CGFloat(width), height: 12)
            }
        }
        .accessibilityHidden(true)
    }
}

#if DEBUG
#Preview("Lyrics") {
    LyricsView(browseId: "MPLYtpreview")
        .frame(width: 400, height: 500)
        .padding()
        .environment(PreviewFixtures.trackTabs())
        .environment(PreviewFixtures.nowPlaying())
        .background(.themeBase)
}
#endif
