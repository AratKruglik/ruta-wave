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

    private(set) var state: State = .loading

    @ObservationIgnored private let client = InnerTubeClient()

    func load(session: AuthSession) async {
        guard case .signedIn(let cookies) = session.state else { return }
        let index = session.authUserIndex
        state = .loading
        do {
            let info = try await client.accountMenu(cookies: cookies, authUserIndex: index)
            guard !Task.isCancelled else { return }
            state = .loaded(info)
        } catch {
            if !Task.isCancelled { state = .failed }
        }
    }
}
