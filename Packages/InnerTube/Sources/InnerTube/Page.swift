public struct Page<Item: Sendable>: Sendable {
    public let items: [Item]
    public let continuation: String?

    public init(items: [Item], continuation: String?) {
        self.items = items
        self.continuation = continuation
    }
}

extension Page: Equatable where Item: Equatable {}

extension JSONValue {
    // Called on a list container: a shelf renderer object or the `contents` array itself.
    var nextContinuation: String? {
        let older = self["continuations"]?[0]?["nextContinuationData"]?["continuation"]?.string
        let radio = self["continuations"]?[0]?["nextRadioContinuationData"]?["continuation"]?.string
        let newer = (self["contents"]?.array ?? array)?.last?["continuationItemRenderer"]?["continuationEndpoint"]?["continuationCommand"]?["token"]?.string
        return [older, radio, newer].lazy.compactMap { $0 }.first { !$0.isEmpty }
    }
}
