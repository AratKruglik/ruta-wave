import AppSettings
import Foundation
import InnerTube
import Testing

private final class Requests: @unchecked Sendable {
    private let lock = NSLock()
    private var countries: [String?] = []

    var all: [String?] { lock.withLock { countries } }
    func record(_ country: String?) { lock.withLock { countries.append(country) } }
}

private struct Failure: Error {}

private func isolatedPreferences() -> Preferences {
    Preferences(defaults: UserDefaults(suiteName: UUID().uuidString)!)
}

private func charts(selected: String?) -> ChartsPage {
    ChartsPage(
        page: BrowsePage(
            title: nil, chips: [], shelves: Page(items: [Shelf(title: "Top", layout: .list, items: [.song(Song(videoId: "v", title: "T"))])], continuation: nil)),
        countries: [ChartCountry(code: "US", name: "United States"), ChartCountry(code: "ZZ", name: "Global")],
        selectedCountry: selected)
}

@MainActor
struct ChartCountryTests {
    @Test func regionIsUsedUntilAnExplicitPick() {
        let preferences = isolatedPreferences()
        #expect(BrowseModel.chartsSource(preferences: preferences, region: "DE") == .charts(country: "DE"))
        #expect(BrowseModel.chartsSource(preferences: preferences, region: nil) == .charts(country: nil))
        preferences.chartCountry = "US"
        #expect(BrowseModel.chartsSource(preferences: preferences, region: "DE") == .charts(country: "US"))
    }

    @Test func explicitPickIsPersistedAndRequested() async {
        let preferences = isolatedPreferences()
        let requests = Requests()
        let model = BrowseModel(
            source: BrowseModel.chartsSource(preferences: preferences, region: "DE"),
            loader: BrowseLoader(
                page: { source, _ in
                    if case .charts(let country) = source { requests.record(country) }
                    return charts(selected: "US")
                },
                more: { _, _ in Page(items: [], continuation: nil) }),
            credentials: { nil }, preferences: preferences)
        await model.load()
        model.selectCountry("ZZ")
        await model.load()
        #expect(requests.all == ["DE", "ZZ"])
        #expect(preferences.chartCountry == "ZZ")
    }

    @Test func rejectedCountryRetriesOnceWithoutItAndKeepsTheStoredPick() async {
        let preferences = isolatedPreferences()
        preferences.chartCountry = "US"
        let requests = Requests()
        let model = BrowseModel(
            source: .charts(country: "US"),
            loader: BrowseLoader(
                page: { source, _ in
                    guard case .charts(let country) = source else { throw Failure() }
                    requests.record(country)
                    if country != nil { throw Failure() }
                    return charts(selected: "ZZ")
                },
                more: { _, _ in Page(items: [], continuation: nil) }),
            credentials: { nil }, preferences: preferences)
        await model.load()
        #expect(requests.all == ["US", nil])
        guard case .loaded(let content) = model.state else { Issue.record("expected loaded"); return }
        #expect(content.selectedCountry == "ZZ")
        #expect(preferences.chartCountry == "US")
    }

    @Test func countryMissingFromTheListShowsTheResponsesSelection() async {
        let preferences = isolatedPreferences()
        let model = BrowseModel(
            source: .charts(country: "DE"),
            loader: BrowseLoader(page: { _, _ in charts(selected: "ZZ") }, more: { _, _ in Page(items: [], continuation: nil) }),
            credentials: { nil }, preferences: preferences)
        await model.load()
        guard case .loaded(let content) = model.state else { Issue.record("expected loaded"); return }
        #expect(content.selectedCountry == "ZZ")
        #expect(preferences.chartCountry == nil)
    }
}
