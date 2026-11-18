import Foundation

public enum SessionCookies {
    public enum RestoreOutcome {
        case signedIn([HTTPCookie])
        case signedOut
        case corrupt
    }

    static let requiredNames = ["SAPISID", "__Secure-3PAPISID", "SID", "HSID", "SSID"]

    static func encode(_ cookies: [HTTPCookie]) throws -> Data {
        let list = cookies.compactMap { cookie in
            cookie.properties.map { Dictionary(uniqueKeysWithValues: $0.map { ($0.key.rawValue, $0.value) }) }
        }
        return try PropertyListSerialization.data(fromPropertyList: list, format: .binary, options: 0)
    }

    static func restore(from data: Data?, now: Date) -> RestoreOutcome {
        guard let data else { return .signedOut }
        guard let list = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [[String: Any]] else {
            return .corrupt
        }
        let cookies = list.compactMap { dict in
            HTTPCookie(properties: Dictionary(uniqueKeysWithValues: dict.map { (HTTPCookiePropertyKey($0.key), $0.value) }))
        }
        let valid = Set(cookies.filter { ($0.expiresDate ?? .distantFuture) > now }.map(\.name))
        return requiredNames.allSatisfy(valid.contains) ? .signedIn(cookies) : .signedOut
    }
}
