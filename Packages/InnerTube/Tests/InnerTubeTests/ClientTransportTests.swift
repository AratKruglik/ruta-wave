import Foundation
import os
import Testing
@testable import InnerTube

private let ok = Step.status(200, #"{"responseContext":{}}"#)
private let visitor = "CgtTWU5USEVUSUMxMjM%3D"

@Suite(.serialized) struct ClientTransportTests {
    private func failure(_ script: Script) async -> (any Error)? {
        do {
            _ = try await script.client().postGuest("browse")
            return nil
        } catch {
            return error
        }
    }

    @Test func networkErrorThenSuccessRetries() async throws {
        let script = Script([.fail(.timedOut), ok])
        _ = try await script.client().postGuest("browse")
        #expect(script.requests.count == 2)
    }

    @Test func serverErrorStopsAfterThreeAttempts() async {
        let script = Script([.status(503, "")])
        #expect(await failure(script) as? InnerTubeError == .httpStatus(503))
        #expect(script.requests.count == InnerTubeClient.maxAttempts)
    }

    @Test func offlineMapsToNetwork() async {
        let script = Script([.fail(.notConnectedToInternet)])
        #expect(await failure(script) as? InnerTubeError == .network(.notConnectedToInternet))
        #expect(script.requests.count == 3)
    }

    @Test(arguments: [400, 403, 429])
    func permanentStatusIsNotRetried(_ status: Int) async {
        let script = Script([.status(status, "")])
        #expect(await failure(script) as? InnerTubeError == .httpStatus(status))
        #expect(script.requests.count == 1)
    }

    @Test func unauthorizedIsNotRetried() async {
        let script = Script([.status(401, "")])
        #expect(await failure(script) as? InnerTubeError == .unauthorized)
        #expect(script.requests.count == 1)
    }

    @Test func malformedBodyIsNotRetried() async {
        let script = Script([.status(200, "not json")])
        #expect(await failure(script) as? InnerTubeError == .unexpectedResponse)
        #expect(script.requests.count == 1)
    }

    @Test func cancellationDuringBackoffStopsRetrying() async {
        let script = Script([.fail(.timedOut)])
        let client = script.client(retryDelay: .seconds(30))
        let task = Task { try await client.postGuest("browse") }
        while script.requests.isEmpty { await Task.yield() }
        task.cancel()
        do {
            _ = try await task.value
            Issue.record("expected cancellation")
        } catch {
            #expect(error is CancellationError)
        }
        #expect(script.requests.count == 1)
    }

    @Test func guestPagingKeepsVisitorAndSendsToken() async throws {
        GuestVisitor.shared.reset()
        let first = """
        {"responseContext":{"visitorData":"\(visitor)"},"contents":[{"known":"a"},{"mystery":1},{"known":"b"},
        {"continuationItemRenderer":{"continuationEndpoint":{"continuationCommand":{"token":"next-token"}}}}]}
        """
        let script = Script([.status(200, first), .status(200, #"{"contents":[{"known":"c"}]}"#)])
        let client = script.client()

        func page(_ json: JSONValue) -> Page<String> {
            let blocks = json["contents"]?.array ?? []
            return Page(items: parseBlocks(blocks) { $0["known"]?.string }, continuation: json["contents"]?.nextContinuation)
        }
        let one = page(try await client.postGuest("browse", body: ["browseId": "FEmusic_home"]))
        #expect(one == Page(items: ["a", "b"], continuation: "next-token"))
        let two = page(try await client.postGuest("browse", body: ["continuation": #require(one.continuation)]))
        #expect(two == Page(items: ["c"], continuation: nil))

        let request = script.requests[1]
        let body = try JSONDecoder().decode(JSONValue.self, from: #require(request.httpBody))
        #expect(body["continuation"]?.string == "next-token")
        #expect(body["context"]?["client"]?["clientVersion"]?.string?.isEmpty == false)
        #expect(request.value(forHTTPHeaderField: "X-Goog-Visitor-Id") == visitor)
        for header in ["Cookie", "Authorization", "X-Goog-AuthUser"] {
            #expect(request.value(forHTTPHeaderField: header) == nil)
        }
        GuestVisitor.shared.reset()
    }

    @Test func signedContinuationRequestCarriesTokenAndAuth() throws {
        let cookie = HTTPCookie(properties: [.name: "SAPISID", .value: "v", .domain: ".youtube.com", .path: "/"])!
        let request = try InnerTubeRequest.make(
            endpoint: "browse", body: ["continuation": "t"], cookies: [cookie], authUserIndex: 1, now: Date(), locale: .current)
        #expect(request.value(forHTTPHeaderField: "Authorization")?.hasPrefix("SAPISIDHASH ") == true)
        #expect(request.value(forHTTPHeaderField: "X-Goog-AuthUser") == "1")
        let body = try JSONDecoder().decode(JSONValue.self, from: #require(request.httpBody))
        #expect(body["continuation"]?.string == "t")
    }
}
