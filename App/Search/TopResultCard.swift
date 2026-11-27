import InnerTube
import SwiftUI

struct TopResultCard: View {
    let item: MusicItem

    @Environment(NavigationModel.self) private var navigation
    @Environment(NowPlayingModel.self) private var nowPlaying
    @State private var popover: ItemPopover?

    var body: some View {
        HStack(alignment: .center, spacing: Metrics.space24) {
            Button { activate(item, navigation: navigation, nowPlaying: nowPlaying) } label: {
                ArtworkImage(
                    url: item.thumbnailURL, width: Metrics.entityCover, height: Metrics.entityCover, isCircle: item.isArtist)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel([item.cardTitle, item.cardSubtitle].compactMap { $0 }.joined(separator: ", "))
            VStack(alignment: .leading, spacing: Metrics.space8) {
                Text(item.cardTitle)
                    .font(.rwShelfTitle)
                    .foregroundStyle(.textPrimary)
                    .lineLimit(2)
                    .onTapGesture { activate(item, navigation: navigation, nowPlaying: nowPlaying) }
                if let subtitle = item.cardSubtitle {
                    Text(subtitle)
                        .font(.rwBody)
                        .foregroundStyle(.textSecondary)
                        .lineLimit(2)
                }
                actions.padding(.top, Metrics.space8)
            }
            Spacer(minLength: 0)
        }
        .padding(Metrics.space16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.surfaceFill, in: RoundedRectangle(cornerRadius: Metrics.radiusTile))
        .contextMenu { ItemMenu(item: item, popover: $popover) }
        .itemPopover($popover)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var actions: some View {
        switch item {
        case .song:
            pills(primary: ("Play", { nowPlaying.play(item) }), secondary: ("Radio", { nowPlaying.startRadio(item) }))
        case .album, .playlist:
            pills(primary: ("Play", { nowPlaying.play(item) }), secondary: ("Shuffle", { nowPlaying.shuffle(item) }))
        case .artist:
            pills(primary: ("Shuffle", { nowPlaying.shuffle(item) }), secondary: ("Radio", { nowPlaying.startRadio(item) }))
        case .link:
            EmptyView()
        }
    }

    private func pills(primary: (LocalizedStringKey, () -> Void), secondary: (LocalizedStringKey, () -> Void)) -> some View {
        HStack(spacing: Metrics.space8) {
            Button(action: primary.1) { Text(primary.0) }
                .buttonStyle(PillButtonStyle(isProminent: true))
            Button(action: secondary.1) { Text(secondary.0) }
                .buttonStyle(PillButtonStyle())
        }
    }
}

#if DEBUG
#Preview("Top result") {
    VStack(spacing: Metrics.space16) {
        ForEach(Array(PreviewFixtures.cardItems.prefix(3).enumerated()), id: \.offset) { _, item in TopResultCard(item: item) }
    }
    .padding()
    .frame(width: 800)
    .environment(NavigationModel())
    .environment(PreviewFixtures.nowPlaying())
    .background(.themeBase)
}
#endif
