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
}
