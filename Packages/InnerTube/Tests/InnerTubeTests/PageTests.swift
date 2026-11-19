import Foundation
import Testing
@testable import InnerTube

private func json(_ text: String) throws -> JSONValue {
    try JSONDecoder().decode(JSONValue.self, from: Data(text.utf8))
}

@Suite struct PageTests {
    @Test func olderContinuationShape() throws {
        let shelf = try json(#"{"continuations":[{"nextContinuationData":{"continuation":"tok1"}}]}"#)
        #expect(shelf.nextContinuation == "tok1")
    }

    @Test func newerContinuationShapeOnObjectAndArray() throws {
        let item = #"{"continuationItemRenderer":{"continuationEndpoint":{"continuationCommand":{"token":"tok2"}}}}"#
        #expect(try json(#"{"contents":[{"a":1},\#(item)]}"#).nextContinuation == "tok2")
        #expect(try json("[{\"a\":1},\(item)]").nextContinuation == "tok2")
    }

    @Test func noOrEmptyContinuation() throws {
        #expect(try json(#"{"contents":[{"a":1}]}"#).nextContinuation == nil)
        #expect(try json(#"{"continuations":[{"nextContinuationData":{"continuation":""}}]}"#).nextContinuation == nil)
    }

    @Test func parseBlocksKeepsOrderAndDropsNil() throws {
        let blocks = try json(#"[{"known":"a"},{"unknown":"x"},{"known":"b"}]"#).array ?? []
        let parsed = parseBlocks(blocks) { $0["known"]?.string }
        #expect(parsed == ["a", "b"])
    }

    @Test func blockKeyNeverIncludesValues() throws {
        let block = try json(#"{"someRenderer":{"cookie":"SAPISID=secret","token":"tok"}}"#)
        #expect(blockKey(block) == "someRenderer")
        #expect(blockKey(.string("x")) == "non-object")
        #expect(blockKey(.object([String(repeating: "k", count: 100): .null])).count == 64)
    }
}
