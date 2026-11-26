import Foundation

public enum InnerTubeError: Error, Sendable, Equatable {
    case missingSAPISID
    case unauthorized
    case network(URLError.Code)
    case httpStatus(Int)
    case unexpectedResponse
    /// A private, deleted or non-existent playlist, album or artist: the server answers 200 without `contents`.
    case notAvailable
    /// A mutation was called without credentials. No request was sent.
    case signInRequired
    /// A mutation argument failed client-side validation. No request was sent.
    case invalidArgument
}

extension InnerTubeError {
    var isTransient: Bool {
        switch self {
        case .network: true
        case .httpStatus(let status): (500...599).contains(status)
        default: false
        }
    }
}

/// Signed-in identity for a request. A `nil` `Credentials` means a guest.
public struct Credentials: Sendable {
    public let cookies: [HTTPCookie]

    public init(cookies: [HTTPCookie]) {
        self.cookies = cookies
    }
}

private final class RejectRedirects: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest
    ) async -> URLRequest? {
        nil
    }
}

public actor InnerTubeClient {
    typealias Transport = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    static let maxAttempts = 3

    private let transport: Transport
    private let retryDelay: Duration

    public init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        let session = URLSession(configuration: configuration, delegate: RejectRedirects(), delegateQueue: nil)
        self.init(transport: { try await session.data(for: $0) }, retryDelay: .milliseconds(500))
    }

    init(transport: @escaping Transport, retryDelay: Duration) {
        self.transport = transport
        self.retryDelay = retryDelay
    }

    public func refreshClientVersion() async {
        guard let data = try? await data(for: InnerTubeRequest.makePage()) else { return }
        ClientVersion.shared.accept(ClientVersion.extract(fromPage: String(decoding: data, as: UTF8.self)))
    }

    public func accountMenu(cookies: [HTTPCookie]) async throws -> AccountInfo {
        try AccountInfo(accountMenu: await post("account/account_menu", cookies: cookies))
    }

    public func connectAsGuest() async throws {
        let json = try await postGuest("browse", body: ["browseId": "FEmusic_home"])
        guard GuestVisitor.validated(json["responseContext"]?["visitorData"]?.string) != nil else {
            throw InnerTubeError.unexpectedResponse
        }
    }

    public func home(params: String? = nil, credentials: Credentials?) async throws -> BrowsePage {
        try await browse(BrowseTarget(browseId: BrowseTarget.home.browseId, params: params), credentials: credentials)
    }

    /// Not for entity pages: `MPREb_…` goes to `album(_:)`, `UC…` without params to `artist(_:)` and every `VL…` target to `playlist(_:)`.
    /// Artist "Show all" (`MPAD…`, `UC…` with params), the Related page and other section lists parse here.
    public func browse(_ target: BrowseTarget, credentials: Credentials?) async throws -> BrowsePage {
        var body: [String: any Sendable] = ["browseId": target.browseId]
        body["params"] = target.params
        return try BrowsePage(browse: await fetch("browse", body: body, credentials: credentials))
    }

    /// A guest continuation works only while the guest visitor is unchanged; after `resetGuestVisitor()` restart from page 1.
    public func browseContinuation(_ token: String, credentials: Credentials?) async throws -> Page<Shelf> {
        try BrowsePage(browse: await fetch("browse", body: ["continuation": token], credentials: credentials)).shelves
    }

    /// `MPREb_…`, with the optional `params` of an "Other versions" card.
    public func album(_ target: BrowseTarget, credentials: Credentials?) async throws -> AlbumPage {
        try AlbumPage(album: await fetchBrowse(target, credentials: credentials))
    }

    /// `UC…` without params.
    public func artist(_ target: BrowseTarget, credentials: Credentials?) async throws -> ArtistPage {
        try ArtistPage(artist: await fetchBrowse(target, credentials: credentials))
    }

    /// Every `VL…` target, including `VLLM` and the `VLOLAK…` target of an artist's Top songs. Private, deleted and non-existent
    /// playlists throw `.notAvailable`.
    public func playlist(_ target: BrowseTarget, credentials: Credentials?) async throws -> PlaylistPage {
        try PlaylistPage(playlist: await fetchBrowse(target, credentials: credentials))
    }

    /// A guest continuation works only while the guest visitor is unchanged. Without the issuing visitor the server does not fail:
    /// it silently returns page 1 again. After `resetGuestVisitor()` reload page 1.
    public func playlistContinuation(_ token: String, credentials: Credentials?) async throws -> Page<Song> {
        try Page<Song>(playlistContinuation: await fetch("browse", body: ["continuation": token], credentials: credentials))
    }

    /// A guest gets an empty page.
    public func library(_ target: BrowseTarget, credentials: Credentials?) async throws -> LibraryPage {
        try LibraryPage(library: await fetchBrowse(target, credentials: credentials))
    }

    /// The section in the order of a `LibrarySort`.
    public func libraryReload(_ token: String, credentials: Credentials?) async throws -> LibraryPage {
        try LibraryPage(library: await fetch("browse", body: ["continuation": token], credentials: credentials))
    }

    public func libraryContinuation(_ token: String, credentials: Credentials?) async throws -> Page<MusicItem> {
        try Page<MusicItem>(libraryContinuation: await fetch("browse", body: ["continuation": token], credentials: credentials))
    }

    /// The `guide` playlists, or the library playlists when the guide has none. Liked music is the entry with
    /// `browseId == BrowseTarget.likedMusic.browseId`. A guest gets an empty list.
    public func sidebarPlaylists(credentials: Credentials?) async throws -> [Playlist] {
        let guided = [Playlist](guide: try await fetch("guide", body: [:], credentials: credentials))
        if !guided.isEmpty { return guided }
        return try await library(.likedPlaylists, credentials: credentials).items.items.compactMap {
            if case .playlist(let playlist) = $0 { playlist } else { nil }
        }
    }

    /// A guest gets no days.
    public func history(credentials: Credentials?) async throws -> [HistoryDay] {
        try [HistoryDay](history: await fetchBrowse(.history, credentials: credentials))
    }

    /// The bridge stays the source of truth for the live queue; this is for the initial display and chip switching.
    public func watchNext(_ target: WatchTarget, credentials: Credentials?) async throws -> WatchNext {
        var body: [String: any Sendable] = [:]
        body["videoId"] = target.videoId
        body["playlistId"] = target.playlistId
        body["params"] = target.params
        return try WatchNext(next: await fetch("next", body: body, credentials: credentials))
    }

    public func watchNextContinuation(_ token: String, credentials: Credentials?) async throws -> Page<QueueItem> {
        try Page<QueueItem>(nextContinuation: await fetch("next", body: ["continuation": token], credentials: credentials))
    }

    /// `nil` is "Lyrics not available".
    public func lyrics(_ browseId: String, credentials: Credentials?) async throws -> Lyrics? {
        try LyricsParser.parse(await fetch("browse", body: ["browseId": browseId], credentials: credentials))
    }

    /// `nil` is "no timed lyrics": none exist, or the lines carry no times. Always a guest request, so it never touches the visitor id or the session.
    public func timedLyrics(_ browseId: String) async throws -> TimedLyrics? {
        let request = try InnerTubeRequest.makeMobileGuest(endpoint: "browse", body: ["browseId": browseId], locale: .current)
        return try TimedLyricsParser.parse(await data(for: request))
    }

    /// `country` is a `ChartCountry.code`. Without it the server picks the country from the caller's IP address.
    public func charts(country: String? = nil, credentials: Credentials?) async throws -> ChartsPage {
        var body: [String: any Sendable] = ["browseId": BrowseTarget.charts.browseId]
        if let country { body["formData"] = ["selectedValues": [country]] }
        return try ChartsPage(charts: await fetch("browse", body: body, credentials: credentials))
    }

    public func search(_ query: String, params: String? = nil, credentials: Credentials?) async throws -> SearchResults {
        var body: [String: any Sendable] = ["query": query]
        body["params"] = params
        return try SearchResults(search: await fetch("search", body: body, credentials: credentials))
    }

    /// Filtered results only.
    public func searchContinuation(_ token: String, credentials: Credentials?) async throws -> Page<MusicItem> {
        try SearchResults(search: await fetch("search", body: ["continuation": token], credentials: credentials)).items
    }

    public func searchSuggestions(_ input: String, credentials: Credentials?) async throws -> SearchSuggestions {
        SearchSuggestions(suggestions: try await fetch("music/get_search_suggestions", body: ["input": input], credentials: credentials))
    }

    public func rate(videoId: String, _ rating: Rating, credentials: Credentials?) async throws {
        guard !videoId.isEmpty else { throw InnerTubeError.invalidArgument }
        _ = try await mutate(rating.endpoint, body: ["target": ["videoId": videoId]], credentials: credentials)
    }

    /// Save to library is `.like`, remove from library is `.indifferent`. An album passes `AlbumPage.audioPlaylistId`.
    public func rate(playlistId: String, _ rating: Rating, credentials: Credentials?) async throws {
        let id = try Self.editableId(playlistId)
        _ = try await mutate(rating.endpoint, body: ["target": ["playlistId": id]], credentials: credentials)
    }

    /// Returns the bare playlist id. Not retried: after `.network` reload the playlists instead of calling again.
    public func createPlaylist(
        title: String, description: String = "", privacy: PlaylistPrivacy = .private, videoIds: [String] = [],
        credentials: Credentials?
    ) async throws -> String {
        guard let title = PlaylistEdit.validTitle(title) else { throw InnerTubeError.invalidArgument }
        guard !videoIds.contains(where: \.isEmpty) else { throw InnerTubeError.invalidArgument }
        var body: [String: any Sendable] = ["title": title, "description": description, "privacyStatus": privacy.rawValue]
        if !videoIds.isEmpty { body["videoIds"] = videoIds }
        let json = try JSONValue(response: await mutate("playlist/create", body: body, credentials: credentials))
        guard let id = json["playlistId"]?.string, !id.isEmpty else { throw InnerTubeError.unexpectedResponse }
        return id
    }

    public func deletePlaylist(_ playlistId: String, credentials: Credentials?) async throws {
        let id = try Self.editableId(playlistId)
        _ = try await mutate("playlist/delete", body: ["playlistId": id], credentials: credentials)
    }

    /// All edits go in one request, in order. The result lists the rows an `.add` created; it is empty when the response has none.
    /// `playlistSetVideoId` values are only valid for the account that fetched the playlist.
    @discardableResult
    public func editPlaylist(_ playlistId: String, _ edits: [PlaylistEdit], credentials: Credentials?) async throws -> [AddedPlaylistRow] {
        let id = try Self.editableId(playlistId)
        guard !edits.isEmpty, edits.allSatisfy(\.isValid) else { throw InnerTubeError.invalidArgument }
        let body: [String: any Sendable] = ["playlistId": id, "actions": edits.map(\.action)]
        let json = try JSONValue(response: await mutate("browse/edit_playlist", body: body, credentials: credentials))
        guard json["status"]?.string == "STATUS_SUCCEEDED" else { throw InnerTubeError.unexpectedResponse }
        return [AddedPlaylistRow](editResponse: json)
    }

    /// `channelId` is `ArtistPage.channelId`, never the page `browseId`.
    public func setSubscribed(_ subscribed: Bool, channelId: String, credentials: Credentials?) async throws {
        guard !channelId.isEmpty else { throw InnerTubeError.invalidArgument }
        _ = try await mutate(
            subscribed ? "subscription/subscribe" : "subscription/unsubscribe", body: ["channelIds": [channelId]],
            credentials: credentials)
    }

    /// Tokens are bound to the account that fetched them: send only with its credentials, and cancel a delayed send (Undo window) on sign-out or account switch.
    public func sendFeedback(_ tokens: [String], credentials: Credentials?) async throws {
        guard !tokens.isEmpty, !tokens.contains(where: \.isEmpty) else { throw InnerTubeError.invalidArgument }
        let json = try JSONValue(response: await mutate("feedback", body: ["feedbackTokens": tokens], credentials: credentials))
        guard let responses = json["feedbackResponses"]?.array, !responses.isEmpty,
            responses.allSatisfy({ $0["isProcessed"]?.bool == true })
        else { throw InnerTubeError.unexpectedResponse }
    }

    public static func resetGuestVisitor() {
        GuestVisitor.shared.reset()
    }

    func post(
        _ endpoint: String,
        body: [String: any Sendable] = [:],
        cookies: [HTTPCookie]
    ) async throws -> JSONValue {
        let request = try InnerTubeRequest.make(
            endpoint: endpoint,
            body: body,
            cookies: cookies,
            now: Date(),
            locale: .current
        )
        return try await send(request)
    }

    func postGuest(_ endpoint: String, body: [String: any Sendable] = [:]) async throws -> JSONValue {
        let snapshot = GuestVisitor.shared.snapshot()
        let request = try InnerTubeRequest.makeGuest(
            endpoint: endpoint, body: body, visitorData: snapshot.value, locale: .current)
        let json = try await send(request)
        GuestVisitor.shared.accept(json["responseContext"]?["visitorData"]?.string, generation: snapshot.generation)
        return json
    }

    // Never retried: a resend after a timeout can duplicate a playlist or flip a toggle back.
    private func mutate(_ endpoint: String, body: [String: any Sendable], credentials: Credentials?) async throws -> Data {
        guard let credentials else { throw InnerTubeError.signInRequired }
        let request = try InnerTubeRequest.make(
            endpoint: endpoint, body: body, cookies: credentials.cookies,
            now: Date(), locale: .current)
        return try await attemptOnce(request)
    }

    /// Drops `VL`. Liked music (`LM`) cannot be saved, deleted or edited.
    private static func editableId(_ playlistId: String) throws -> String {
        let id = playlistId.hasPrefix("VL") ? String(playlistId.dropFirst(2)) : playlistId
        guard !id.isEmpty, id != "LM" else { throw InnerTubeError.invalidArgument }
        return id
    }

    private func fetchBrowse(_ target: BrowseTarget, credentials: Credentials?) async throws -> JSONValue {
        var body: [String: any Sendable] = ["browseId": target.browseId]
        body["params"] = target.params
        return try await fetch("browse", body: body, credentials: credentials)
    }

    private func fetch(_ endpoint: String, body: [String: any Sendable], credentials: Credentials?) async throws -> JSONValue {
        guard let credentials else { return try await postGuest(endpoint, body: body) }
        return try await post(endpoint, body: body, cookies: credentials.cookies)
    }

    private func send(_ request: URLRequest) async throws -> JSONValue {
        try JSONValue(response: try await data(for: request))
    }

    // Every attempt reuses the same request, so the visitor and signed headers stay fixed across retries.
    private func data(for request: URLRequest) async throws -> Data {
        var attempt = 1
        while true {
            do {
                return try await attemptOnce(request)
            } catch let error as InnerTubeError where error.isTransient && attempt < Self.maxAttempts {
                try await Task.sleep(for: retryDelay * attempt)
                attempt += 1
            }
        }
    }

    private func attemptOnce(_ request: URLRequest) async throws -> Data {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await transport(request)
        } catch let error as URLError where error.code != .cancelled {
            throw InnerTubeError.network(error.code)
        }
        guard let status = (response as? HTTPURLResponse)?.statusCode else { throw InnerTubeError.unexpectedResponse }
        if status == 401 { throw InnerTubeError.unauthorized }
        guard (200..<300).contains(status) else { throw InnerTubeError.httpStatus(status) }
        return data
    }
}
