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

struct LyricsView: View {
    let browseId: String

    @Environment(TrackTabsModel.self) private var trackTabs
    @State private var attempt = 0

    private var phase: TrackTabsModel.Phase<Lyrics> {
        trackTabs.lyrics.flatMap { $0.id == browseId ? $0.phase : nil } ?? .loading
    }

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
        case .loaded(let lyrics): loaded(lyrics)
        case .empty: PanelMessage(text: "Lyrics aren't available")
        case .failed: PageErrorView { attempt += 1 }
        }
    }

    private func loaded(_ lyrics: Lyrics) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Metrics.space24) {
                Text(verbatim: lyrics.text)
                    .font(.rwBody)
                    .foregroundStyle(.textPrimary)
                    .textSelection(.enabled)
                if let source = lyrics.source {
                    Text(verbatim: source)
                        .font(.rwCaption)
                        .foregroundStyle(.textSecondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
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
        .background(.themeBase)
}
#endif
