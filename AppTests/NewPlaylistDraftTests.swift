import InnerTube
import Testing

struct NewPlaylistDraftTests {
    @Test(arguments: [
        ("", false), ("   \n", false), ("A", true), ("  A  ", true),
        (String(repeating: "a", count: 150), true), (String(repeating: "a", count: 151), false),
        (String(repeating: "👨‍👩‍👧", count: 150), true), (String(repeating: "👨‍👩‍👧", count: 151), false),
    ])
    func titleBoundaries(title: String, isValid: Bool) {
        #expect(NewPlaylistDraft(title: title).isValid == isValid)
    }

    @Test func defaultsToPrivate() {
        #expect(NewPlaylistDraft().privacy == .private)
    }

    @Test func startsWithoutSongs() {
        #expect(NewPlaylistDraft().videoIds.isEmpty)
    }

    @Test func editsListOnlyChangedFields() {
        let original = NewPlaylistDraft(title: "A", description: "d", privacy: .private)
        #expect(original.edits(from: original).isEmpty)
        var changed = original
        changed.title = "  B  "
        changed.description = ""
        #expect(changed.edits(from: original) == [.rename("B"), .setDescription("")])
        changed.privacy = .unlisted
        #expect(changed.edits(from: original).last == .setPrivacy(.unlisted))
    }
}
