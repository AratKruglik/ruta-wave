import InnerTube
import Observation

@MainActor @Observable
final class TrackTabsModel {
    enum Phase<Value> {
        case loading
        case loaded(Value)
        case empty
        case failed
    }

    struct Entry<Value> {
        let id: String
        var phase: Phase<Value>
    }

    struct LyricsContent {
        let plain: Lyrics?
        let timed: TimedLyrics?
    }

    private(set) var lyrics: Entry<Lyrics>?
    private(set) var timedLyrics: Entry<TimedLyrics>?
    private(set) var related: Entry<BrowsePage>?
    private(set) var generation = 0

    @ObservationIgnored private let loader: TrackTabsLoader
    @ObservationIgnored private let credentials: @MainActor () -> Credentials?

    init(loader: TrackTabsLoader, credentials: @escaping @MainActor () -> Credentials?) {
        self.loader = loader
        self.credentials = credentials
    }

    func loadLyrics(_ id: String) async {
        async let plain: Void = loadPlainLyrics(id)
        async let timed: Void = loadTimedLyrics(id)
        _ = await (plain, timed)
    }

    private func loadPlainLyrics(_ id: String) async {
        let loader = loader
        await load(id, into: \.lyrics) { try await loader.lyrics(id, $0) }
    }

    private func loadTimedLyrics(_ id: String) async {
        let loader = loader
        await load(id, into: \.timedLyrics) { _ in try await loader.timedLyrics(id) }
    }

    /// Plain lyrics decide the screen; timed lines swap in when they arrive. Plain missing waits for the timed answer.
    func lyricsPhase(_ id: String) -> Phase<LyricsContent> {
        let plain = lyrics.flatMap { $0.id == id ? $0.phase : nil } ?? .loading
        let timed = timedLyrics.flatMap { $0.id == id ? $0.phase : nil } ?? .loading
        let timedLines: TimedLyrics? = if case .loaded(let lines) = timed { lines } else { nil }
        switch plain {
        case .loading: return .loading
        case .failed: return .failed
        case .loaded(let text): return .loaded(LyricsContent(plain: text, timed: timedLines))
        case .empty:
            if let timedLines { return .loaded(LyricsContent(plain: nil, timed: timedLines)) }
            if case .loading = timed { return .loading }
            return .empty
        }
    }

    func loadRelated(_ id: String) async {
        let loader = loader
        await load(id, into: \.related) { credentials in
            let page = try await loader.related(id, credentials)
            return page.shelves.items.isEmpty && page.about == nil ? nil : page
        }
    }

    /// A sign-in, sign-out or account switch changes what the server returns.
    func reset() {
        lyrics = nil
        timedLyrics = nil
        related = nil
        generation += 1
    }

    private func load<Value>(
        _ id: String, into slot: ReferenceWritableKeyPath<TrackTabsModel, Entry<Value>?>,
        fetch: (Credentials?) async throws -> Value?
    ) async {
        if let entry = self[keyPath: slot], entry.id == id {
            switch entry.phase {
            case .loaded, .empty: return
            case .loading, .failed: break
            }
        }
        let captured = generation
        self[keyPath: slot] = Entry(id: id, phase: .loading)
        let phase: Phase<Value>
        do {
            phase = try await fetch(credentials()).map { .loaded($0) } ?? .empty
        } catch {
            phase = .failed
        }
        guard !Task.isCancelled, generation == captured, self[keyPath: slot]?.id == id else { return }
        self[keyPath: slot] = Entry(id: id, phase: phase)
    }
}
