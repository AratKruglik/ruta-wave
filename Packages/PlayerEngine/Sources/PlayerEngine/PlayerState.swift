import Foundation

public enum LikeStatus: Sendable, Equatable {
    case like, dislike, indifferent

    init?(page: String) {
        switch page {
        case "LIKE": self = .like
        case "DISLIKE": self = .dislike
        case "INDIFFERENT": self = .indifferent
        default: return nil
        }
    }
}

public enum RepeatMode: Sendable, Equatable {
    case off, all, one

    init?(page: String) {
        switch page {
        case "NONE": self = .off
        case "ALL": self = .all
        case "ONE": self = .one
        default: return nil
        }
    }
}

public enum PlayerError: Sendable, Equatable {
    case pageLoadFailed, playerTimeout, unavailable(videoId: String), contentProcessCrashed, signInRequired
}
