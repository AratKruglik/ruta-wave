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
}
