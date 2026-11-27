import AppKit
import InnerTube
import SwiftUI

struct CircleIconButton: View {
    let symbol: String
    let label: LocalizedStringKey
    var isSelected = false
    let action: () -> Void

    var body: some View {
        Button(action: action) { CircleIcon(symbol: symbol) }
            .buttonStyle(.plain)
            .help(label)
            .accessibilityLabel(label)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct CircleIcon: View {
    let symbol: String

    var body: some View {
        Image(systemName: symbol)
            .font(.rwIcon(Metrics.iconRow))
            .foregroundStyle(.textPrimary)
            .frame(width: Metrics.actionButton, height: Metrics.actionButton)
            .background(.surfaceFill, in: Circle())
            .contentShape(Circle())
    }
}

/// Copy link, and the system share menu behind ⋮. Hidden when the page has no public URL.
struct ShareButtons: View {
    let url: URL?

    @Environment(ToastCenter.self) private var toasts

    var body: some View {
        if let url {
            CircleIconButton(symbol: "link", label: "Share") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(url.absoluteString, forType: .string)
                toasts.show("Link copied")
            }
            Menu { ShareLink(item: url) } label: { CircleIcon(symbol: "ellipsis") }
                .menuStyle(.button)
                .menuIndicator(.hidden)
                .buttonStyle(.plain)
                .help("More actions")
                .accessibilityLabel("More actions")
        }
    }
}

struct ExpandableText: View {
    let text: String

    @State private var isExpanded = false

    // shortcut: the toggle shows for any text past 150 characters, whether or not the line limit truncates it.
    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.space4) {
            Text(text)
                .font(.rwBody)
                .foregroundStyle(.textSecondary)
                .lineLimit(isExpanded ? nil : 3)
            if text.count > 150 {
                Button(isExpanded ? "Less" : "More") { isExpanded.toggle() }
                    .buttonStyle(.plain)
                    .font(.rwButton)
                    .foregroundStyle(.accentLink)
            }
        }
    }
}

/// Header of an album or a playlist.
struct EntityHeader: View {
    let model: EntityModel
    let header: PageHeader
    let isSaved: Bool
    let isWide: Bool

    @Environment(NavigationModel.self) private var navigation
    @Environment(NowPlayingModel.self) private var nowPlaying
    @Environment(\.requestSignIn) private var requestSignIn
    @State private var isSavePromptShown = false
    @State private var popover: ItemPopover?
    @State private var isEditing = false
    @State private var isSavingEdit = false
    @Environment(ToastCenter.self) private var toasts

