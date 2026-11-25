import Auth
import Foundation
import InnerTube
import Observation

@MainActor @Observable
final class AccountModel {
    enum State {
        case loading
        case loaded(AccountInfo)
        case failed
    }

    typealias Fetch = @MainActor (_ cookies: [HTTPCookie]) async throws -> AccountInfo
    /// Ends the session the cookies belong to; returns whether the user is still signed in afterwards.
    typealias Expire = @MainActor (_ cookies: [HTTPCookie]) async -> Bool

    private(set) var state: State = .loading

    @ObservationIgnored private let fetch: Fetch

    init(fetch: Fetch? = nil) {
        let client = InnerTubeClient()
        self.fetch = fetch ?? { try await client.accountMenu(cookies: $0) }
    }

    func load(session: AuthSession) async {
        guard case .signedIn(let cookies) = session.state else {
            state = .loading
            return
        }
        await load(cookies: cookies) { cookies in
            await session.expireSession(cookies: cookies)
            return session.state.isSignedIn
        }
    }

    func load(cookies: [HTTPCookie], expire: Expire) async {
        state = .loading
        do {
            let info = try await fetch(cookies)
            guard !Task.isCancelled else { return }
            state = .loaded(info)
        } catch InnerTubeError.unauthorized {
            let stillSignedIn = await expire(cookies)
            guard !Task.isCancelled, stillSignedIn else { return }
            state = .failed
        } catch {
            guard !Task.isCancelled else { return }
            state = .failed
        }
    }
}
