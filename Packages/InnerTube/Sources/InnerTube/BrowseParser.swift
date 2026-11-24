extension JSONValue {
    // A first page or its continuation. Nil when the response holds neither.
    var sectionList: JSONValue? {
        self["continuationContents"]?["sectionListContinuation"]
            ?? self["contents"]?["singleColumnBrowseResultsRenderer"]?["tabs"]?[0]?["tabRenderer"]?["content"]?["sectionListRenderer"]
            ?? self["contents"]?["sectionListRenderer"]
    }
}

extension BrowsePage {
    init(browse json: JSONValue) throws(InnerTubeError) {
        guard let list = json.sectionList else { throw .unexpectedResponse }
        let about = list["contents"]?.array?.lazy.compactMap { $0["musicDescriptionShelfRenderer"] }.first
        self.init(
            title: json["header"]?["musicHeaderRenderer"]?["title"].flatMap(text),
            chips: ItemParser.chips(list["header"]?["chipCloudRenderer"]),
            shelves: Page(
                items: parseBlocks(list["contents"]?.array ?? [], ItemParser.section),
                continuation: list.nextContinuation),
            about: about.flatMap { shelf in
                shelf["description"].flatMap(text).map { DescriptionShelf(title: shelf["header"].flatMap(text), text: $0) }
            })
    }
}
