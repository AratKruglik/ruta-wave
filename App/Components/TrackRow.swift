import AppKit
import InnerTube
import SwiftUI

/// A row's part in a multi-selection. A click with ⌘ or ⇧ selects instead of playing.
struct RowSelection {
    let isSelected: Bool
    let onSelect: (NSEvent.ModifierFlags) -> Void
    /// What a drag of this (selected) row carries: the whole selection.
    var selectedSongs: () -> [Song] = { [] }
}

struct TrackRow: View {
    enum Density { case compact, detailed, numbered }

    let song: Song
    let density: Density
    var selection: RowSelection?
    /// Replaces the chart rank in the leading column (an album's track number).
    var number: Int?
    var onPlay: (() -> Void)?
    /// Queue rows decide for themselves: the same video can appear twice.
    var isCurrentRow: Bool?
    var place: ItemPlace = .plain
    /// Set on own-playlist rows so a drop on another row of the same playlist reorders.
    var sourcePlaylistId: String?
    /// Handles the actions only the list can do: removals, and a queue row's Play next.
    var onAction: ((ItemAction) -> Void)?

    private enum Field: Hashable { case main, like, dislike, menu, select }

    @Environment(NavigationModel.self) private var navigation
    @Environment(NowPlayingModel.self) private var nowPlaying
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false
    @State private var popover: ItemPopover?
    @FocusState private var focus: Field?

    private var item: MusicItem { .song(song) }
    private var isCurrent: Bool { isCurrentRow ?? nowPlaying.isPlaying(item) }
    private var showsActions: Bool { isHovering || focus != nil || selection?.isSelected == true }
    private var rating: Rating? { nowPlaying.rowRatings[song.videoId] }

    private var height: CGFloat {
        switch density {
        case .compact: Metrics.rowHeightCompact
        case .detailed: Metrics.rowHeightDetailed
        case .numbered: Metrics.rowHeightNumbered
        }
    }

    private var thumbSize: CGFloat { density == .numbered ? Metrics.rowThumbCompact : Metrics.rowThumb }

