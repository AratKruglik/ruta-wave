import Foundation

public struct AccountInfo: Sendable, Equatable {
    public let name: String
    public let handle: String?
    public let avatarURL: URL?

    public init(name: String, handle: String?, avatarURL: URL?) {
        self.name = name
        self.handle = handle
        self.avatarURL = avatarURL
    }

    init(accountMenu json: JSONValue) throws(InnerTubeError) {
        let header = json["actions"]?[0]?["openPopupAction"]?["popup"]?["multiPageMenuRenderer"]?["header"]?["activeAccountHeaderRenderer"]
        guard let name = header?["accountName"].flatMap(text) else { throw .unexpectedResponse }
        self.init(
            name: name,
            handle: header?["channelHandle"].flatMap(text),
            avatarURL: header?["accountPhoto"].flatMap(lastThumbnailURL)
        )
    }
}

func text(_ value: JSONValue) -> String? {
    let joined = value["runs"]?.array?.compactMap { $0["text"]?.string }.joined()
    return [joined, value["simpleText"]?.string].lazy.compactMap { $0 }.first { !$0.isEmpty }
}

private let allowedAvatarHosts = ["ggpht.com", "googleusercontent.com", "ytimg.com", "gstatic.com"]

func lastThumbnailURL(_ photo: JSONValue) -> URL? {
    guard var raw = photo["thumbnails"]?.array?.last?["url"]?.string else { return nil }
    if raw.hasPrefix("//") { raw = "https:" + raw }
    guard let url = URL(string: raw), url.scheme == "https", let host = url.host?.lowercased(),
          allowedAvatarHosts.contains(where: { host == $0 || host.hasSuffix("." + $0) })
    else {
        parserLog.notice("Rejected thumbnail host \(URL(string: raw)?.host ?? "none", privacy: .public)")
        return nil
    }
    return url
}
