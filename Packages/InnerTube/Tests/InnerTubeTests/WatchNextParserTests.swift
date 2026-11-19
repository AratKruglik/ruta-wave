import Foundation
import Testing
@testable import InnerTube

@Suite struct WatchNextParserTests {
    @Test func radioHasItemsCurrentMarkerChipsAndSource() throws {
        let next = try WatchNext(next: Fixture.json("next-radio"))
        #expect(next.queue.items.map(\.song.title) == ["Airbag", "Let Down", "505"])
        #expect(next.queue.items.map(\.isCurrent) == [true, false, false])
        #expect(next.queue.items[0].song.duration == "4:48")
        #expect(next.queue.items[0].song.artists.map(\.name) == ["Radiohead"])
        #expect(next.queue.items[0].song.album?.name == "OK Computer")
        #expect(next.queue.items.allSatisfy { $0.counterpart == nil })
        #expect(next.queue.continuation == "PLACEHOLDER_CONTINUATION_1")
        #expect(next.playingFrom == "Airbag Mix")
        #expect(next.playlistId == "RDAMVMjNY_wLukVW0")
        #expect(next.chips.first?.title == "All")
        #expect(next.chips.first?.isSelected == true)
        #expect(next.chips.allSatisfy { $0.watchTarget?.playlistId != nil && $0.target == nil })
        #expect(next.automix == nil)
    }

    @Test func currentItemIsTheSelectedOneNotTheFirst() throws {
        let next = try WatchNext(next: Self.selecting("Let Down", in: Fixture.json("next-radio")))
        #expect(next.queue.items.map(\.isCurrent) == [false, true, false])
    }

    private static func selecting(_ title: String, in node: JSONValue) -> JSONValue {
        switch node {
        case .object(var object):
            if case .object(var renderer)? = object["playlistPanelVideoRenderer"] {
                renderer["selected"] = .bool(node["playlistPanelVideoRenderer"]?["title"].flatMap(text) == title)
                object["playlistPanelVideoRenderer"] = .object(renderer)
            }
            return .object(object.mapValues { selecting(title, in: $0) })
        case .array(let items):
            return .array(items.map { selecting(title, in: $0) })
        default:
            return node
        }
    }

    @Test func tabsAreFoundByPageType() throws {
        let next = try WatchNext(next: Fixture.json("next-radio"))
        #expect(next.lyricsBrowseId?.hasPrefix("MPLY") == true)
        #expect(next.relatedBrowseId?.hasPrefix("MPTR") == true)
    }

    @Test func albumQueueHasAutomixAndNoChips() throws {
        let next = try WatchNext(next: Fixture.json("next-album"))
        #expect(next.queue.items.count == 2)
        #expect(next.queue.continuation == nil)
        #expect(next.chips.isEmpty)
        #expect(next.playingFrom == "OK Computer")
        #expect(next.automix?.playlistId?.hasPrefix("RDAMPL") == true)
        #expect(next.automix?.params != nil)
    }

    @Test func unselectableLyricsTabHasNoLyricsId() throws {
        let next = try WatchNext(next: Fixture.json("next-no-lyrics"))
        #expect(next.lyricsBrowseId == nil)
        #expect(next.relatedBrowseId != nil)
    }

    @Test func counterpartIsParsedFromTheWrapper() throws {
        let items = try WatchNext(next: Fixture.json("next-counterpart")).queue.items
        #expect(items.count == 2)
        #expect(items[0].song.isVideo == false)
        #expect(items[0].counterpart?.isVideo == true)
        #expect(items[0].counterpart?.videoId == "PLACEHOLDERVID")
        #expect(items[1].counterpart == nil)
    }

    @Test func continuationPagesTheQueue() throws {
        let page = try Page<QueueItem>(nextContinuation: Fixture.json("next-continuation"))
        #expect(page.items.count == 2)
        #expect(page.continuation == "PLACEHOLDER_CONTINUATION_1")
    }

    @Test func unplayableRowsAreSkipped() throws {
        let text = String(decoding: try Fixture.data("next-radio"), as: UTF8.self)
            .replacingOccurrences(of: "\"selected\": true,", with: "\"selected\": true, \"unplayableText\": {\"runs\": [{\"text\": \"x\"}]},")
        let next = try WatchNext(next: JSONValue(response: Data(text.utf8)))
        #expect(next.queue.items.map(\.song.title) == ["Let Down", "505"])
    }

    @Test func unknownRootIsUnexpected() {
        #expect(throws: InnerTubeError.unexpectedResponse) { try WatchNext(next: JSONValue.object([:])) }
        #expect(throws: InnerTubeError.unexpectedResponse) { try Page<QueueItem>(nextContinuation: JSONValue.object([:])) }
    }
}
