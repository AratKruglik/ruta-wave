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

    private func selecting(_ keys: [String]) -> TrackSelection {
        var selection = TrackSelection()
        for key in keys { selection.toggle(key) }
        return selection
    }

    @Test func blockMoveShiftsASingleRowAndABlock() {
        let single = selecting(["c"])
        #expect(single.blockMove(in: order, up: true)! == (1, 2))
        #expect(single.blockMove(in: order, up: false)! == (3, 2))
        let block = selecting(["b", "c"])
        #expect(block.blockMove(in: order, up: true)! == (0, 2))
        #expect(block.blockMove(in: order, up: false)! == (3, 1))
    }

    @Test func blockMoveStopsAtTheEdges() {
        #expect(selecting(["a", "b"]).blockMove(in: order, up: true) == nil)
        #expect(selecting(["d", "e"]).blockMove(in: order, up: false) == nil)
    }

    @Test func blockMoveRefusesAGappedOrEmptySelection() {
        #expect(selecting(["a", "c"]).blockMove(in: order, up: true) == nil)
        #expect(TrackSelection().blockMove(in: order, up: false) == nil)
    }

    @Test func shiftQueueKeysMovesKeysAndAnchor() {
        var selection = selecting(["q2", "q3"])
        selection.shiftQueueKeys(by: -1)
        #expect(selection.keys == ["q1", "q2"] && selection.anchor == "q2")
    }
}
