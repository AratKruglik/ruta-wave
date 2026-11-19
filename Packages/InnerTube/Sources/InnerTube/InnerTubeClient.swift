import Foundation

public enum InnerTubeError: Error, Sendable, Equatable {
    case missingSAPISID
    case unauthorized
    case network(URLError.Code)
    case httpStatus(Int)
    case unexpectedResponse
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

    public static func resetGuestVisitor() {
        GuestVisitor.shared.reset()
    }

    func post(
        _ endpoint: String,
        body: [String: String] = [:],
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

    func postGuest(_ endpoint: String, body: [String: String] = [:]) async throws -> JSONValue {
        let snapshot = GuestVisitor.shared.snapshot()
        let request = try InnerTubeRequest.makeGuest(
            endpoint: endpoint, body: body, visitorData: snapshot.value, locale: .current)
        let json = try await send(request)
        GuestVisitor.shared.accept(json["responseContext"]?["visitorData"]?.string, generation: snapshot.generation)
        return json
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
