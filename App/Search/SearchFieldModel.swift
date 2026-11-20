import Foundation
import InnerTube
import Observation

@MainActor @Observable
final class SearchFieldModel {
    enum Row: Equatable {
        case history(SearchHistoryEntry)
        case query(String)
        case item(MusicItem)
    }

    enum Action: Equatable {
        case search(String)
        case open(Route)
        case radio(Song)
        case play(MusicItem)
    }

    static let historyLimit = 7
    static let debounce = Duration.milliseconds(150)

    private(set) var text = ""
    private(set) var rows: [Row] = []
    private(set) var isOpen = false
    private(set) var highlighted: Int?
    @ObservationIgnored var isPointerOverField = false
    @ObservationIgnored var isPointerOverDropdown = false

    @ObservationIgnored private let loader: SearchLoader
    @ObservationIgnored private let credentials: @MainActor () -> Credentials?
    @ObservationIgnored private let toasts: ToastCenter
    @ObservationIgnored private let sleep: @Sendable (Duration) async throws -> Void
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var identityGeneration = 0
    @ObservationIgnored private var history: [SearchHistoryEntry] = []
    @ObservationIgnored private var queries: [String] = []
    @ObservationIgnored private var items: [MusicItem] = []
    @ObservationIgnored private var pendingRemovals: Set<String> = []

    init(
        loader: SearchLoader, credentials: @escaping @MainActor () -> Credentials?, toasts: ToastCenter,
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        self.loader = loader
        self.credentials = credentials
        self.toasts = toasts
        self.sleep = sleep
    }

    var isDropdownVisible: Bool { isOpen && !rows.isEmpty }

    func edit(_ newText: String) {
        guard newText != text else { return }
        text = newText
        isOpen = true
        highlighted = nil
        generation += 1
    }

    /// Run from `.task(id:)`, so the next keystroke cancels it.
    func suggest() async {
        guard isOpen else { return }
        let captured = generation
        let input = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let credentials = credentials()
        if input.isEmpty {
            guard credentials != nil else {
                clearRows()
                return
            }
        } else {
            do { try await sleep(Self.debounce) } catch { return }
            guard !Task.isCancelled, generation == captured else { return }
        }
        do {
            let suggestions = try await loader.suggestions(input, credentials)
            guard !Task.isCancelled, generation == captured else { return }
            history = suggestions.history
            queries = suggestions.queries
            items = suggestions.items
            rebuildRows()
        } catch {
            guard !Task.isCancelled, generation == captured else { return }
            clearRows()
        }
    }

    func focusChanged(_ focused: Bool) {
        if focused {
            isOpen = true
        } else if !isPointerOverDropdown {
            close()
        }
    }

    func moveHighlight(_ delta: Int) {
        guard !rows.isEmpty else { return }
        isOpen = true
        guard let current = highlighted else {
            highlighted = delta > 0 ? 0 : rows.count - 1
            return
        }
        highlighted = ((current + delta) % rows.count + rows.count) % rows.count
    }

    func submit() -> Action? {
        if let highlighted, rows.indices.contains(highlighted) { return activate(rows[highlighted]) }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        close()
        return .search(trimmed)
    }

    func activate(_ row: Row) -> Action {
        close()
        switch row {
        case .history(let entry):
            text = entry.query
            return .search(entry.query)
        case .query(let query):
            text = query
            return .search(query)
        case .item(let item):
            if let route = item.route { return .open(route) }
            if case .song(let song) = item { return .radio(song) }
            return .play(item)
        }
    }

    /// Esc ladder: close the dropdown, then clear the text, then let the caller give up focus.
    func escape() -> Bool {
        if isDropdownVisible {
            close()
            return true
        }
        guard !text.isEmpty else { return false }
        text = ""
        close()
        return true
    }

    func remove(_ entry: SearchHistoryEntry) {
        let token = entry.feedbackToken
        guard !pendingRemovals.contains(token), let index = history.firstIndex(of: entry) else { return }
        pendingRemovals.insert(token)
        history.remove(at: index)
        highlighted = nil
        rebuildRows()
        let identity = identityGeneration
        let credentials = credentials()
        Task {
            var failed = false
            do { try await loader.feedback(token, credentials) } catch { failed = true }
            guard identityGeneration == identity else { return }
            pendingRemovals.remove(token)
            history.removeAll { $0.feedbackToken == token }
            if failed { history.insert(entry, at: min(index, history.count)) }
            rebuildRows()
            guard failed else { return }
            toasts.show("Couldn't remove the search")
        }
    }

    func close() {
        isOpen = false
        highlighted = nil
        generation += 1
    }

    func mouseDownInWindow() {
        if isOpen, !isPointerOverField, !isPointerOverDropdown { close() }
    }

    func showQuery(_ query: String) {
        text = query
        close()
    }

    func reset() {
        text = ""
        history = []
        queries = []
        items = []
        pendingRemovals = []
        rows = []
        isOpen = false
        highlighted = nil
        generation += 1
        identityGeneration += 1
    }

    private func clearRows() {
        history = []
        queries = []
        items = []
        rows = []
        highlighted = nil
    }

    private func rebuildRows() {
        let visibleHistory = history.filter { !pendingRemovals.contains($0.feedbackToken) }.prefix(Self.historyLimit)
        rows = visibleHistory.map(Row.history) + queries.map(Row.query) + items.map(Row.item)
        highlighted = nil
    }
}
