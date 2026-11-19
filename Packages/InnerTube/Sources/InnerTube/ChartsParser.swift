extension ChartsPage {
    init(charts json: JSONValue) throws(InnerTubeError) {
        let page = try BrowsePage(browse: json)
        // The country code exists only in the form mutations; options reference it by `formItemEntityKey`.
        let choices = (json["frameworkUpdates"]?["entityBatchUpdate"]?["mutations"]?.array ?? [])
            .compactMap { $0["payload"]?["musicFormBooleanChoice"] }
        let codes = Dictionary(
            choices.compactMap { choice in
                choice["id"]?.string.flatMap { id in choice["opaqueToken"]?.string.map { (id, $0) } }
            },
            uniquingKeysWith: { first, _ in first })
        let options = (json.sectionList?["contents"]?.array ?? []).lazy
            .compactMap { $0["musicShelfRenderer"]?["subheaders"]?[0]?["musicSideAlignedItemRenderer"]?["startItems"]?[0] }
            .compactMap { $0["musicSortFilterButtonRenderer"]?["menu"]?["musicMultiSelectMenuRenderer"]?["options"]?.array }
            .first ?? []
        let countries = options.compactMap { option -> ChartCountry? in
            guard let renderer = option["musicMultiSelectMenuItemRenderer"],
                  let code = renderer["formItemEntityKey"]?.string.flatMap({ codes[$0] }),
                  let name = renderer["title"].flatMap(text)
            else { return nil }
            return ChartCountry(code: code, name: name)
        }
        let selected = choices.first { $0["selected"]?.bool == true }?["opaqueToken"]?.string
        self.init(page: page, countries: countries, selectedCountry: selected)
    }
}