    var body: some View {
        let layout = isWide
            ? AnyLayout(HStackLayout(alignment: .bottom, spacing: Metrics.space32))
            : AnyLayout(VStackLayout(alignment: .leading, spacing: Metrics.space24))
        layout {
            ArtworkImage(
                url: header.thumbnailURL, width: Metrics.entityCover, height: Metrics.entityCover, cornerRadius: Metrics.radiusCover,
                placeholderSymbol: model.playlistBrowseId == Route.likedMusicBrowseId ? "heart.fill" : "music.note")
            VStack(alignment: .leading, spacing: Metrics.space12) {
                HStack(spacing: Metrics.space8) {
                    Text(header.title)
                        .font(.rwDisplay)
                        .foregroundStyle(.textPrimary)
                        .accessibilityAddTraits(.isHeader)
                    if header.isExplicit { ExplicitBadge() }
                }
                owners
                ForEach([header.subtitle, header.secondSubtitle].compactMap { $0 }, id: \.self) { line in
                    Text(line)
                        .font(.rwBody)
                        .foregroundStyle(.textSecondary)
                }
                if let description = header.description, !description.isEmpty { ExpandableText(text: description) }
                actions
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var owners: some View {
        HStack(spacing: 0) {
            ForEach(Array(header.artists.enumerated()), id: \.offset) { index, artist in
                if index > 0 { Text(", ").font(.rwTitle).foregroundStyle(.textPrimary) }
                if let browseId = artist.browseId {
                    Button(artist.name) { navigation.push(Route(target: BrowseTarget(browseId: browseId))) }
                        .buttonStyle(.plain)
                        .font(.rwTitle)
                        .foregroundStyle(.textPrimary)
                } else {
                    Text(artist.name).font(.rwTitle).foregroundStyle(.textPrimary)
                }
            }
        }
    }

    private var actions: some View {
        HStack(spacing: Metrics.space12) {
            Button(action: play) {
                Image(systemName: "play.fill")
                    .font(.rwIcon(Metrics.iconBar))
                    .foregroundStyle(.textOnInverse)
                    .frame(width: Metrics.playButton, height: Metrics.playButton)
                    .background(.surfaceInverse, in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Play (⌥-click to shuffle)")
            .accessibilityLabel("Play")
            CircleIconButton(symbol: "shuffle", label: "Shuffle") { nowPlaying.play(model.shuffleTarget) }
            if model.canSave {
                CircleIconButton(
                    symbol: isSaved ? "bookmark.fill" : "bookmark", label: isSaved ? "Remove from library" : "Save to library",
                    isSelected: isSaved
                ) {
                    if nowPlaying.isSignedIn { model.toggleSaved() } else { isSavePromptShown = true }
                }
                .guestPrompt(isPresented: $isSavePromptShown, reason: "Sign in to save to your library", onSignIn: requestSignIn.perform)
            }
            if let url = model.shareURL {
                CircleIconButton(symbol: "link", label: "Share") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(url.absoluteString, forType: .string)
                    toasts.show("Link copied")
                }
            }
            moreMenu
        }
        .padding(.top, Metrics.space8)
        .itemPopover($popover)
        .sheet(isPresented: $isEditing) {
            NewPlaylistSheet(
                title: "Edit playlist", confirmTitle: "Save", initial: model.editDraft ?? NewPlaylistDraft(),
                showsPrivacy: model.canEditPrivacy, isCreating: isSavingEdit, onCancel: { isEditing = false },
                onCreate: { draft in
                    isSavingEdit = true
                    Task {
                        if await model.editDetails(draft) { isEditing = false }
                        isSavingEdit = false
                    }
                })
        }
    }

    private var pageItem: MusicItem? {
        switch model.kind {
        case .album(let target): .album(Album(browseId: target.browseId, title: header.title, playTarget: model.playTarget))
        case .playlist(let browseId): .playlist(Playlist(browseId: browseId, title: header.title, playTarget: model.playTarget))
        case .artist: nil
        }
    }

    @ViewBuilder private var moreMenu: some View {
        if let item = pageItem {
            Menu {
                ItemMenu(item: item, place: .entityHeader(isOwned: model.canEdit), popover: $popover, onHostAction: hostAction)
            } label: { CircleIcon(symbol: "ellipsis") }
                .menuStyle(.button)
                .menuIndicator(.hidden)
                .buttonStyle(.plain)
                .help("More actions")
                .accessibilityLabel("More actions")
        }
    }

    private func hostAction(_ action: ItemAction) {
        switch action {
        case .edit: isEditing = true
        case .likeAll, .dislikeAll:
            let rating: Rating = action == .likeAll ? .like : .dislike
            nowPlaying.rateAll(rating) { await model.allTrackIds() }
        default: break
        }
    }

    private func play() {
        nowPlaying.play(NSEvent.modifierFlags.contains(.option) ? model.shuffleTarget : model.playTarget)
    }
}

/// The loading header in the final layout, so nothing shifts when the page arrives.
struct SkeletonEntityHeader: View {
    let isArtist: Bool
    let isWide: Bool

    var body: some View {
        Group {
            if isArtist {
                Rectangle().fill(.surfaceFill).frame(height: Metrics.artistHeroHeight)
            } else {
                let layout = isWide
                    ? AnyLayout(HStackLayout(alignment: .bottom, spacing: Metrics.space32))
                    : AnyLayout(VStackLayout(alignment: .leading, spacing: Metrics.space24))
                layout {
                    RoundedRectangle(cornerRadius: Metrics.radiusCover).fill(.surfaceFill)
                        .frame(width: Metrics.entityCover, height: Metrics.entityCover)
                    VStack(alignment: .leading, spacing: Metrics.space12) {
                        Capsule().fill(.surfaceFill).frame(width: 320, height: 40)
                        Capsule().fill(.surfaceFill).frame(width: 200, height: 14)
                        Capsule().fill(.surfaceFill).frame(width: 140, height: 14)
                        Circle().fill(.surfaceFill).frame(width: Metrics.playButton, height: Metrics.playButton)
                    }
                }
            }
        }
        .accessibilityHidden(true)
    }
}
