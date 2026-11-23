import InnerTube

struct NewPlaylistDraft: Equatable, Sendable {
    var title = ""
    var description = ""
    var privacy = PlaylistPrivacy.private

    var isValid: Bool { PlaylistEdit.validTitle(title) != nil }
}
