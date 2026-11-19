extension JSONValue {
    // A first page or its continuation. Nil when the response holds neither.
    var sectionList: JSONValue? {
        self["continuationContents"]?["sectionListContinuation"]
            ?? self["contents"]?["singleColumnBrowseResultsRenderer"]?["tabs"]?[0]?["tabRenderer"]?["content"]?["sectionListRenderer"]
    }
}

extension BrowsePage {
    init(browse json: JSONValue) throws(InnerTubeError) {
        guard let list = json.sectionList else { throw .unexpectedResponse }
        self.init(
            title: json["header"]?["musicHeaderRenderer"]?["title"].flatMap(text),
            chips: ItemParser.chips(list["header"]?["chipCloudRenderer"]),
            shelves: Page(
                items: parseBlocks(list["contents"]?.array ?? [], ItemParser.section),
                continuation: list.nextContinuation))
    }
}
