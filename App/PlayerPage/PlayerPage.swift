import InnerTube
import SwiftUI

struct PlayerPage: View {
    let onClose: () -> Void

    private enum Tab: CaseIterable {
        case upNext, lyrics, comments, related

        var title: LocalizedStringKey {
            switch self {
            case .upNext: "Up next"
            case .lyrics: "Lyrics"
            case .comments: "Comments"
            case .related: "Related"
            }
        }
    }

    @Environment(NowPlayingModel.self) private var nowPlaying

    var body: some View {
        ZStack(alignment: .topLeading) {
            HStack(alignment: .top, spacing: Metrics.space32) {
                artwork
                VStack(alignment: .leading, spacing: Metrics.space16) {
                    tabs
                    UpNextView(onClose: onClose)
                }
                .frame(minWidth: Metrics.playerPanelMinWidth, maxWidth: Metrics.playerPanelMaxWidth)
                .frame(maxHeight: .infinity)
                .layoutPriority(1)
            }
            .padding(.horizontal, Metrics.space32)
            .padding(.top, Metrics.space48)
            .padding(.bottom, Metrics.playerBarHeight + Metrics.space16)
            Button(action: onClose) {
                Image(systemName: "chevron.down")
                    .font(.rwIcon(Metrics.iconBar))
                    .foregroundStyle(.textPrimary)
                    .frame(width: Metrics.hitTarget, height: Metrics.hitTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
            .help("Close player page")
            .accessibilityLabel("Close player page")
            .padding(Metrics.space12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.themeBase)
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
        HStack(spacing: Metrics.space24) {
            ForEach(Tab.allCases, id: \.self) { tab in
                Text(tab.title)
                    .font(.rwTab)
                    .foregroundStyle(tab == .upNext ? .textPrimary : .textDisabled)
                    .padding(.bottom, Metrics.space4)
                    .overlay(alignment: .bottom) {
                        if tab == .upNext { Rectangle().fill(.textPrimary).frame(height: 2) }
                    }
                    .accessibilityAddTraits(tab == .upNext ? .isSelected : [])
                    .accessibilityHint(tab == .upNext ? "" : String(localized: "Coming soon"))
            }
        }
    }
}

#if DEBUG
#Preview("Player page") {
    PlayerPage(onClose: {})
        .frame(width: 1100, height: 700)
        .environment(NavigationModel())
        .environment(PreviewFixtures.nowPlaying())
        .environment(ToastCenter())
        .background(.themeBase)
}
#endif
