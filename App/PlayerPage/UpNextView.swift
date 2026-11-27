import InnerTube
import SwiftUI

struct UpNextView: View {
    let onClose: () -> Void
    @Binding var selection: TrackSelection

    @Environment(NowPlayingModel.self) private var nowPlaying
    @Environment(NavigationModel.self) private var navigation
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var popover: ItemPopover?

    // queueSongs formats durations as m:ss only; the player's own value goes through the shared formatter.
    private var songs: [Song] {
        zip(nowPlaying.queueSongs, nowPlaying.player.queue).map { song, item in
            Song(
                videoId: song.videoId, title: song.title, artists: song.artists, album: song.album,
                duration: PlaybackRules.formatTime(item.duration), thumbnailURL: song.thumbnailURL,
                playlistSetVideoId: song.playlistSetVideoId)
        }
    }
    private var currentIndex: Int? { nowPlaying.player.queue.firstIndex(where: \.isCurrent) }

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.space12) {
            header
            if let chips = nowPlaying.queueInfo?.chips, !chips.isEmpty {
                ChipRow(chips: chips.map { Chip(title: $0.title, isSelected: $0.isSelected, watchTarget: $0.target) }) { chip in
                    if let match = chips.first(where: { $0.title == chip.title }) { nowPlaying.selectChip(match) }
                }
            }
            queue
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: Metrics.space12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Playing from")
                    .font(.rwCaption)
                    .foregroundStyle(.textSecondary)
                source
            }
            Spacer(minLength: 0)
            saveMenu
        }
    }

    @ViewBuilder private var source: some View {
        if let name = nowPlaying.queueInfo?.playingFrom {
            if let browseId = sourceBrowseId {
                Button {
                    navigation.push(.playlist(browseId: browseId))
                    onClose()
                } label: {
                    Text(verbatim: name).font(.rwTitle).foregroundStyle(.accentLink).lineLimit(1)
                }
                .buttonStyle(.plain)
            } else {
                Text(verbatim: name).font(.rwTitle).foregroundStyle(.textPrimary).lineLimit(1)
            }
        } else if isLoadingDetails {
            Capsule().fill(.surfaceFill).frame(width: 160, height: 16)
                .accessibilityHidden(true)
        }
    }

    /// Radio ids (`RD…`) have no page of their own.
    private var sourceBrowseId: String? {
        guard let id = nowPlaying.queueInfo?.playlistId, id.hasPrefix("PL") || id.hasPrefix("OLAK") else { return nil }
        return "VL" + id
    }

    private var saveMenu: some View {
        Menu {
            Button("New playlist…") { save(newPlaylist: true) }
            Button("Add to playlist…") { save(newPlaylist: false) }
        } label: {
            InversePillLabel(title: "Save")
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
        .fixedSize()
        .itemPopover($popover)
        .help("Save the queue as a playlist")
        .accessibilityLabel("Save the queue as a playlist")
        .disabled(songs.isEmpty)
    }

    // The queue mirror holds at most the 500 rows the page reports, so a long radio saves only those.
    private func save(newPlaylist: Bool) {
        guard nowPlaying.isSignedIn else {
            popover = .signIn(reason: String(localized: "Sign in to add songs to playlists"))
            return
        }
        let ids = songs.filter(\.isAvailable).map(\.videoId)
        if newPlaylist { navigation.requestNewPlaylist(videoIds: ids) } else { popover = .addToPlaylist(videoIds: ids) }
    }

    private var isLoadingDetails: Bool {
        nowPlaying.queueInfo == nil && nowPlaying.player.song != nil && !nowPlaying.detailsFailed
    }

    @ViewBuilder private var queue: some View {
        if songs.isEmpty {
            if isLoadingDetails {
                SkeletonRows(count: 6)
            } else {
                PanelMessage(text: "Your queue is empty", message: "Play a song, or use Play next or Add to queue.")
            }
        } else {
            queueList
        }
    }

    private var queueList: some View {
        let songs = songs
        let order = songs.map(\.rowKey)
        return ScrollViewReader { proxy in
            List {
                ForEach(Array(songs.enumerated()), id: \.offset) { index, song in
                    TrackRow(
                        song: song, density: .compact, selection: $selection.row(for: song, order: order, songs: songs),
                        onPlay: { nowPlaying.jump(to: index) }, isCurrentRow: index == currentIndex, place: .queueRow, onAction: { handle($0, index: index) })
                        .id(index)
                        .listRowInsets(EdgeInsets())
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                }
                .onMove(perform: move)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .dropDestination(for: TrackDrag.self) { drags, _ in
                for drag in drags { nowPlaying.enqueue(drag, playNext: false) }
                return !drags.isEmpty
            }
            .trackSelection($selection, songs: songs, onRemove: { keys in
                nowPlaying.removeQueueItems(at: keys.compactMap(NowPlayingModel.queueIndex))
            }, onMove: moveSelected)
            .onChange(of: currentIndex) { _, index in
                guard let index else { return }
                if reduceMotion {
                    proxy.scrollTo(index, anchor: .center)
                } else {
                    withAnimation(.easeInOut(duration: Motion.panel)) { proxy.scrollTo(index, anchor: .center) }
                }
            }
            .onAppear { if let currentIndex { proxy.scrollTo(currentIndex, anchor: .center) } }
        }
    }

    private func handle(_ action: ItemAction, index: Int) {
        switch action {
        case .playNext: nowPlaying.playNext(queueIndex: index)
        case .removeFromQueue: nowPlaying.removeQueueItem(at: index)
        default: break
        }
    }

    private func moveSelected(from: Int, to: Int) {
        guard nowPlaying.canEditQueue else { return }
        nowPlaying.moveQueueItem(from: from, to: to)
        selection.shiftQueueKeys(by: from < to ? -1 : 1)
    }

    private func move(from source: IndexSet, to destination: Int) {
        guard let from = source.first else { return }
        nowPlaying.moveQueueItem(from: from, to: destination > from ? destination - 1 : destination)
    }
}
