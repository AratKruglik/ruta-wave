import AppSettings
import InnerTube
import Observation

@MainActor @Observable
final class BrowseStore {
    private(set) var home: BrowseModel
    private(set) var explore: BrowseModel
    private(set) var isReady = true

    @ObservationIgnored private let loader: BrowseLoader
    @ObservationIgnored private let credentials: @MainActor () -> Credentials?
    @ObservationIgnored private let preferences: Preferences
    // shortcut: route models are kept for the whole identity; prune by live paths if memory shows up in Instruments.
    @ObservationIgnored private var routeModels: [Route: BrowseModel] = [:]

    init(
        loader: BrowseLoader, credentials: @escaping @MainActor () -> Credentials?, preferences: Preferences = Preferences()
    ) {
        self.loader = loader
        self.credentials = credentials
        self.preferences = preferences
        home = BrowseModel(source: .home(chipParams: nil), loader: loader, credentials: credentials, preferences: preferences)
        explore = BrowseModel(source: .browse(.explore), loader: loader, credentials: credentials, preferences: preferences)
    }

    func setReady(_ ready: Bool) {
        isReady = ready
        for model in [home, explore] + Array(routeModels.values) { model.isReady = ready }
    }

    func model(for route: Route) -> BrowseModel? {
        if let cached = routeModels[route] { return cached }
        guard let source = source(for: route) else { return nil }
        let model = makeModel(source)
        routeModels[route] = model
        return model
    }

    /// Called when the content identity changes: every model, continuation token and cached page is dropped.
    func reset() {
        for model in [home, explore] + Array(routeModels.values) { model.cancelInFlight() }
        routeModels = [:]
        home = makeModel(.home(chipParams: nil))
        explore = makeModel(.browse(.explore))
    }

    private func makeModel(_ source: BrowseModel.Source) -> BrowseModel {
        let model = BrowseModel(source: source, loader: loader, credentials: credentials, preferences: preferences)
        model.isReady = isReady
        return model
    }

    private func source(for route: Route) -> BrowseModel.Source? {
        switch route {
        case .explore(.newReleases): .browse(.newReleases)
        case .explore(.moods): .browse(.moodsAndGenres)
        case .explore(.mood(let params)): .browse(.moodCategory(params: params))
        case .explore(.charts): BrowseModel.chartsSource(preferences: preferences)
        case .more(let browseId, let params): .browse(BrowseTarget(browseId: browseId, params: params))
        default: nil
        }
    }
}
