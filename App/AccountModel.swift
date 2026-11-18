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
        async let list = try? client.accountSwitcher(cookies: cookies, authUserIndex: 0)
        async let menu = try? client.accountMenu(cookies: cookies, authUserIndex: index)
        // An empty result means the parser no longer matches the response, so it is a list failure.
        let accounts = await list.flatMap { $0.isEmpty ? nil : $0 }
        guard !Task.isCancelled else { return }
        let resolved = AccountListItem.fallbackIndex(current: index, accounts: accounts)
        if resolved != index {
            session.authUserIndex = resolved
            return
        }
        let info = await menu
        guard !Task.isCancelled else { return }
        state = info.map { .loaded($0, accounts: accounts) } ?? .failed(accounts: accounts)
    }
}
