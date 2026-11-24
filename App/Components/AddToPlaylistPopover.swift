import InnerTube
import SwiftUI

/// The user's playlists with a search field. Playlists whose owner is not yet known are listed too:
/// the server refuses a non-owned add and the toast says so.
struct AddToPlaylistPopover: View {
    let videoIds: [String]
    let onDismiss: () -> Void

    @Environment(SidebarModel.self) private var sidebar
    @Environment(NavigationModel.self) private var navigation
    @State private var query = ""

    private var playlists: [Playlist] {
        guard case .loaded(let all) = sidebar.state else { return [] }
        let candidates = all.filter { $0.browseId != Route.likedMusicBrowseId && sidebar.ownership(of: $0.browseId) != false }
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return needle.isEmpty ? candidates : candidates.filter { $0.title.localizedCaseInsensitiveContains(needle) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.space8) {
            TextField("Search playlists", text: $query)
                .textFieldStyle(.roundedBorder)
                .font(.rwBody)
                .accessibilityLabel("Search playlists")
            Button {
                onDismiss()
                navigation.requestNewPlaylist(videoIds: videoIds)
            } label: {
                Label("New playlist…", systemImage: "plus")
                    .font(.rwTitle)
                    .foregroundStyle(.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(playlists, id: \.browseId) { playlist in
                        Button {
                            onDismiss()
                            Task { await sidebar.add(videoIds: videoIds, to: playlist.browseId) }
                        } label: {
                            Text(verbatim: playlist.title)
                                .font(.rwBody)
                                .foregroundStyle(.textPrimary)
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .frame(height: Metrics.hitTarget)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(maxHeight: 240)
        }
        .padding(Metrics.space12)
        .frame(width: 260)
        .noInitialPopoverFocus()
        .popoverSurface()
    }
}
