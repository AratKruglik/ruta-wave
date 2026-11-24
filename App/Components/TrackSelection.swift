import InnerTube

extension Song {
    /// Keyed by the row's id in the playlist: the same video can legitimately appear twice.
    var rowKey: String { playlistSetVideoId ?? videoId }
}

/// A multi-selection keyed by row, not index, so paging and removals never shift it onto other rows.
struct TrackSelection: Equatable {
    private(set) var keys: Set<String> = []
    private(set) var anchor: String?

    var isEmpty: Bool { keys.isEmpty }
    var count: Int { keys.count }

    func contains(_ key: String) -> Bool { keys.contains(key) }

    mutating func toggle(_ key: String) {
        if keys.remove(key) == nil { keys.insert(key) }
        anchor = key
    }

    /// Selects the rows between the anchor and `key`, both ends included. Without an anchor it selects `key` alone.
    mutating func extend(to key: String, in order: [String]) {
        guard let anchor, let from = order.firstIndex(of: anchor), let to = order.firstIndex(of: key) else {
            keys = [key]
            anchor = key
            return
        }
        keys = Set(order[min(from, to)...max(from, to)])
    }

    mutating func selectAll(_ order: [String]) {
        keys = Set(order)
        anchor = order.first
    }

    mutating func clear() {
        keys = []
        anchor = nil
    }

    /// Drops keys that are no longer in the list (a removal, a reload).
    mutating func retain(keys valid: [String]) {
        let valid = Set(valid)
        keys.formIntersection(valid)
        if let anchor, !valid.contains(anchor) { self.anchor = nil }
    }

    /// The one neighbour move that shifts the selected block a step up or down: `from` is the row jumping over the block
    /// and `to` is where it lands. Nil at an edge, or when the selection is not one contiguous block.
    func blockMove(in order: [String], up: Bool) -> (from: Int, to: Int)? {
        let indices = order.indices.filter { keys.contains(order[$0]) }
        guard let first = indices.first, let last = indices.last, indices.count == keys.count, last - first + 1 == indices.count
        else { return nil }
        if up { return first > 0 ? (first - 1, last) : nil }
        return last < order.count - 1 ? (last + 1, first) : nil
    }

    /// Moves queue keys (`q<index>`) with their rows after a queue move.
    mutating func shiftQueueKeys(by delta: Int) {
        func shifted(_ key: String) -> String {
            guard key.hasPrefix("q"), let index = Int(key.dropFirst()) else { return key }
            return "q\(index + delta)"
        }
        keys = Set(keys.map(shifted))
        anchor = anchor.map(shifted)
    }

    /// The selected keys in list order.
    func ordered(in order: [String]) -> [String] { order.filter(keys.contains) }
}