    var body: some View {
        ZStack(alignment: .trailing) {
            Button(action: play) {
                HStack(spacing: Metrics.space12) {
                    if density == .numbered { rank }
                    ArtworkImage(
                        url: song.thumbnailURL, width: song.isVideo ? thumbSize * 16 / 9 : thumbSize, height: thumbSize,
                        cornerRadius: Metrics.radiusThumb)
                    titles
                    if density == .detailed, let album = song.album {
                        Text(album.name)
                            .font(.rwBody)
                            .foregroundStyle(.textSecondary)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if let duration = song.duration {
                        Text(duration)
                            .font(.rwBody)
                            .foregroundStyle(.textSecondary)
                            .monospacedDigit()
                    }
                }
                .padding(.horizontal, Metrics.space8)
                .frame(height: height)
                .background(
                    selection?.isSelected == true ? Color.surfaceRaised : (isHovering ? Color.surfaceFill : .clear),
                    in: RoundedRectangle(cornerRadius: Metrics.radiusThumb))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!song.isAvailable)
            .focused($focus, equals: .main)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityAddTraits(selection?.isSelected == true ? .isSelected : [])

            actions
                .opacity(showsActions ? 1 : 0)
                .padding(.trailing, Metrics.space8)
        }
        .opacity(song.isAvailable ? 1 : Metrics.unavailableOpacity)
        .onHover { isHovering = $0 }
        .animation(Motion.animation(Motion.hover, reduceMotion: reduceMotion), value: showsActions)
        .contextMenu { menu }
        .draggable(dragPayload())
        .itemPopover($popover)
    }

    private func dragPayload() -> TrackDrag {
        let songs = selection?.isSelected == true ? (selection?.selectedSongs()).flatMap { $0.isEmpty ? nil : $0 } ?? [song] : [song]
        return TrackDrag(
            videoIds: songs.map(\.videoId), sourcePlaylistId: sourcePlaylistId, setVideoIds: songs.compactMap(\.playlistSetVideoId))
    }

    @ViewBuilder private var menu: some View {
        ItemMenu(item: item, place: place, popover: $popover, onHostAction: onAction)
    }

    private func play() {
        if let selection {
            let flags = NSEvent.modifierFlags.intersection([.command, .shift])
            if !flags.isEmpty {
                selection.onSelect(flags)
                return
            }
        }
        if let onPlay { onPlay() } else { nowPlaying.play(item) }
    }

    private var titles: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: Metrics.space4) {
                Text(song.title)
                    .font(.rwTitle)
                    .foregroundStyle(isCurrent ? .accentLink : .textPrimary)
                    .lineLimit(1)
                if song.isExplicit { ExplicitBadge() }
            }
            if let line = artistLine {
                Text(line)
                    .font(.rwCaption)
                    .foregroundStyle(.textSecondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var artistLine: String? {
        let names = song.artists.map(\.name).joined(separator: ", ")
        return names.isEmpty ? song.subtitle : names
    }

    private var rank: some View {
        HStack(spacing: Metrics.space4) {
            if isCurrent {
                Image(systemName: "waveform")
                    .symbolEffect(.variableColor.iterative, isActive: !reduceMotion && !nowPlaying.player.isPaused)
            } else if let position = number ?? song.rank?.position {
                Text("\(position)").monospacedDigit()
            }
            if let trend = song.rank?.trend {
                Image(systemName: trend.symbol)
                    .font(.rwIcon(Metrics.iconPin))
                    .foregroundStyle(trend.tint)
                    .accessibilityLabel(trend.label)
            }
        }
        .font(.rwTitle)
        .foregroundStyle(.textSecondary)
        .frame(width: 56, alignment: .leading)
    }

    private var actions: some View {
        HStack(spacing: Metrics.space4) {
            if let selection {
                actionButton(selection.isSelected ? "checkmark.square.fill" : "square", label: "Select", field: .select) {
                    selection.onSelect(.command)
                }
            }
            actionButton(rating == .like ? "hand.thumbsup.fill" : "hand.thumbsup", label: "Like", field: .like) { rate(.like) }
            actionButton(rating == .dislike ? "hand.thumbsdown.fill" : "hand.thumbsdown", label: "Dislike", field: .dislike) { rate(.dislike) }
            Menu { menu } label: {
                Image(systemName: "ellipsis")
                    .font(.rwIcon(Metrics.iconRow))
                    .foregroundStyle(.textPrimary)
                    .frame(width: Metrics.hitTarget, height: Metrics.hitTarget)
            }
            .menuStyle(.button)
            .menuIndicator(.hidden)
            .buttonStyle(.plain)
            .focused($focus, equals: .menu)
            .help("More actions")
            .accessibilityLabel("More actions")
        }
        .padding(.leading, Metrics.space8)
        .background(.themeBase.opacity(0.9), in: Capsule())
    }

    private func actionButton(_ symbol: String, label: LocalizedStringKey, field: Field, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.rwIcon(Metrics.iconRow))
                .foregroundStyle(.textPrimary)
                .frame(width: Metrics.hitTarget, height: Metrics.hitTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focused($focus, equals: field)
        .help(label)
        .accessibilityLabel(label)
    }

    private func rate(_ target: Rating) {
        guard nowPlaying.isSignedIn else {
            popover = .signIn(reason: String(localized: target == .like ? "Sign in to like songs" : "Sign in to dislike songs"))
            return
        }
        nowPlaying.rate(videoId: song.videoId, rating == target ? .indifferent : target)
    }

    private var accessibilityLabel: String {
        var parts = [number.map(String.init), song.title, artistLine, song.album?.name, song.duration]
        if isCurrent { parts.append(String(localized: "Now playing")) }
        if !song.isAvailable { parts.append(String(localized: "Unavailable")) }
        return parts.compactMap { $0 }.joined(separator: ", ")
    }
}

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

    fileprivate var label: LocalizedStringKey {
        switch self {
        case .up: "Rising"
        case .down: "Falling"
        case .neutral: "No change"
        }
    }
}

#if DEBUG
#Preview("Rows") {
    VStack(spacing: 0) {
        ForEach(Array(PreviewFixtures.songs.enumerated()), id: \.offset) { index, song in
            TrackRow(song: song, density: [.compact, .detailed, .numbered][index % 3], selection: RowSelection(isSelected: index == 1) { _ in })
        }
    }
    .padding()
    .frame(width: 600)
    .environment(NavigationModel())
    .environment(PreviewFixtures.nowPlaying())
    .environment(ToastCenter())
    .background(.themeBase)
}
#endif
