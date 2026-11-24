import InnerTube
import Testing

private let song = Song(
    videoId: "v1", title: "T", artists: [ItemRef(name: "A", browseId: "UC1")], album: ItemRef(name: "Al", browseId: "MPREb1"))
private let album = Album(browseId: "MPREb1", title: "Al", playTarget: WatchTarget(playlistId: "OLAK1"))
private let playlist = Playlist(browseId: "VLPL1", title: "P")
private let artist = Artist(browseId: "UC1", name: "A")

struct ItemActionsTests {
    @Test func plainSongHasTheFullQueueAndNavigationSet() {
        let actions = ItemActions.actions(for: .song(song), at: .plain)
        #expect(actions == [.play, .startRadio, .playNext, .addToQueue, .addToPlaylist, .goToAlbum, .goToArtist, .copyLink, .share])
    }

    @Test func artistHasNoQueueActions() {
        let actions = ItemActions.actions(for: .artist(artist), at: .plain)
        #expect(!actions.contains(.playNext) && !actions.contains(.addToQueue))
        #expect(actions.contains(.shuffle))
    }

    @Test func removalsFollowThePlace() {
        #expect(ItemActions.actions(for: .song(song), at: .ownPlaylistRow).contains(.removeFromPlaylist))
        #expect(ItemActions.actions(for: .song(song), at: .historyRow).contains(.removeFromHistory))
        #expect(ItemActions.actions(for: .song(song), at: .queueRow).contains(.removeFromQueue))
        #expect(!ItemActions.actions(for: .song(song), at: .plain).contains(.removeFromPlaylist))
    }

    @Test func unavailableSongHasNoQueueActions() {
        let gone = Song(videoId: "v2", title: "T", isAvailable: false)
        let actions = ItemActions.actions(for: .song(gone), at: .plain)
        #expect(!actions.contains(.play) && !actions.contains(.playNext) && !actions.contains(.addToPlaylist))
    }

    @Test func entityHeaderOffersEditOnlyToTheOwner() {
        #expect(ItemActions.actions(for: .playlist(playlist), at: .entityHeader(isOwned: true)).contains(.edit))
        let guestView = ItemActions.actions(for: .playlist(playlist), at: .entityHeader(isOwned: false))
        #expect(!guestView.contains(.edit) && guestView.contains(.likeAll))
    }

    @Test func accountActionsAreFlagged() {
        #expect(ItemAction.addToPlaylist.requiresAccount && ItemAction.likeAll.requiresAccount)
        #expect(!ItemAction.playNext.requiresAccount && !ItemAction.addToQueue.requiresAccount)
    }

    @Test func shareURLs() {
        #expect(MusicItem.song(song).shareURL?.absoluteString == "https://music.youtube.com/watch?v=v1")
        #expect(MusicItem.album(album).shareURL?.absoluteString == "https://music.youtube.com/playlist?list=OLAK1")
        #expect(MusicItem.playlist(playlist).shareURL?.absoluteString == "https://music.youtube.com/playlist?list=PL1")
        #expect(MusicItem.artist(artist).shareURL?.absoluteString == "https://music.youtube.com/channel/UC1")
        #expect(MusicItem.playlist(Playlist(browseId: Route.likedMusicBrowseId, title: "L")).shareURL == nil)
    }

    @Test func playNextBelongsToTheHostOnlyInTheQueue() {
        #expect(ItemActions.handledByHost(.playNext, at: .queueRow))
        for place in [ItemPlace.plain, .ownPlaylistRow, .historyRow, .playerBar, .entityHeader(isOwned: true)] {
            #expect(!ItemActions.handledByHost(.playNext, at: place))
        }
        #expect(ItemActions.handledByHost(.removeFromHistory, at: .historyRow))
        #expect(!ItemActions.handledByHost(.play, at: .plain))
    }
}
