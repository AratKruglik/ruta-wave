import InnerTube
import SwiftUI

struct SidebarView: View {
    let selectedSection: SidebarSection
    let selectedPlaylistId: String?
    let isSignedIn: Bool
    let model: SidebarModel
    let onSelectSection: (SidebarSection) -> Void
    let onSelectPlaylist: (String) -> Void
    let onNewPlaylist: () -> Void
    /// The playlist's browse id, and whether it was deleted (otherwise removed from the library).
    let onPlaylistRemoved: (String, Bool) -> Void
    let onRetry: () -> Void
    let onSignIn: () -> Void

    @Environment(ToastCenter.self) private var toasts
    @State private var pendingDelete: Playlist?

    var body: some View {
        ScrollView {
            LazyVStack(spacing: Metrics.space4) {
                ForEach(SidebarSection.allCases, id: \.self) { section in
                    NavItem(section: section, isSelected: selectedPlaylistId == nil && selectedSection == section) {
                        onSelectSection(section)
                    }
                }
                Divider()
                    .overlay(.strokeSubtle)
                    .padding(.vertical, Metrics.space16)
                NewPlaylistButton(isSignedIn: isSignedIn, onNewPlaylist: onNewPlaylist, onSignIn: onSignIn)
                if isSignedIn {
                    PlaylistList(
                        model: model, selectedId: selectedPlaylistId, onSelect: onSelectPlaylist, onRetry: onRetry,
                        onRequestDelete: { pendingDelete = $0 }, onRemove: removeFromLibrary, onResolve: resolveAndAct)
                } else {
                    GuestCard(onSignIn: onSignIn)
                }
            }
            .padding(.horizontal, Metrics.space12)
            .padding(.top, Metrics.space8)
        }
        .contentMargins(.bottom, Metrics.contentBottomMargin, for: .scrollContent)
        .confirmationDialog(
            "Delete this playlist?", isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            presenting: pendingDelete
        ) { playlist in
            Button("Delete", role: .destructive) { delete(playlist) }
            Button("Cancel", role: .cancel) {}
        } message: { playlist in
            Text("“\(playlist.title)” will be deleted for good.")
        }
    }

    private func delete(_ playlist: Playlist) {
        Task {
            if await model.delete(playlist.browseId) { onPlaylistRemoved(playlist.browseId, true) }
        }
    }

    private func removeFromLibrary(_ playlist: Playlist) {
        Task {
            if await model.removeFromLibrary(playlist.browseId) { onPlaylistRemoved(playlist.browseId, false) }
        }
    }

    /// The keyboard and VoiceOver path, and a click that beats the hover prefetch: ask, then take the matching action.
    private func resolveAndAct(_ playlist: Playlist) {
        Task {
            await model.resolveOwnership(playlist.browseId)
            switch model.ownership(of: playlist.browseId) {
            case true?: pendingDelete = playlist
            case false?: removeFromLibrary(playlist)
            case nil: toasts.show("Couldn't update your library")
            }
        }
    }
}

private struct NewPlaylistButton: View {
    let isSignedIn: Bool
    let onNewPlaylist: () -> Void
    let onSignIn: () -> Void

    @State private var isPromptPresented = false

    var body: some View {
        Button {
            if isSignedIn { onNewPlaylist() } else { isPromptPresented = true }
        } label: {
            HStack(spacing: Metrics.space8) {
                Image(systemName: "plus").font(.rwIcon(Metrics.iconRow))
                Text("New playlist")
                    .font(.rwButton)
                    .lineLimit(1)
            }
            .foregroundStyle(.textPrimary)
            .padding(.horizontal, Metrics.space16)
            .frame(height: Metrics.pillHeight)
            .background(.surfaceFill, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Metrics.space12)
        .help("New playlist")
        .accessibilityLabel("New playlist")
        .guestPrompt(isPresented: $isPromptPresented, reason: "Sign in to create playlists", onSignIn: onSignIn)
    }
}

private struct NavItem: View {
    let section: SidebarSection
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Metrics.space12) {
                Image(systemName: isSelected ? section.filledSymbol : section.symbol)
                    .font(.rwIcon(Metrics.iconSidebar - 4))
                    .frame(width: Metrics.iconSidebar)
                Text(section.title)
                    .font(isSelected ? .rwNavSelected : .rwNav)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .foregroundStyle(.textPrimary)
            .padding(.horizontal, Metrics.space12)
            .frame(height: Metrics.sidebarItemHeight)
            .background(isSelected ? .surfaceFill : Color.clear, in: RoundedRectangle(cornerRadius: Metrics.radiusCard))
            .contentShape(RoundedRectangle(cornerRadius: Metrics.radiusCard))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct PlaylistList: View {
    let model: SidebarModel
    let selectedId: String?
    let onSelect: (String) -> Void
    let onRetry: () -> Void
    let onRequestDelete: (Playlist) -> Void
    let onRemove: (Playlist) -> Void
    let onResolve: (Playlist) -> Void

    @Environment(NowPlayingModel.self) private var nowPlaying
    @Environment(ToastCenter.self) private var toasts

    var body: some View {
        switch model.state {
        case .loading:
            ForEach(0..<3, id: \.self) { _ in
                PlaylistRow(title: "Playlist title", subtitle: .text("Owner"), isSelected: false, action: {})
                    .redacted(reason: .placeholder)
                    .accessibilityHidden(true)
            }
        case .loaded(let playlists):
            ForEach(playlists, id: \.browseId) { playlist in
                PlaylistRow(
                    title: playlist.browseId == Route.likedMusicBrowseId ? String(localized: "Liked music") : playlist.title,
                    subtitle: subtitle(for: playlist), isSelected: selectedId == playlist.browseId,
                    onPrefetch: playlist.browseId == Route.likedMusicBrowseId ? nil : { await model.resolveOwnership(playlist.browseId) }
                ) { onSelect(playlist.browseId) }
                .contextMenu { menu(for: playlist) }
            }
        case .failed:
            VStack(alignment: .leading, spacing: Metrics.space8) {
                Text("Couldn't load playlists")
                    .font(.rwCaption)
                    .foregroundStyle(.textSecondary)
                Button("Retry", action: onRetry)
                    .buttonStyle(.plain)
                    .font(.rwCaption)
                    .foregroundStyle(.accentLink)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Metrics.space12)
        }
    }

    @ViewBuilder
    private func menu(for playlist: Playlist) -> some View {
        Button("Play") { nowPlaying.play(.playlist(playlist)) }
        if let url = PlaylistLink.shareURL(browseId: playlist.browseId) {
            Button("Copy link") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(url.absoluteString, forType: .string)
                toasts.show("Link copied")
            }
            ShareLink(item: url)
        }
        if playlist.browseId != Route.likedMusicBrowseId {
            Divider()
            switch model.ownership(of: playlist.browseId) {
            case true?: Button("Delete playlist…", role: .destructive) { onRequestDelete(playlist) }
            case false?: Button("Remove from library") { onRemove(playlist) }
            case nil: Button("Remove from library or delete…") { onResolve(playlist) }
            }
        }
    }

    private func subtitle(for playlist: Playlist) -> PlaylistRow.Subtitle {
        if playlist.browseId == Route.likedMusicBrowseId { return .autoGenerated }
        return playlist.subtitle.map { .text($0) } ?? .none
    }
}

private struct PlaylistRow: View {
    enum Subtitle {
        case none, autoGenerated
        case text(String)
    }

