import Foundation

enum JSONValue: Decodable, Sendable, Equatable {
    case object([String: JSONValue])
    case array([JSONValue])
    case string(String)
    case number(Double)
    case bool(Bool)
    case null

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: JSONValue].self))
        }
    }

    subscript(key: String) -> JSONValue? {
        guard case .object(let dict) = self else { return nil }
        return dict[key]
    }

    subscript(index: Int) -> JSONValue? {
        guard case .array(let items) = self, items.indices.contains(index) else { return nil }
        return items[index]
    }

    var string: String? {
        guard case .string(let value) = self else { return nil }
        return value
    }

    var double: Double? {
        guard case .number(let value) = self else { return nil }
        return value
    }

    var bool: Bool? {
        guard case .bool(let value) = self else { return nil }
        return value
    }

    var array: [JSONValue]? {
        guard case .array(let value) = self else { return nil }
        return value
    }

    var object: [String: JSONValue]? {
        guard case .object(let value) = self else { return nil }
        return value
    }
}
