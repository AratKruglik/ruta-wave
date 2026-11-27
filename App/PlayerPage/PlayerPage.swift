import InnerTube
import SwiftUI

struct PlayerPage: View {
    let onClose: () -> Void

    private enum Tab: CaseIterable {
        case upNext, lyrics, related

        var title: LocalizedStringKey {
            switch self {
            case .upNext: "Up next"
            case .lyrics: "Lyrics"
            case .related: "Related"
            }
        }
    }

    @Environment(NowPlayingModel.self) private var nowPlaying
    @Environment(\.themeBase) private var themeBase
    @State private var selection: Tab = .upNext
    /// Lives here so Esc can clear it before it closes the page.
    @State private var upNextSelection = TrackSelection()

    private var currentDetails: TrackDetails? {
        nowPlaying.details.flatMap { $0.videoId == nowPlaying.player.song?.videoId ? $0 : nil }
    }

    private var isLyricsUnavailable: Bool {
        currentDetails.map { $0.lyricsBrowseId == nil } ?? false
    }

    private func isDisabled(_ tab: Tab) -> Bool {
        switch tab {
        case .lyrics: isLyricsUnavailable
        case .upNext, .related: false
        }
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            HStack(alignment: .top, spacing: Metrics.space32) {
                VStack(spacing: Metrics.space16) {
                    artwork
                    titles
                }
                VStack(alignment: .leading, spacing: Metrics.space16) {
                    tabs
                    tabContent
                }
                .frame(minWidth: Metrics.playerPanelMinWidth, maxWidth: Metrics.playerPanelMaxWidth)
                .frame(maxHeight: .infinity)
                .layoutPriority(1)
            }
            .padding(.horizontal, Metrics.space32)
            .padding(.top, Metrics.space48)
            .padding(.bottom, Metrics.space16)
            Button(action: onClose) {
                Image(systemName: "chevron.down")
                    .font(.rwIcon(Metrics.iconBar))
                    .foregroundStyle(.textPrimary)
                    .frame(width: Metrics.hitTarget, height: Metrics.hitTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(IconButtonStyle())
            .cancelShortcut(if: upNextSelection.isEmpty)
            .help("Close player page")
            .accessibilityLabel("Close player page")
            .padding(Metrics.space12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(themeBase)
        .onReconnect {
            if nowPlaying.detailsFailed, let song = nowPlaying.player.song { Task { await nowPlaying.loadDetails(for: song) } }
        }
        .onChange(of: selection) { upNextSelection.clear() }
        .onChange(of: isLyricsUnavailable) {
            if isLyricsUnavailable, selection == .lyrics { selection = .upNext }
        }
    }

    @ViewBuilder
    private var tabContent: some View {
        switch selection {
        case .upNext:
            UpNextView(onClose: onClose, selection: $upNextSelection)
        case .lyrics:
            detailsGated(\.lyricsBrowseId, unavailable: "Lyrics aren't available") { LyricsView(browseId: $0) }
        case .related:
            detailsGated(\.relatedBrowseId, unavailable: "Nothing related for this track", isRelated: true) { RelatedView(browseId: $0) }
        }
    }

    @ViewBuilder
    private func detailsGated<Content: View>(
        _ browseId: KeyPath<TrackDetails, String?>, unavailable: LocalizedStringKey, isRelated: Bool = false,
        @ViewBuilder content: (String) -> Content
    ) -> some View {
        if let details = currentDetails {
            if let id = details[keyPath: browseId] { content(id) } else { PanelMessage(text: unavailable) }
        } else if nowPlaying.detailsFailed {
            let retry = { if let song = nowPlaying.player.song { Task { await nowPlaying.loadDetails(for: song) } } }
            if isRelated { RelatedErrorView(onRetry: retry) } else { PageErrorView(onRetry: retry) }
        } else {
            SkeletonRows(count: 6).accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private var titles: some View {
        let player = nowPlaying.player
        if player.isAd {
            Text("Ad").font(.rwShelfTitle).foregroundStyle(.textPrimary)
        } else if let song = player.song {
            VStack(spacing: Metrics.space4) {
                Text(verbatim: song.title).font(.rwShelfTitle).foregroundStyle(.textPrimary)
                Text(verbatim: song.artist).font(.rwBody).foregroundStyle(.textSecondary)
            }
            .lineLimit(2)
            .multilineTextAlignment(.center)
            .frame(maxWidth: Metrics.playerArtworkMax)
            .accessibilityElement(children: .combine)
        }
    }

    private var artwork: some View {
        GeometryReader { proxy in
            let isVideo = nowPlaying.details?.isVideo == true
            let side = max(min(proxy.size.width, proxy.size.height, Metrics.playerArtworkMax), 0)
            Button(action: nowPlaying.togglePlay) {
                ArtworkImage(
                    url: nowPlaying.player.song?.artworkURL, width: side, height: isVideo ? side * 9 / 16 : side,
                    cornerRadius: Metrics.radiusCover)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityLabel(nowPlaying.player.isPaused ? "Play" : "Pause")
        }
    }

    private var tabs: some View {
        let binding = Binding(get: { selection }, set: { if !isDisabled($0) { selection = $0 } })
        return Picker("Player page tabs", selection: binding) {
            ForEach(Tab.allCases, id: \.self) { tab in
                Text(tab.title).tag(tab).disabled(isDisabled(tab))
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }
}

#if DEBUG
#Preview("Player page") {
    PlayerPage(onClose: {})
        .frame(width: 1100, height: 700)
        .environment(NavigationModel())
        .environment(PreviewFixtures.nowPlaying())
        .environment(PreviewFixtures.trackTabs())
        .environment(ToastCenter())
        .background(.themeBase)
}

#Preview("Player page, minimum window") {
    PlayerPage(onClose: {})
        .frame(width: Metrics.minWindowWidth - Metrics.sidebarWidth, height: Metrics.minWindowHeight)
        .environment(NavigationModel())
        .environment(PreviewFixtures.nowPlaying())
        .environment(PreviewFixtures.trackTabs())
        .environment(ToastCenter())
        .background(.themeBase)
}
#endif
