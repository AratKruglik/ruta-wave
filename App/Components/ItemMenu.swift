import InnerTube
import SwiftUI

extension MusicItem {
    var canPlay: Bool {
        switch self {
        case .song, .album, .playlist: true
        case .artist, .link: false
        }
    }
}

@MainActor
func activate(_ item: MusicItem, navigation: NavigationModel, nowPlaying: NowPlayingModel) {
    if let route = item.route {
        navigation.push(route)
    } else {
        nowPlaying.play(item)
    }
}

/// The one menu behind both the context menu and the ⋮ button. The full menu arrives with 4.6.
struct ItemMenu: View {
    let item: MusicItem

    @Environment(NavigationModel.self) private var navigation
    @Environment(NowPlayingModel.self) private var nowPlaying

    var body: some View {
        if item.canPlay {
            Button("Play") { nowPlaying.play(item) }
        }
        if let route = item.route {
            Button("Open") { navigation.push(route) }
        }
        if case .song(let song) = item {
            Button("Start radio") { nowPlaying.startRadio(song) }
        }
    }
}
