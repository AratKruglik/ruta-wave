import Foundation

public enum InnerTubeError: Error, Sendable, Equatable {
    case missingSAPISID
    case httpStatus(Int)
    case unexpectedResponse
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
    private let session: URLSession

    public init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        session = URLSession(configuration: configuration, delegate: RejectRedirects(), delegateQueue: nil)
    }

    public func accountMenu(cookies: [HTTPCookie], authUserIndex: Int) async throws -> AccountInfo {
        try AccountInfo(accountMenu: await post("account/account_menu", cookies: cookies, authUserIndex: authUserIndex))
    }

    public func accountSwitcher(cookies: [HTTPCookie], authUserIndex: Int) async throws -> [AccountListItem] {
        let request = try InnerTubeRequest.makeGet(
            path: "/getAccountSwitcherEndpoint", cookies: cookies, authUserIndex: authUserIndex, now: Date())
        return AccountListItem.list(accountSwitcher: try await send(request))
    }

    private func post(
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

    private func send(_ request: URLRequest) async throws -> JSONValue {
        let (data, response) = try await session.data(for: request)
        guard let status = (response as? HTTPURLResponse)?.statusCode else { throw InnerTubeError.unexpectedResponse }
        guard (200..<300).contains(status) else { throw InnerTubeError.httpStatus(status) }
        return try JSONValue(response: data)
    }
}
