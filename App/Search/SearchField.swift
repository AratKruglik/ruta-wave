import SwiftUI

struct SearchField: View {
    @Environment(SearchFieldModel.self) private var model
    @Environment(NavigationModel.self) private var navigation
    @Environment(NowPlayingModel.self) private var nowPlaying
    @FocusState private var isFocused: Bool

    private struct SuggestKey: Equatable {
        let text: String
        let isOpen: Bool
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: LiquidGlass.isAvailable ? Metrics.searchFieldHeight / 2 : Metrics.radiusCard)
    }

    var body: some View {
        HStack(spacing: Metrics.space12) {
            Image(systemName: "magnifyingglass")
                .font(.rwIcon(Metrics.iconBar))
                .foregroundStyle(.textTertiary)
                .accessibilityHidden(true)
            TextField("Search songs, albums, artists", text: Binding(get: { model.text }, set: model.edit))
                .textFieldStyle(.plain)
                .font(.rwBody)
                .foregroundStyle(.textPrimary)
                .lineLimit(1)
                .focused($isFocused)
                .focusEffectDisabled()
                .accessibilityLabel("Search")
                .onSubmit { perform(model.submit()) }
                .onKeyPress(.upArrow) {
                    model.moveHighlight(-1)
                    return .handled
                }
                .onKeyPress(.downArrow) {
                    model.moveHighlight(1)
                    return .handled
                }
                .onExitCommand { if !model.escape() { isFocused = false } }
        }
        .padding(.horizontal, Metrics.space12)
        .frame(height: Metrics.searchFieldHeight)
        .glassSurface(in: shape, fallback: .surfaceField)
        .contentShape(shape)
        .onTapGesture { isFocused = true }
        .onHover { model.isPointerOverField = $0 }
        .overlay(alignment: .topLeading) {
            if model.isDropdownVisible {
                SearchDropdown(model: model) { perform($0) }
                    .offset(y: Metrics.searchFieldHeight + Metrics.space4)
            }
        }
        .onChange(of: isFocused) { _, focused in
            navigation.isSearchFocused = focused
            model.focusChanged(focused)
        }
        .onChange(of: navigation.searchFocusRequests) {
            isFocused = true
            model.focusChanged(true)
        }
        .task(id: SuggestKey(text: model.text, isOpen: model.isOpen)) { await model.suggest() }
    }

    private func perform(_ action: SearchFieldModel.Action?) {
        guard let action else { return }
        isFocused = false
        switch action {
        case .search(let query):
            let route = Route.search(query: query, filter: nil)
            if navigation.path(for: navigation.selection).last != route { navigation.push(route) }
            navigation.isPlayerPagePresented = false
        case .open(let route):
            navigation.push(route)
            navigation.isPlayerPagePresented = false
        case .radio(let song):
            nowPlaying.startRadio(song)
        case .play(let item):
            nowPlaying.play(item)
        }
    }
}

#if DEBUG
#Preview("Empty") { SearchFieldPreview(.empty) }
#Preview("History") { SearchFieldPreview(.history) }
#Preview("Suggestions") { SearchFieldPreview(.suggestions) }

private struct SearchFieldPreview: View {
    @State private var model: SearchFieldModel
    private let variant: PreviewFixtures.SearchFieldVariant

    init(_ variant: PreviewFixtures.SearchFieldVariant) {
        self.variant = variant
        _model = State(initialValue: PreviewFixtures.searchFieldModel(variant))
    }

    var body: some View {
        SearchField()
            .frame(width: 560)
            .padding(Metrics.space32)
            .frame(width: 700, height: 460, alignment: .topLeading)
            .environment(model)
            .environment(NavigationModel())
            .environment(PreviewFixtures.nowPlaying())
            .background(.themeBase)
            .task {
                if variant != .empty { model.edit(variant == .suggestions ? "rad" : "") }
                await model.suggest()
            }
    }
}
#endif
