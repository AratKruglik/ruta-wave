import AppKit
import InnerTube
import SwiftUI

@MainActor
func activate(_ item: MusicItem, navigation: NavigationModel, nowPlaying: NowPlayingModel) {
    if let route = item.route {
        navigation.push(route)
    } else {
        nowPlaying.play(item)
    }
}

extension ItemAction {
    var title: LocalizedStringKey {
        switch self {
        case .play: "Play"
        case .playNext: "Play next"
        case .addToQueue: "Add to queue"
        case .startRadio: "Start radio"
        case .shuffle: "Shuffle"
        case .open: "Open"
        case .addToPlaylist: "Add to playlist…"
        case .goToAlbum: "Go to album"
        case .goToArtist: "Go to artist"
        case .like: "Like"
        case .copyLink: "Copy link"
        case .share: "Share"
        case .removeFromPlaylist: "Remove from playlist"
        case .removeFromHistory: "Remove from history"
        case .removeFromQueue: "Remove from queue"
        case .edit: "Edit playlist…"
        case .likeAll: "Like all"
        case .dislikeAll: "Dislike all"
        }
    }

    var signInReason: String {
        switch self {
        case .like, .likeAll: String(localized: "Sign in to like songs")
        case .dislikeAll: String(localized: "Sign in to dislike songs")
        case .edit, .removeFromPlaylist: String(localized: "Sign in to edit playlists")
        case .removeFromHistory: String(localized: "Sign in to manage your history")
        default: String(localized: "Sign in to add songs to playlists")
        }
    }
}

/// The one menu body behind every context menu and ⋮ button. The host owns `popover` and shows it with `.itemPopover`.
struct ItemMenu: View {
    let item: MusicItem
    var place: ItemPlace = .plain
    @Binding var popover: ItemPopover?
    /// Handles the actions only the host can do (removals, editing, whole-list rating, queue positions). Others run here.
    var onHostAction: ((ItemAction) -> Void)?
    /// Rows the "Add to playlist…" action applies to; the item's own song when `nil`.
    var videoIds: [String]?

    @Environment(NavigationModel.self) private var navigation
    @Environment(NowPlayingModel.self) private var nowPlaying
    @Environment(ToastCenter.self) private var toasts

    var body: some View {
        ForEach(ItemActions.actions(for: item, at: place), id: \.self) { action in
            if action == .share, let url = item.shareURL {
                ShareLink(item: url)
            } else {
                Button(action.title, role: action.isDestructive ? .destructive : nil) { perform(action) }
            }
        }
    }

    private func perform(_ action: ItemAction) {
        if action.requiresAccount, !nowPlaying.isSignedIn {
            popover = .signIn(reason: action.signInReason)
            return
        }
        if ItemActions.handledByHost(action, at: place) {
            onHostAction?(action)
            return
        }
        switch action {
        case .play: nowPlaying.play(item)
        case .playNext: nowPlaying.enqueue(item, playNext: true)
        case .addToQueue: nowPlaying.enqueue(item, playNext: false)
        case .startRadio: nowPlaying.startRadio(item)
        case .shuffle: nowPlaying.shuffle(item)
        case .open: if let route = item.route { navigation.push(route) }
        case .addToPlaylist: popover = .addToPlaylist(videoIds: videoIds ?? songIds)
        case .goToAlbum: if case .song(let song) = item, let id = song.album?.browseId { navigation.push(.album(browseId: id)) }
        case .goToArtist:
            if case .song(let song) = item, let id = song.artists.compactMap(\.browseId).first { navigation.push(.artist(channelId: id)) }
        case .copyLink:
            if let url = item.shareURL {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(url.absoluteString, forType: .string)
                toasts.show("Link copied")
            }
        case .like: if case .song(let song) = item { nowPlaying.rate(videoId: song.videoId, .like) }
        case .share: break
        case .removeFromPlaylist, .removeFromHistory, .removeFromQueue, .edit, .likeAll, .dislikeAll: break
        }
    }

    private var songIds: [String] {
        if case .song(let song) = item { [song.videoId] } else { [] }
    }
}

extension ItemAction {
    fileprivate var isDestructive: Bool {
        self == .removeFromPlaylist || self == .removeFromHistory || self == .removeFromQueue
    }
}

extension View {
    /// Presents the sign-in prompt or the Add-to-playlist popover that an `ItemMenu` asked for, anchored to this host.
    func itemPopover(_ popover: Binding<ItemPopover?>) -> some View {
        modifier(ItemPopoverModifier(popover: popover))
    }
}

private struct ItemPopoverModifier: ViewModifier {
    @Binding var popover: ItemPopover?

    @Environment(\.requestSignIn) private var requestSignIn

    func body(content: Content) -> some View {
        content
            .guestPrompt(
                isPresented: Binding(
                    get: { if case .signIn = popover { true } else { false } },
                    set: { if !$0 { popover = nil } }),
                reason: LocalizedStringResource(stringLiteral: signInReason), onSignIn: requestSignIn.perform)
            .popover(
                isPresented: Binding(
                    get: { if case .addToPlaylist = popover { true } else { false } },
                    set: { if !$0 { popover = nil } })
            ) {
                if case .addToPlaylist(let videoIds) = popover {
                    AddToPlaylistPopover(videoIds: videoIds, onDismiss: { popover = nil })
                }
            }
    }

    private var signInReason: String {
        if case .signIn(let reason) = popover { reason } else { "" }
    }
}
