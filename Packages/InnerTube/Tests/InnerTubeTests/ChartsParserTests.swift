import Testing
@testable import InnerTube

@Suite struct ChartsParserTests {
    private func charts() throws -> ChartsPage {
        try ChartsPage(charts: Fixture.json("charts"))
    }

    @Test func countriesJoinOptionsAndFormMutations() throws {
        let page = try charts()
        #expect(page.countries.map(\.code) == ["ZZ", "AR", "DE", "US"])
        #expect(page.countries.first { $0.code == "ZZ" }?.name == "Global")
        #expect(page.selectedCountry == "US")
    }

    @Test func rankedArtistsCarryPositionAndTrend() throws {
        let artists = try #require(try charts().page.shelves.items.first { $0.title == "Top artists" })
        #expect(artists.layout == .rows)
        let ranks = artists.items.compactMap { item -> ChartRank? in
            guard case .artist(let artist) = item else { return nil }
            return artist.rank
        }
        #expect(ranks.map(\.position) == Array(1...ranks.count))
        #expect(Set(ranks.compactMap(\.trend)).isSuperset(of: [.neutral, .up]))
    }

    @Test func podcastShelfAndCountrySelectorAreNotShelves() throws {
        let titles = try charts().page.shelves.items.map(\.title)
        #expect(titles == ["Video charts", "Genres", "Top artists"])
    }

    @Test func pageWithoutFormDataHasNoCountries() throws {
        let page = try ChartsPage(charts: Fixture.json("explore"))
        #expect(page.countries.isEmpty)
        #expect(page.selectedCountry == nil)
    }
}
