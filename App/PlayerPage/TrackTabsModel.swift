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

    private(set) var lyrics: Entry<Lyrics>?
    private(set) var related: Entry<BrowsePage>?
    private(set) var generation = 0

    @ObservationIgnored private let loader: TrackTabsLoader
    @ObservationIgnored private let credentials: @MainActor () -> Credentials?

    init(loader: TrackTabsLoader, credentials: @escaping @MainActor () -> Credentials?) {
        self.loader = loader
        self.credentials = credentials
    }

    func loadLyrics(_ id: String) async {
        let loader = loader
        await load(id, into: \.lyrics) { try await loader.lyrics(id, $0) }
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