    let title: String
    let subtitle: Subtitle
    let isSelected: Bool
    /// Runs after the pointer or keyboard focus rests on the row, so a later menu can already know the playlist's owner.
    var onPrefetch: (() async -> Void)?
    let action: () -> Void

    @State private var isHovering = false
    @FocusState private var isFocused: Bool

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: title)
                    .font(.rwTitle)
                    .foregroundStyle(.textPrimary)
                    .lineLimit(1)
                subtitleView
                    .font(.rwCaption)
                    .foregroundStyle(.textSecondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Metrics.space12)
            .padding(.vertical, Metrics.space8)
            .background(isSelected ? .surfaceFill : Color.clear, in: RoundedRectangle(cornerRadius: Metrics.radiusCard))
            .contentShape(RoundedRectangle(cornerRadius: Metrics.radiusCard))
        }
        .buttonStyle(.plain)
        .focused($isFocused)
        .onHover { isHovering = $0 }
        .task(id: isHovering || isFocused) {
            guard isHovering || isFocused, let onPrefetch else { return }
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            await onPrefetch()
        }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @ViewBuilder private var subtitleView: some View {
        switch subtitle {
        case .none:
            EmptyView()
        case .autoGenerated:
            HStack(spacing: Metrics.space4) {
                Image(systemName: "pin.fill").font(.rwIcon(Metrics.iconPin))
                Text("Auto-generated")
            }
        case .text(let owner):
            Text(verbatim: owner)
        }
    }
}

private struct GuestCard: View {
    let onSignIn: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.space12) {
            Text("Sign in to create and save playlists, and to see your library.")
                .font(.rwCaption)
                .foregroundStyle(.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Button(action: onSignIn) {
                Text("Sign in")
                    .font(.rwButton)
                    .foregroundStyle(.textPrimary)
                    .lineLimit(1)
                    .padding(.horizontal, Metrics.space16)
                    .frame(height: Metrics.pillHeight)
                    .background(.surfaceFill, in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Metrics.space12)
    }
}

#if DEBUG
#Preview("Signed in") { SidebarPreview(.loaded, isSignedIn: true) }
#Preview("Loading") { SidebarPreview(.loading, isSignedIn: true) }
#Preview("Failed") { SidebarPreview(.failed, isSignedIn: true) }
#Preview("Guest") { SidebarPreview(.loaded, isSignedIn: false) }

private struct SidebarPreview: View {
    let isSignedIn: Bool
    @State private var model: SidebarModel

    init(_ variant: PreviewFixtures.SidebarVariant, isSignedIn: Bool) {
        self.isSignedIn = isSignedIn
        _model = State(initialValue: PreviewFixtures.sidebarModel(variant))
    }

    var body: some View {
        SidebarView(
            selectedSection: .home, selectedPlaylistId: nil, isSignedIn: isSignedIn, model: model,
            onSelectSection: { _ in }, onSelectPlaylist: { _ in }, onNewPlaylist: {}, onPlaylistRemoved: { _, _ in }, onRetry: {},
            onSignIn: {}
        )
        .frame(width: Metrics.sidebarWidth, height: 500)
        .environment(PreviewFixtures.nowPlaying())
        .environment(ToastCenter())
        .background(.themeBase)
        .task { await model.load() }
    }
}
#endif
