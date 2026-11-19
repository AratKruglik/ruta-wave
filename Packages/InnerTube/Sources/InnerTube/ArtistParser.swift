extension ArtistPage {
    init(artist json: JSONValue) throws(InnerTubeError) {
        guard json["contents"] != nil else { throw .notAvailable }
        let header = json["header"]?["musicImmersiveHeaderRenderer"] ?? json["header"]?["musicVisualHeaderRenderer"]
        guard let header, let name = header["title"].flatMap(text), let list = json.sectionList else { throw .unexpectedResponse }
        let subscribe = header["subscriptionButton"]?["subscribeButtonRenderer"]
        let blocks = list["contents"]?.array ?? []
        let about = blocks.lazy.compactMap { $0["musicDescriptionShelfRenderer"] }.first
        self.init(
            name: name,
            thumbnailURL: header["thumbnail"]?["musicThumbnailRenderer"]?["thumbnail"].flatMap(lastThumbnailURL),
            subscriberCountText: subscribe?["longSubscriberCountText"].flatMap(text),
            isSubscribed: subscribe?["subscribed"]?.bool,
            channelId: subscribe?["channelId"]?.string,
            shuffle: header["playButton"]?["buttonRenderer"]?["navigationEndpoint"].flatMap(ItemParser.watchTarget),
            radio: header["startRadioButton"]?["buttonRenderer"]?["navigationEndpoint"].flatMap(ItemParser.watchTarget),
            shelves: parseBlocks(blocks.filter { $0["musicDescriptionShelfRenderer"] == nil }, ItemParser.section),
            description: about?["description"].flatMap(text) ?? header["description"].flatMap(text),
            viewCountText: about?["subheader"].flatMap(text))
    }
}
