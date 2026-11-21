import AppSettings
import InnerTube
import Observation

@MainActor @Observable
final class BrowseStore {
    private(set) var home: BrowseModel
    private(set) var explore: BrowseModel
    private(set) var isReady = true

    @ObservationIgnored private let loader: BrowseLoader
    @ObservationIgnored private let searchLoader: SearchLoader
    @ObservationIgnored private let entityLoader: EntityLoader
    @ObservationIgnored private let toasts: ToastCenter
    @ObservationIgnored private let credentials: @MainActor () -> Credentials?
    @ObservationIgnored private let preferences: Preferences
    // shortcut: route models are kept for the whole identity; prune by live paths if memory shows up in Instruments.
    @ObservationIgnored private var routeModels: [Route: BrowseModel] = [:]
    @ObservationIgnored private var searchModels: [Route: SearchModel] = [:]
    @ObservationIgnored private var entityModels: [Route: EntityModel] = [:]
    private(set) var generation = 0

    init(
        loader: BrowseLoader, searchLoader: SearchLoader, entityLoader: EntityLoader, toasts: ToastCenter,
        credentials: @escaping @MainActor () -> Credentials?, preferences: Preferences = Preferences()
    ) {
        self.loader = loader
        self.searchLoader = searchLoader
        self.entityLoader = entityLoader
        self.toasts = toasts
        self.credentials = credentials
        self.preferences = preferences
        home = BrowseModel(source: .home(chipParams: nil), loader: loader, credentials: credentials, preferences: preferences)
        explore = BrowseModel(source: .browse(.explore), loader: loader, credentials: credentials, preferences: preferences)
    }

    func setReady(_ ready: Bool) {
        isReady = ready
        for model in [home, explore] + Array(routeModels.values) { model.isReady = ready }
        for model in searchModels.values { model.isReady = ready }
        for model in entityModels.values { model.isReady = ready }
    }

    func entityModel(for route: Route) -> EntityModel? {
        if let cached = entityModels[route] { return cached }
        let kind: EntityModel.Kind
        switch route {
        case .album(let browseId, let params): kind = .album(BrowseTarget(browseId: browseId, params: params))
        case .artist(let channelId): kind = .artist(browseId: channelId)
        case .playlist(let browseId): kind = .playlist(browseId: browseId)
        default: return nil
        }
        let model = EntityModel(kind: kind, loader: entityLoader, credentials: credentials, toasts: toasts)
        model.isReady = isReady
        entityModels[route] = model
        return model
    }

    /// A chip change opens a new route for the same query; the old chips seed the new model so the row stays put.
    func searchModel(for route: Route) -> SearchModel? {
        guard case .search(let query, let filter) = route else { return nil }
        if let cached = searchModels[route] { return cached }
        let chips = searchModels.first { $0.key.searchQuery == query }?.value.chips ?? []
        let model = SearchModel(query: query, filter: filter, chips: chips, loader: searchLoader, credentials: credentials)
        model.isReady = isReady
        searchModels[route] = model
        return model
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
        for model in searchModels.values { model.cancelInFlight() }
        for model in entityModels.values { model.cancelInFlight() }
        routeModels = [:]
        searchModels = [:]
        entityModels = [:]
        generation += 1
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

private extension Route {
    var searchQuery: String? {
        if case .search(let query, _) = self { query } else { nil }
    }
}
