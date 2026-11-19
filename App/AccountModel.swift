import Auth
import Foundation
import InnerTube
import Observation

@MainActor @Observable
final class AccountModel {
    enum State {
        case loading
        case loaded(AccountInfo, accounts: [AccountListItem]?)
        case failed(accounts: [AccountListItem]?)
    }

    private(set) var state: State = .loading

    @ObservationIgnored private let client = InnerTubeClient()

    func load(session: AuthSession) async {
        guard case .signedIn(let cookies) = session.state else { return }
        let index = session.authUserIndex
        state = .loading
        // The list always uses the primary session index: its authuser tokens are session-wide, and a stale index must not break it.
        async let list = result { try await client.accountSwitcher(cookies: cookies, authUserIndex: 0) }
        async let menu = result { try await client.accountMenu(cookies: cookies, authUserIndex: index) }
        let listResult = await list
        guard !Task.isCancelled else { return }
        if case .failure(InnerTubeError.unauthorized) = listResult {
            await expire(session, cookies: cookies, accounts: nil)
            return
        }
        // An empty result means the parser no longer matches the response, so it is a list failure.
        let accounts = (try? listResult.get()).flatMap { $0.isEmpty ? nil : $0 }
        let resolved = AccountListItem.fallbackIndex(current: index, accounts: accounts)
        if resolved != index {
            session.authUserIndex = resolved
            return
        }
        let menuResult = await menu
        guard !Task.isCancelled else { return }
        if case .failure(InnerTubeError.unauthorized) = menuResult {
            // A secondary account's menu 401 is not proof the whole session is dead; the primary list already passed.
            if index == 0 {
                await expire(session, cookies: cookies, accounts: accounts)
            } else {
                session.authUserIndex = 0
            }
            return
        }
        state = (try? menuResult.get()).map { .loaded($0, accounts: accounts) } ?? .failed(accounts: accounts)
    }

    private func expire(_ session: AuthSession, cookies: [HTTPCookie], accounts: [AccountListItem]?) async {
        await session.expireSession(cookies: cookies)
        guard !Task.isCancelled, session.state.isSignedIn else { return }
        state = .failed(accounts: accounts)
    }

    private func result<T: Sendable>(_ work: @Sendable () async throws -> T) async -> Result<T, any Error> {
        do { return .success(try await work()) } catch { return .failure(error) }
    }
}
