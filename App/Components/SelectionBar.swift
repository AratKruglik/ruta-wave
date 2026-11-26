import InnerTube
import SwiftUI

extension Binding where Value == TrackSelection {
    /// The row's selection state. ⇧ extends from the anchor over `order`; anything else toggles.
    func row(for song: Song, order: [String], songs: [Song] = []) -> RowSelection {
        let selection = wrappedValue
        return RowSelection(
            isSelected: selection.contains(song.rowKey),
            onSelect: { flags in
                if flags.contains(.shift) {
                    wrappedValue.extend(to: song.rowKey, in: order)
                } else {
                    wrappedValue.toggle(song.rowKey)
                }
            },
            selectedSongs: { songs.filter { selection.contains($0.rowKey) } })
    }
}

/// Moves the focused list's selected rows one step. Published only while a reorderable selection exists.
struct ReorderAction {
    let up: () -> Void
    let down: () -> Void
}

extension FocusedValues {
    @Entry var reorderSelection: ReorderAction?
}

extension View {
    /// Makes a track list selectable from the keyboard (⌘A, ⌫, Esc) and pins the selection bar above it.
    /// `onRemove` is set only where the rows belong to an own playlist; `onMove(from, to)` only where they can be reordered.
    func trackSelection(
        _ selection: Binding<TrackSelection>, songs: [Song], onRemove: (([String]) -> Void)? = nil,
        onMove: ((_ from: Int, _ to: Int) -> Void)? = nil
    ) -> some View {
        modifier(TrackSelectionModifier(selection: selection, songs: songs, onRemove: onRemove, onMove: onMove))
    }
}

private struct TrackSelectionModifier: ViewModifier {
    @Binding var selection: TrackSelection
    let songs: [Song]
    let onRemove: (([String]) -> Void)?
    let onMove: ((_ from: Int, _ to: Int) -> Void)?

    @Environment(NowPlayingModel.self) private var nowPlaying
    @Environment(NavigationModel.self) private var navigation
    @State private var popover: ItemPopover?
    @State private var availableWidth: CGFloat = 0
    @State private var fullWidth: CGFloat = 0

    /// Labels drop to icons when the full bar does not fit, as in the narrow Up Next panel.
    private var isCompact: Bool { fullWidth > availableWidth }

    private var order: [String] { songs.map(\.rowKey) }
    private var selectedSongs: [Song] { songs.filter { selection.contains($0.rowKey) } }

    func body(content: Content) -> some View {
        content
            .focusable()
            .focusEffectDisabled()
            .onDeleteCommand { remove() }
            .onExitCommand { selection.clear() }
            .onKeyPress(.space) {
                nowPlaying.togglePlay()
                return .handled
            }
            .focusedValue(\.reorderSelection, reorderAction)
            .onKeyPress("a", phases: .down) { press in
                guard press.modifiers == .command, !songs.isEmpty else { return .ignored }
                selection.selectAll(order)
                return .handled
            }
            .onChange(of: order) { selection.retain(keys: order) }
            .safeAreaInset(edge: .top, spacing: 0) {
                if !selection.isEmpty { bar }
            }
    }

    private var reorderAction: ReorderAction? {
        guard onMove != nil, !selection.isEmpty else { return nil }
        return ReorderAction(up: { moveSelection(up: true) }, down: { moveSelection(up: false) })
    }

    private func moveSelection(up: Bool) {
        guard let move = selection.blockMove(in: order, up: up) else { return }
        onMove?(move.from, move.to)
    }

    private func remove() {
        guard let onRemove, !selection.isEmpty else { return }
        onRemove(selection.ordered(in: order))
        selection.clear()
    }

    private var bar: some View {
        let queueable = selectedSongs.filter(\.isAvailable).map(\.videoId)
        return HStack(spacing: Metrics.space12) {
            countLabel
            Spacer(minLength: 0)
            barButton(.playNext, help: "Play next", disabled: queueable.isEmpty) {
                nowPlaying.enqueue(queueable, playNext: true)
            }
            barButton(.queue, help: "Add to queue", disabled: queueable.isEmpty) {
                nowPlaying.enqueue(queueable, playNext: false)
            }
            barButton(.playlist, help: "Add to playlist…", disabled: queueable.isEmpty) {
                popover = nowPlaying.isSignedIn
                    ? .addToPlaylist(videoIds: queueable) : .signIn(reason: String(localized: "Sign in to add songs to playlists"))
            }
            .itemPopover($popover)
            if onRemove != nil {
                barButton(.remove, help: "Remove from playlist", disabled: false, action: remove)
            }
            barButton(.clear, help: "Clear", disabled: false) { selection.clear() }
                .cancelShortcut(if: !navigation.isSearchFocused)
        }
        .frame(maxWidth: .infinity)
        .onGeometryChange(for: CGFloat.self, of: \.size.width) { availableWidth = $0 }
        .background { fullWidthProbe }
        .padding(.horizontal, Metrics.space16)
        .frame(height: Metrics.topBarHeight - Metrics.space16)
        .glassSurface(in: Capsule())
        .padding(.horizontal, Metrics.space16)
        .padding(.vertical, Metrics.space8)
        .accessibilityElement(children: .contain)
    }

    private var countLabel: some View {
        Text("\(selection.count) selected")
            .font(.rwTitle)
            .foregroundStyle(.textPrimary)
            .lineLimit(1)
    }

    /// The bar's natural width with full labels; never drawn, only measured.
    private var fullWidthProbe: some View {
        HStack(spacing: Metrics.space12) {
            countLabel
            ForEach(BarLabel.shown(includingRemove: onRemove != nil), id: \.systemImage) { label($0, compact: false) }
        }
        .fixedSize()
        .hidden()
        .accessibilityHidden(true)
        .onGeometryChange(for: CGFloat.self, of: \.size.width) { fullWidth = $0 }
    }

    private func label(_ label: BarLabel, compact: Bool) -> some View {
        Label {
            Text(label.title)
        } icon: {
            Image(systemName: label.systemImage)
        }
        .labelStyle(BarLabelStyle(compact: compact))
        .font(.rwButton)
        .lineLimit(1)
        .fixedSize()
    }

    private func barButton(
        _ barLabel: BarLabel, help: LocalizedStringKey, disabled: Bool, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) { label(barLabel, compact: isCompact) }
            .buttonStyle(.plain)
            .foregroundStyle(disabled ? .textDisabled : .textPrimary)
            .disabled(disabled)
            .help(help)
            .accessibilityLabel(help)
    }
}

private struct BarLabel {
    let title: LocalizedStringResource
    let systemImage: String

    static let playNext = BarLabel(
        title: LocalizedStringResource(
            "Play next (short)", defaultValue: "Next", comment: "Selection bar: play the selected songs next"),
        systemImage: "text.line.first.and.arrowtriangle.forward")
    static let queue = BarLabel(title: "Queue", systemImage: "text.line.last.and.arrowtriangle.forward")
    static let playlist = BarLabel(title: "Playlist", systemImage: "text.badge.plus")
    static let remove = BarLabel(title: "Remove", systemImage: "minus.circle")
    static let clear = BarLabel(title: "Clear", systemImage: "xmark")

    static func shown(includingRemove: Bool) -> [BarLabel] {
        includingRemove ? [playNext, queue, playlist, remove, clear] : [playNext, queue, playlist, clear]
    }
}

private struct BarLabelStyle: LabelStyle {
    let compact: Bool

    func makeBody(configuration: Configuration) -> some View {
        if compact {
            configuration.icon
        } else {
            HStack(spacing: Metrics.space4) {
                configuration.icon
                configuration.title
            }
        }
    }
}
