#if DEBUG
import PlayerEngine
import SwiftUI

struct PlayerDebugView: View {
    let player: PlayerEngine
    @State private var videoId = ""
    @State private var playlistId = ""
    @State private var seekTime = 30.0
    @State private var skipDelta = 10.0
    @State private var volume = 0.5
    @State private var enqueueId = ""
    @State private var log: [String] = []

    var body: some View {
        HSplitView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    StateSummary(player: player)
                    CommandGrid(
                        player: player, videoId: $videoId, playlistId: $playlistId, seekTime: $seekTime,
                        skipDelta: $skipDelta, volume: $volume, enqueueId: $enqueueId)
                    QueueSection(player: player)
                }
                .padding()
            }
            .frame(minWidth: 380)
            EventLog(lines: log)
                .frame(minWidth: 320)
        }
        .frame(minWidth: 760, minHeight: 560)
        .task {
            for await event in player.events() {
                log.append(String(describing: event))
                if log.count > 500 { log.removeFirst(log.count - 500) }
            }
        }
    }
}

private struct StateSummary: View {
    let player: PlayerEngine

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
            row("Song", player.song.map { "\($0.title) - \($0.artist)" } ?? "none")
            row("Ready / paused / ad", "\(player.isReady) / \(player.isPaused) / \(player.isAd)")
            row("Elapsed", player.elapsed.formatted(.number.precision(.fractionLength(1))))
            row("Volume / muted", "\(player.volume.formatted(.number.precision(.fractionLength(2)))) / \(player.isMuted)")
            row("Like / repeat / shuffle", "\(player.like) / \(player.repeatMode) / \(player.isShuffled)")
        }
        .font(.callout)
        .accessibilityElement(children: .combine)
    }

    private func row(_ title: String, _ value: String) -> some View {
        GridRow {
            Text(title).foregroundStyle(.secondary)
            Text(value).textSelection(.enabled)
        }
    }
}

private struct CommandGrid: View {
    let player: PlayerEngine
    @Binding var videoId: String
    @Binding var playlistId: String
    @Binding var seekTime: Double
    @Binding var skipDelta: Double
    @Binding var volume: Double
    @Binding var enqueueId: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                TextField("videoId", text: $videoId).accessibilityLabel("Video ID")
                TextField("playlistId", text: $playlistId).accessibilityLabel("Playlist ID")
                button("Load") { .load(videoId: videoId, playlistId: playlistId.isEmpty ? nil : playlistId) }
            }
            HStack {
                button("Play") { .play }
                button("Pause") { .pause }
                button("Toggle") { .togglePlay }
                button("Previous") { .previous }
                button("Next") { .next }
            }
            HStack {
                button("Mute") { .toggleMute }
                button("Shuffle") { .toggleShuffle }
                button("Repeat") { .cycleRepeat }
                button("Like") { .setLike(.like) }
                button("Dislike") { .setLike(.dislike) }
                button("Unlike") { .setLike(.indifferent) }
            }
            HStack {
                Stepper("Seek to \(Int(seekTime)) s", value: $seekTime, in: 0...600, step: 10)
                button("Seek") { .seek(to: seekTime) }
            }
            HStack {
                Stepper("Skip by \(Int(skipDelta)) s", value: $skipDelta, in: -60...60, step: 5)
                button("Skip") { .skip(by: skipDelta) }
            }
            HStack {
                Slider(value: $volume, in: 0...1) { Text("Volume") }
                button("Set volume") { .setVolume(volume) }
            }
            HStack {
                TextField("videoId to enqueue", text: $enqueueId).accessibilityLabel("Video ID to enqueue")
                button("Play next") { .enqueue(videoId: enqueueId, playNext: true) }
                button("Add to end") { .enqueue(videoId: enqueueId, playNext: false) }
            }
        }
        .textFieldStyle(.roundedBorder)
    }

    private func button(_ title: String, command: @escaping () -> PlayerCommand) -> some View {
        Button(title) { player.send(command()) }
            .accessibilityLabel(title)
    }
}

private struct QueueSection: View {
    let player: PlayerEngine

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Queue (\(player.queue.count))").font(.headline)
            ForEach(Array(player.queue.enumerated()), id: \.offset) { index, item in
                HStack {
                    Text(item.isCurrent ? "▶︎ \(item.title)" : item.title).lineLimit(1)
                    Spacer()
                    Button("Play", systemImage: "play.fill") { player.send(.playQueueItem(index: index)) }
                    Button("Up", systemImage: "arrow.up") { player.send(.moveQueueItem(from: index, to: index - 1)) }
                        .disabled(index == 0)
                    Button("Down", systemImage: "arrow.down") { player.send(.moveQueueItem(from: index, to: index + 1)) }
                        .disabled(index == player.queue.count - 1)
                    Button("Remove", systemImage: "trash") { player.send(.removeQueueItem(index: index)) }
                        .disabled(item.isCurrent)
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .accessibilityElement(children: .contain)
            }
        }
    }
}

private struct EventLog: View {
    let lines: [String]

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                        Text(line).font(.caption.monospaced()).textSelection(.enabled).id(index)
                    }
                }
                .padding(8)
            }
            .onChange(of: lines.count) { proxy.scrollTo(lines.count - 1, anchor: .bottom) }
        }
        .accessibilityLabel("Event log")
    }
}
#endif
