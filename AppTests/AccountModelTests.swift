import Foundation
import InnerTube
import Testing

private struct Failure: Error {}

private let cookies = [HTTPCookie(properties: [.name: "SAPISID", .value: "v", .domain: ".youtube.com", .path: "/"])!]
private let info = AccountInfo(name: "Ann", handle: "@ann", avatarURL: nil)

@MainActor
struct AccountModelTests {
    @Test func unauthorizedExpiresTheSession() async {
        let model = AccountModel(fetch: { _ in throw InnerTubeError.unauthorized })
        var expired: [[HTTPCookie]] = []
        await model.load(cookies: cookies) { expired.append($0); return false }
        #expect(expired == [cookies])
        guard case .loading = model.state else { Issue.record("expected loading after sign-out"); return }
    }

    @Test func unauthorizedKeptSessionFails() async {
        let model = AccountModel(fetch: { _ in throw InnerTubeError.unauthorized })
        await model.load(cookies: cookies) { _ in true }
        guard case .failed = model.state else { Issue.record("expected failed"); return }
    }

    @Test func otherErrorFailsWithoutExpiring() async {
        let model = AccountModel(fetch: { _ in throw Failure() })
        var expireCalls = 0
        await model.load(cookies: cookies) { _ in expireCalls += 1; return true }
        #expect(expireCalls == 0)
        guard case .failed = model.state else { Issue.record("expected failed"); return }
    }

    @Test func successLoadsInfo() async {
        let model = AccountModel(fetch: { _ in info })
        await model.load(cookies: cookies) { _ in Issue.record("must not expire"); return true }
        guard case .loaded(let loaded) = model.state else { Issue.record("expected loaded"); return }
        #expect(loaded == info)
    }
}
