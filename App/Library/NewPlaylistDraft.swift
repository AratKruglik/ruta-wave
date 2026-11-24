import InnerTube

struct NewPlaylistDraft: Equatable, Sendable {
    var title = ""
    var description = ""
    var privacy = PlaylistPrivacy.private
    var videoIds: [String] = []

    var isValid: Bool { PlaylistEdit.validTitle(title) != nil }

    /// The edits that turn `original` into this draft; only changed fields.
    func edits(from original: NewPlaylistDraft) -> [PlaylistEdit] {
        var edits: [PlaylistEdit] = []
        if let valid = PlaylistEdit.validTitle(title), valid != original.title { edits.append(.rename(valid)) }
        if description != original.description { edits.append(.setDescription(description)) }
        if privacy != original.privacy { edits.append(.setPrivacy(privacy)) }
        return edits
    }
}

extension NewPlaylistDraft {
    init(page: PlaylistPage) {
        self.init(title: page.header.title, description: page.header.description ?? "", privacy: page.privacy ?? .private)
    }
}
