import Foundation
import InnerTube
import Observation

@MainActor @Observable
final class HistoryModel {
    enum State {
        case loading
        case loaded([HistoryDay])
        case empty
        case failed
    }

    private(set) var state: State = .loading

    @ObservationIgnored private let loader: LibraryLoader
    @ObservationIgnored private let credentials: @MainActor () -> Credentials?
    @ObservationIgnored private let toasts: ToastCenter
    @ObservationIgnored private var attempt = 0
    @ObservationIgnored private var loadedAttempt: Int?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var isRetired = false
    @ObservationIgnored private var pendingRemovals: Set<String> = []

    init(loader: LibraryLoader, credentials: @escaping @MainActor () -> Credentials?, toasts: ToastCenter) {
        self.loader = loader
        self.credentials = credentials
        self.toasts = toasts
    }

    var loadKey: Int { attempt }

    func load() async {
        guard !isRetired, loadedAttempt != attempt else { return }
        let captured = generation
        let key = attempt
        if case .loaded = state {} else { state = .loading }
        do {
            let days = try await loader.history(credentials()).filter { !$0.entries.isEmpty }
            guard !Task.isCancelled, !isRetired, generation == captured else { return }
            state = days.isEmpty ? .empty : .loaded(days)
            loadedAttempt = key
        } catch {
            guard !Task.isCancelled, !isRetired, generation == captured else { return }
            state = .failed
        }
    }

    func retry() {
        attempt += 1
    }

    /// Optimistic. The credentials are captured now, so a queued removal is never sent with another account.
    func remove(_ entry: HistoryEntry) {
        guard !isRetired, let token = entry.feedbackToken, !pendingRemovals.contains(token), case .loaded(var days) = state,
              let dayIndex = days.firstIndex(where: { $0.entries.contains(entry) }),
              let entryIndex = days[dayIndex].entries.firstIndex(of: entry) else { return }
        pendingRemovals.insert(token)
        let day = days[dayIndex]
        var entries = day.entries
        entries.remove(at: entryIndex)
        if entries.isEmpty {
            days.remove(at: dayIndex)
        } else {
            days[dayIndex] = HistoryDay(title: day.title, entries: entries)
        }
        state = days.isEmpty ? .empty : .loaded(days)
        let captured = generation
        let credentials = credentials()
        Task { [loader] in
            var failed = false
            do { try await loader.feedback(token, credentials) } catch { failed = true }
            guard generation == captured else { return }
            pendingRemovals.remove(token)
            guard failed else { return }
            restore(entry, in: day.title, dayIndex: dayIndex, entryIndex: entryIndex)
            toasts.show("Couldn't remove from history")
        }
    }

    func cancelInFlight() {
        isRetired = true
        generation += 1
        pendingRemovals = []
    }

    private func restore(_ entry: HistoryEntry, in title: String, dayIndex: Int, entryIndex: Int) {
        var days: [HistoryDay] = if case .loaded(let current) = state { current } else { [] }
        if let index = days.firstIndex(where: { $0.title == title }) {
            var entries = days[index].entries
            entries.insert(entry, at: min(entryIndex, entries.count))
            days[index] = HistoryDay(title: title, entries: entries)
        } else {
            days.insert(HistoryDay(title: title, entries: [entry]), at: min(dayIndex, days.count))
        }
        state = .loaded(days)
    }
}
