import Foundation

enum SidebarSection: CaseIterable, Hashable, Sendable {
    case home, explore, library

    var title: LocalizedStringResource {
        switch self {
        case .home: "Home"
        case .explore: "Explore"
        case .library: "Library"
        }
    }

    var symbol: String {
        switch self {
        case .home: "house"
        case .explore: "safari"
        case .library: "square.stack"
        }
    }

    var filledSymbol: String { symbol + ".fill" }

    var shortcutDigit: Character {
        switch self {
        case .home: "1"
        case .explore: "2"
        case .library: "3"
        }
    }
}

enum ExploreRoute: Hashable, Sendable {
    case newReleases, charts, moods
    case mood(params: String)
}

enum Route: Hashable, Sendable {
    case explore(ExploreRoute)
    case library(section: String?)
    case search(query: String, filter: String?)
    case album(browseId: String)
    case artist(channelId: String)
    case playlist(browseId: String)
    case more(browseId: String, params: String?)
    case history

    static let likedMusicBrowseId = "VLLM"

    /// Dropped on sign-out; every playlist counts because an unlisted one loads for anyone holding its ID.
    var requiresAccount: Bool {
        switch self {
        case .library, .history, .playlist: true
        default: false
        }
    }

    var title: LocalizedStringResource {
        switch self {
        case .explore(.newReleases): "New releases"
        case .explore(.charts): "Charts"
        case .explore(.moods), .explore(.mood): "Moods & genres"
        case .library: "Library"
        case .search: "Search"
        case .album: "Album"
        case .artist: "Artist"
        case .playlist: "Playlist"
        case .more: "More"
        case .history: "History"
        }
    }
}
