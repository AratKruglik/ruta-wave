import Foundation
import os
@testable import InnerTube

enum Step: Sendable {
    case status(Int, String)
    case fail(URLError.Code)

    static func fixture(_ name: String) throws -> Step {
        .status(200, String(decoding: try Fixture.data(name), as: UTF8.self))
    }
}

final class Script: Sendable {
    private let state: OSAllocatedUnfairLock<(steps: [Step], requests: [URLRequest])>

    init(_ steps: [Step]) {
        state = OSAllocatedUnfairLock(initialState: (steps, []))
    }

    var requests: [URLRequest] { state.withLock { $0.requests } }

    func client(retryDelay: Duration = .zero) -> InnerTubeClient {
        InnerTubeClient(transport: { [self] request in
            let step = state.withLock { state in
                state.requests.append(request)
                return state.steps.count > 1 ? state.steps.removeFirst() : state.steps[0]
            }
            switch step {
            case .status(let code, let body):
                let response = HTTPURLResponse(url: request.url!, statusCode: code, httpVersion: nil, headerFields: nil)!
                return (Data(body.utf8), response)
            case .fail(let code):
                throw URLError(code)
            }
        }, retryDelay: retryDelay)
    }
}
