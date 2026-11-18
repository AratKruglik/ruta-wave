import os

final class GuestVisitor: Sendable {
    static let shared = GuestVisitor()

    struct Snapshot: Sendable {
        let value: String?
        let generation: Int
    }

    private let lock = OSAllocatedUnfairLock(initialState: Snapshot(value: nil, generation: 0))

    func snapshot() -> Snapshot {
        lock.withLock { $0 }
    }

    func reset() {
        lock.withLock { $0 = Snapshot(value: nil, generation: $0.generation + 1) }
    }

    // A response that outlives a sign-in or sign-out carries the previous identity and is dropped.
    func accept(_ raw: String?, generation: Int) {
        guard let value = Self.validated(raw) else { return }
        lock.withLock { state in
            if state.generation == generation { state = Snapshot(value: value, generation: generation) }
        }
    }

    static func validated(_ raw: String?) -> String? {
        guard let raw, (1...512).contains(raw.count) else { return nil }
        let allowed = raw.unicodeScalars.allSatisfy { scalar in
            switch scalar {
            case "A"..."Z", "a"..."z", "0"..."9", "-", "_", "%", "=": true
            default: false
            }
        }
        return allowed ? raw : nil
    }
}
