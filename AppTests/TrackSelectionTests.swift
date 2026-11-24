import InnerTube
import Testing

struct TrackSelectionTests {
    private let order = ["a", "b", "c", "d", "e"]

    @Test func toggleAddsAndRemovesAndMovesTheAnchor() {
        var selection = TrackSelection()
        selection.toggle("b")
        selection.toggle("d")
        #expect(selection.keys == ["b", "d"] && selection.anchor == "d")
        selection.toggle("b")
        #expect(selection.keys == ["d"])
    }

    @Test func extendSelectsTheRangeInBothDirectionsAndKeepsTheAnchor() {
        var selection = TrackSelection()
        selection.toggle("c")
        selection.extend(to: "e", in: order)
        #expect(selection.keys == ["c", "d", "e"] && selection.anchor == "c")
        selection.extend(to: "a", in: order)
        #expect(selection.keys == ["a", "b", "c"] && selection.anchor == "c")
    }

    @Test func extendWithoutAnAnchorSelectsOneRow() {
        var selection = TrackSelection()
        selection.extend(to: "d", in: order)
        #expect(selection.keys == ["d"] && selection.anchor == "d")
    }

    @Test func selectAllAndClear() {
        var selection = TrackSelection()
        selection.selectAll(order)
        #expect(selection.count == 5)
        selection.clear()
        #expect(selection.isEmpty && selection.anchor == nil)
    }

    @Test func retainDropsRowsThatLeftTheList() {
        var selection = TrackSelection()
        selection.toggle("a")
        selection.toggle("c")
        selection.retain(keys: ["a", "b"])
        #expect(selection.keys == ["a"] && selection.anchor == nil)
    }

    @Test func orderedFollowsTheList() {
        var selection = TrackSelection()
        selection.toggle("d")
        selection.toggle("b")
        #expect(selection.ordered(in: order) == ["b", "d"])
    }

    @Test func songRowKeyPrefersTheSetVideoId() {
        #expect(Song(videoId: "v", title: "T").rowKey == "v")
    }
}
