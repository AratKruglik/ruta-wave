import InnerTube
import SwiftUI

struct ArtistRow: View {
    let artist: Artist
    var isRanked = false

    @Environment(NavigationModel.self) private var navigation
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false
    @State private var popover: ItemPopover?
    @FocusState private var isFocused: Bool

    private func open() { navigation.push(.artist(channelId: artist.browseId)) }

    var body: some View {
        Button(action: open) {
            HStack(spacing: Metrics.space12) {
                if isRanked, let rank = artist.rank { rankColumn(rank) }
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
            .frame(height: isRanked ? Metrics.rowHeightNumbered : Metrics.rowHeightDetailed)
            .background(isHovering || isFocused ? Color.surfaceFill : .clear, in: RoundedRectangle(cornerRadius: Metrics.radiusThumb))
            .overlay { RoundedRectangle(cornerRadius: Metrics.radiusThumb).stroke(.strokeFocus, lineWidth: isFocused ? 2 : 0) }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focused($isFocused)
        .onReturn(open)
        .onHover { isHovering = $0 }
        .animation(Motion.animation(Motion.hover, reduceMotion: reduceMotion), value: isHovering)
        .contextMenu { ItemMenu(item: .artist(artist), popover: $popover) }
        .itemPopover($popover)
        .accessibilityLabel(accessibilityText)
    }

    private func rankColumn(_ rank: ChartRank) -> some View {
        HStack(spacing: Metrics.space4) {
            Text("\(rank.position)").monospacedDigit()
            if let trend = rank.trend {
                Image(systemName: trend.symbol)
                    .font(.rwIcon(Metrics.iconPin))
                    .foregroundStyle(trend.tint)
            }
        }
        .font(.rwTitle)
        .foregroundStyle(.textSecondary)
        .frame(width: 56, alignment: .leading)
        .accessibilityHidden(true)
    }

    private var accessibilityText: String {
        let rank = isRanked ? artist.rank : nil
        return [rank.map { String($0.position) }, artist.name, artist.subtitle, rank?.trend?.spokenLabel]
            .compactMap { $0 }.joined(separator: ", ")
    }
}

// shortcut: duplicates TrackRow's fileprivate trend mapping, move to a shared file when TrackRow is free to edit
extension ChartRank.Trend {
    fileprivate var symbol: String {
        switch self {
        case .up: "arrowtriangle.up.fill"
        case .down: "arrowtriangle.down.fill"
        case .neutral: "minus"
        }
    }

    fileprivate var tint: Color {
        switch self {
        case .up: .textPrimary
        case .down, .neutral: .textTertiary
        }
    }

    fileprivate var spokenLabel: String {
        switch self {
        case .up: String(localized: "Rising")
        case .down: String(localized: "Falling")
        case .neutral: String(localized: "No change")
        }
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
