import Foundation
import Testing
@testable import InnerTube

private func decode(_ json: String) throws -> JSONValue {
    try JSONDecoder().decode(JSONValue.self, from: Data(json.utf8))
}

@Suite struct JSONValueTests {
    @Test func navigatesNestedObjectsAndArrays() throws {
        let value = try decode(#"{"a":{"b":[{"c":"x"},{"c":"y"}]}}"#)
        #expect(value["a"]?["b"]?[1]?["c"]?.string == "y")
        #expect(value["a"]?["b"]?.array?.count == 2)
    }

    @Test func decodesScalars() throws {
        let value = try decode(#"{"t":true,"f":false,"zero":0,"one":1,"frac":1.5,"n":null}"#)
        #expect(value["t"] == .bool(true))
        #expect(value["f"] == .bool(false))
        #expect(value["zero"] == .number(0))
        #expect(value["one"] == .number(1))
        #expect(value["frac"]?.double == 1.5)
        #expect(value["n"] == .null)
    }

    @Test func missingOrWrongTypeAccessGivesNil() throws {
        let value = try decode(#"{"a":[1],"o":{}}"#)
        #expect(value["missing"] == nil)
        #expect(value["a"]?[5] == nil)
        #expect(value["a"]?["k"] == nil)
        #expect(value["o"]?[0] == nil)
        #expect(value["a"]?.string == nil)
    }

    @Test(arguments: [")]}'\n{\"a\":1}", "{\"a\":1}"])
    func responseStripsOptionalXSSIPrefix(raw: String) throws {
        #expect(try JSONValue(response: Data(raw.utf8))["a"] == .number(1))
    }

    @Test(arguments: ["garbage", ")]}'garbage", ""])
    func responseRejectsGarbage(raw: String) {
        #expect(throws: InnerTubeError.unexpectedResponse) { try JSONValue(response: Data(raw.utf8)) }
    }

    @Test func textJoinsAllRuns() throws {
        #expect(text(try decode(#"{"runs":[{"text":"Song"},{"text":" • "},{"text":"Artist"}]}"#)) == "Song • Artist")
        #expect(text(try decode(#"{"simpleText":"plain"}"#)) == "plain")
    }

    @Test func textOfEmptyRunsIsNil() throws {
        #expect(text(try decode(#"{"runs":[]}"#)) == nil)
        #expect(text(try decode(#"{"runs":[{"text":""}]}"#)) == nil)
    }
}
