public struct Shelf: Sendable, Equatable {
    public enum Layout: Sendable, Equatable {
        /// A carousel of two-row items.
        case cards
        /// A carousel of list rows (Quick picks, Trending, charts).
        case rows
        case grid
        /// A plain list shelf.
        case list
    }

    public let title: String?
    public let strapline: String?
    public let more: BrowseTarget?
    public let layout: Layout
    public let items: [MusicItem]

    public init(title: String?, strapline: String? = nil, more: BrowseTarget? = nil, layout: Layout, items: [MusicItem]) {
        self.title = title
        self.strapline = strapline
        self.more = more
        self.layout = layout
        self.items = items
    }
}

/// A Home chip uses `target`; a search filter chip uses `searchParams`.
public struct Chip: Sendable, Equatable {
    public let title: String
    public let target: BrowseTarget?
    public let searchParams: String?
    public let isSelected: Bool
    /// A queue chip (radio filter) uses `watchTarget`.
    public let watchTarget: WatchTarget?

    public init(
        title: String, target: BrowseTarget? = nil, searchParams: String? = nil, isSelected: Bool = false,
        watchTarget: WatchTarget? = nil
    ) {
        self.title = title
        self.target = target
        self.searchParams = searchParams
        self.watchTarget = watchTarget
        self.isSelected = isSelected
    }
}

public struct BrowsePage: Sendable, Equatable {
    public let title: String?
    public let chips: [Chip]
    public let shelves: Page<Shelf>

    public init(title: String?, chips: [Chip], shelves: Page<Shelf>) {
        self.title = title
        self.chips = chips
        self.shelves = shelves
    }
}

public struct ChartCountry: Sendable, Equatable {
    public let code: String
    public let name: String

    public init(code: String, name: String) {
        self.code = code
        self.name = name
    }
}

public struct ChartsPage: Sendable, Equatable {
    public let page: BrowsePage
    public let countries: [ChartCountry]
    public let selectedCountry: String?

    public init(page: BrowsePage, countries: [ChartCountry], selectedCountry: String?) {
        self.page = page
        self.countries = countries
        self.selectedCountry = selectedCountry
    }
}
