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

extension View {
    /// Makes a track list selectable from the keyboard (⌘A, ⌫, Esc) and pins the selection bar above it.
    /// `onRemove` is set only where the rows belong to an own playlist.
    func trackSelection(_ selection: Binding<TrackSelection>, songs: [Song], onRemove: (([String]) -> Void)? = nil) -> some View {
        modifier(TrackSelectionModifier(selection: selection, songs: songs, onRemove: onRemove))
    }
}

private struct TrackSelectionModifier: ViewModifier {
    @Binding var selection: TrackSelection
    let songs: [Song]
    let onRemove: (([String]) -> Void)?

    @Environment(NowPlayingModel.self) private var nowPlaying
    @State private var popover: ItemPopover?

    private var order: [String] { songs.map(\.rowKey) }
    private var selectedSongs: [Song] { songs.filter { selection.contains($0.rowKey) } }

    func body(content: Content) -> some View {
        content
            .focusable()
            .focusEffectDisabled()
            .onDeleteCommand { remove() }
            .onExitCommand { selection.clear() }
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

    private func remove() {
        guard let onRemove, !selection.isEmpty else { return }
        onRemove(selection.ordered(in: order))
        selection.clear()
    }

    private var bar: some View {
        let queueable = selectedSongs.filter(\.isAvailable).map(\.videoId)
        return HStack(spacing: Metrics.space12) {
            Text("\(selection.count) selected")
                .font(.rwTitle)
                .foregroundStyle(.textPrimary)
            Spacer(minLength: 0)
            barButton("Play next", disabled: queueable.isEmpty) { nowPlaying.enqueue(queueable, playNext: true) }
            barButton("Add to queue", disabled: queueable.isEmpty) { nowPlaying.enqueue(queueable, playNext: false) }
            barButton("Add to playlist…", disabled: queueable.isEmpty) {
                popover = nowPlaying.isSignedIn
                    ? .addToPlaylist(videoIds: queueable) : .signIn(reason: String(localized: "Sign in to add songs to playlists"))
            }
            .itemPopover($popover)
            if onRemove != nil { barButton("Remove from playlist", disabled: false, action: remove) }
            barButton("Clear", disabled: false) { selection.clear() }
        }
        .padding(.horizontal, Metrics.space16)
        .frame(height: Metrics.topBarHeight - Metrics.space16)
        .glassSurface(in: Capsule())
        .padding(.horizontal, Metrics.space16)
        .padding(.vertical, Metrics.space8)
        .accessibilityElement(children: .contain)
    }

    private func barButton(_ title: LocalizedStringKey, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(.plain)
            .font(.rwButton)
            .foregroundStyle(disabled ? .textDisabled : .textPrimary)
            .disabled(disabled)
    }
}
