import Foundation
import InnerTube

final class CallLog: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [String] = []

    var all: [String] { lock.withLock { recorded } }
    func record(_ call: String) { lock.withLock { recorded.append(call) } }
}

struct LibraryStubFailure: Error {}

extension LibraryLoader {
    static let stub = LibraryLoader(
        page: { _, _ in throw LibraryStubFailure() }, more: { _, _ in throw LibraryStubFailure() }, history: { _ in [] },
        feedback: { _, _ in })
}
