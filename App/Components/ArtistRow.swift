import InnerTube
import SwiftUI

struct ArtistRow: View {
    let artist: Artist

    @Environment(NavigationModel.self) private var navigation
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false
    @State private var popover: ItemPopover?
    @FocusState private var isFocused: Bool

    var body: some View {
        Button { navigation.push(.artist(channelId: artist.browseId)) } label: {
            HStack(spacing: Metrics.space12) {
                ArtworkImage(url: artist.thumbnailURL, width: Metrics.rowThumb, height: Metrics.rowThumb, isCircle: true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(artist.name)
                        .font(.rwTitle)
                        .foregroundStyle(.textPrimary)
                        .lineLimit(1)
                    if let subtitle = artist.subtitle {
                        Text(subtitle)
                            .font(.rwCaption)
                            .foregroundStyle(.textSecondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Metrics.space8)
            .frame(height: Metrics.rowHeightDetailed)
            .background(isHovering || isFocused ? Color.surfaceFill : .clear, in: RoundedRectangle(cornerRadius: Metrics.radiusThumb))
            .overlay { RoundedRectangle(cornerRadius: Metrics.radiusThumb).stroke(.strokeFocus, lineWidth: isFocused ? 2 : 0) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focused($isFocused)
        .onHover { isHovering = $0 }
        .animation(Motion.animation(Motion.hover, reduceMotion: reduceMotion), value: isHovering)
        .contextMenu { ItemMenu(item: .artist(artist), popover: $popover) }
        .itemPopover($popover)
        .accessibilityLabel([artist.name, artist.subtitle].compactMap { $0 }.joined(separator: ", "))
    }
}

#if DEBUG
#Preview("Artist rows") {
    VStack(spacing: 0) {
        ArtistRow(artist: Artist(browseId: "UC1", name: "Test Artist", subtitle: "1.2M subscribers"))
        ArtistRow(artist: Artist(browseId: "UC2", name: "Artist With A Very Long Name That Must Truncate In The Row", subtitle: "12 songs"))
        ArtistRow(artist: Artist(browseId: "UC3", name: "No Subtitle"))
    }
    .padding()
    .frame(width: 600)
    .environment(NavigationModel())
    .environment(PreviewFixtures.nowPlaying())
    .environment(ToastCenter())
    .background(.themeBase)
}
#endif
