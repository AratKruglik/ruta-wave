import InnerTube
import Testing

struct PlaceholderShelfTests {
    @Test(arguments: [Shelf.Layout.rows, .list])
    func songLayoutsGetSongPlaceholders(layout: Shelf.Layout) {
        let shelf = Shelf.placeholder(layout: layout, count: 4)
        #expect(shelf.items.count == 4)
        for item in shelf.items {
            guard case .song(let song) = item else { Issue.record("expected song"); continue }
            #expect(song.rank == nil)
        }
    }

    @Test func rankedSongPlaceholdersCarryRank() {
        let shelf = Shelf.placeholder(layout: .rows, ranked: true)
        for item in shelf.items {
            guard case .song(let song) = item else { Issue.record("expected song"); continue }
            #expect(song.rank != nil)
        }
    }

    @Test(arguments: [Shelf.Layout.cards, .grid])
    func cardLayoutsGetAlbumPlaceholders(layout: Shelf.Layout) {
        let shelf = Shelf.placeholder(layout: layout)
        for item in shelf.items {
            guard case .album = item else { Issue.record("expected album"); continue }
        }
    }
}
