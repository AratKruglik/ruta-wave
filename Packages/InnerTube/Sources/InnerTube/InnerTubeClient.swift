import Foundation

public enum InnerTubeError: Error, Sendable, Equatable {
    case missingSAPISID
    case unauthorized
    case network(URLError.Code)
    case httpStatus(Int)
    case unexpectedResponse
    /// A private, deleted or non-existent playlist, album or artist: the server answers 200 without `contents`.
    case notAvailable
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
    public let authUserIndex: Int

    public init(cookies: [HTTPCookie], authUserIndex: Int) {
        self.cookies = cookies
        self.authUserIndex = authUserIndex
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

    public func accountMenu(cookies: [HTTPCookie], authUserIndex: Int) async throws -> AccountInfo {
        try AccountInfo(accountMenu: await post("account/account_menu", cookies: cookies, authUserIndex: authUserIndex))
    }

    public func accountSwitcher(cookies: [HTTPCookie], authUserIndex: Int) async throws -> [AccountListItem] {
        let request = try InnerTubeRequest.makeGet(
            path: "/getAccountSwitcherEndpoint", cookies: cookies, authUserIndex: authUserIndex, now: Date())
        return AccountListItem.list(accountSwitcher: try await send(request))
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

    public static func resetGuestVisitor() {
        GuestVisitor.shared.reset()
    }

    func post(
        _ endpoint: String,
        body: [String: any Sendable] = [:],
        cookies: [HTTPCookie],
        authUserIndex: Int
    ) async throws -> JSONValue {
        let request = try InnerTubeRequest.make(
            endpoint: endpoint,
            body: body,
            cookies: cookies,
            authUserIndex: authUserIndex,
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

    private func fetchBrowse(_ target: BrowseTarget, credentials: Credentials?) async throws -> JSONValue {
        var body: [String: any Sendable] = ["browseId": target.browseId]
        body["params"] = target.params
        return try await fetch("browse", body: body, credentials: credentials)
    }

    private func fetch(_ endpoint: String, body: [String: any Sendable], credentials: Credentials?) async throws -> JSONValue {
        guard let credentials else { return try await postGuest(endpoint, body: body) }
        return try await post(endpoint, body: body, cookies: credentials.cookies, authUserIndex: credentials.authUserIndex)
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
