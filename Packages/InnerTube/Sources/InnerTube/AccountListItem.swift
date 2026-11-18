import Foundation

public struct AccountListItem: Sendable, Equatable, Identifiable {
    public let name: String
    public let handle: String?
    public let avatarURL: URL?
    public let authUserIndex: Int
    public let isSelected: Bool

    public var id: Int { authUserIndex }

    public init(name: String, handle: String?, avatarURL: URL?, authUserIndex: Int, isSelected: Bool) {
        self.name = name
        self.handle = handle
        self.avatarURL = avatarURL
        self.authUserIndex = authUserIndex
        self.isSelected = isSelected
    }

    static func list(accountSwitcher json: JSONValue) -> [AccountListItem] {
        var seen = Set<Int>()
        return json.values(forKey: "accountItem")
            .compactMap(item)
            .filter { seen.insert($0.authUserIndex).inserted }
            .sorted { $0.authUserIndex < $1.authUserIndex }
    }

    /// Index to use after loading the list: the current one if it exists, otherwise the primary account.
    public static func fallbackIndex(current: Int, accounts: [AccountListItem]?) -> Int {
        guard let accounts, !accounts.isEmpty else { return current }
        if current >= 0, accounts.contains(where: { $0.authUserIndex == current }) { return current }
        return 0
    }

    private static func item(_ json: JSONValue) -> AccountListItem? {
        let urls = json.values(forKey: "signinUrl").compactMap(\.string).compactMap(URLComponents.init(string:))
        let indices = Set(urls.compactMap { $0.queryItems?.first(where: { $0.name == "authuser" })?.value.flatMap(Int.init) })
        // Dictionary traversal order is random, so ambiguous items are dropped rather than guessed.
        guard let name = json["accountName"].flatMap(text),
              indices.count == 1, let authUser = indices.first, authUser >= 0
        else { return nil }
        let isBrand = !json.values(forKey: "pageIdToken").isEmpty
            || urls.contains { $0.queryItems?.contains(where: { $0.name == "pageid" }) == true }
        guard !isBrand else { return nil }
        return AccountListItem(
            name: name,
            handle: json["channelHandle"].flatMap(text),
            avatarURL: json["accountPhoto"].flatMap(lastThumbnailURL),
            authUserIndex: authUser,
            isSelected: json["isSelected"]?.bool ?? false
        )
    }
}

private extension JSONValue {
    func values(forKey key: String) -> [JSONValue] {
        switch self {
        case .object(let dict):
            return (dict[key].map { [$0] } ?? []) + dict.values.flatMap { $0.values(forKey: key) }
        case .array(let items):
            return items.flatMap { $0.values(forKey: key) }
        default:
            return []
        }
    }
}
