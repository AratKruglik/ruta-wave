import Foundation
import Observation

@MainActor @Observable
final class NavigationModel {
    private(set) var selection: SidebarSection = .home
    var isPlayerPagePresented = false
    private(set) var scrollToTopRequests: [SidebarSection: Int] = [:]
    private(set) var searchFocusRequests = 0
    private(set) var newPlaylistRequests = 0
    private(set) var pendingPlaylistVideoIds: [String] = []
    var isSearchFocused = false
    private var paths: [SidebarSection: [Route]] = [:]
    /// The first route is the next one forward.
    private var forwardRoutes: [SidebarSection: [Route]] = [:]

    /// What survives a relaunch: the section and each section's back stack. Forward stacks and the player page do not.
    struct Snapshot: Codable, Equatable {
        var version = 1
        var section: SidebarSection
        var paths: [SidebarSection: [Route]]
        var isSignedIn: Bool
    }

    static let maxRestoredDepth = 32

    func snapshot(isSignedIn: Bool) -> Snapshot {
        Snapshot(section: selection, paths: paths.filter { !$0.value.isEmpty }, isSignedIn: isSignedIn)
    }

    /// Anything unreadable, of another version or implausibly deep starts at Home. Routes that belonged to another
    /// identity than the current one are dropped with the same rules sign-out uses.
    /// A `startingPage` opens at the root of that section; the other sections keep their stacks.
    static func restored(
        from data: Data?, isSignedIn: Bool, startingPage: SidebarSection? = nil
    ) -> NavigationModel {
        let model = NavigationModel()
        if let data, let saved = try? JSONDecoder().decode(Snapshot.self, from: data), saved.version == 1,
           saved.paths.values.allSatisfy({ $0.count <= maxRestoredDepth }) {
            model.selection = saved.section
            model.paths = saved.paths
            if saved.isSignedIn, !isSignedIn {
                model.dropAccountRoutes()
            } else if saved.isSignedIn != isSignedIn {
                model.dropIdentityRoutes()
            }
        }
        if let startingPage {
            model.selection = startingPage == .library && !isSignedIn ? .home : startingPage
            model.paths[model.selection] = []
        }
        return model
    }

    var canGoBack: Bool { !path(for: selection).isEmpty }
    var canGoForward: Bool { !(forwardRoutes[selection] ?? []).isEmpty }

    func path(for section: SidebarSection) -> [Route] {
        paths[section] ?? []
    }

    func setPath(_ newPath: [Route], for section: SidebarSection) {
        let old = path(for: section)
        if newPath.count < old.count, old.starts(with: newPath) {
            forwardRoutes[section] = Array(old[newPath.count...]) + (forwardRoutes[section] ?? [])
        } else if newPath != old {
            forwardRoutes[section] = []
        }
        paths[section] = newPath
    }

    func select(_ section: SidebarSection) {
        isPlayerPagePresented = false
        if section == selection {
            popToRoot(section)
        } else {
            selection = section
        }
    }

    func goHome() {
        isPlayerPagePresented = false
        selection = .home
        popToRoot(.home)
    }

    func push(_ route: Route) {
        isPlayerPagePresented = false
        paths[selection, default: []].append(route)
        forwardRoutes[selection] = []
    }

    /// A filter change swaps the page instead of stacking another one.
    func replaceLast(_ route: Route) {
        isPlayerPagePresented = false
        var current = path(for: selection)
        guard !current.isEmpty else {
            push(route)
            return
        }
        current[current.count - 1] = route
        paths[selection] = current
        forwardRoutes[selection] = []
    }

    func requestSearchFocus() {
        isPlayerPagePresented = false
        searchFocusRequests += 1
    }

    func requestNewPlaylist(videoIds: [String] = []) {
        pendingPlaylistVideoIds = videoIds
        newPlaylistRequests += 1
    }

    /// With the player page open, Back only closes it.
    func back() {
        if isPlayerPagePresented {
            isPlayerPagePresented = false
            return
        }
        guard let route = paths[selection]?.popLast() else { return }
        forwardRoutes[selection, default: []].insert(route, at: 0)
    }

    func forward() {
        isPlayerPagePresented = false
        guard var queued = forwardRoutes[selection], !queued.isEmpty else { return }
        let route = queued.removeFirst()
        forwardRoutes[selection] = queued
        paths[selection, default: []].append(route)
    }

    func dropAccountRoutes() {
        paths[.library] = []
        forwardRoutes[.library] = []
        dropRoutes(where: \.requiresAccount)
        if selection == .library { selection = .home }
    }

    func dropIdentityRoutes() {
        dropRoutes(where: \.requiresAccount)
    }

    /// Truncates each stack at the first match, because later pages were reached through it.
    /// Forward entries follow the same rule: a truncated back path clears them, otherwise they are cut at the first match.
    private func dropRoutes(where isDropped: (Route) -> Bool) {
        for section in SidebarSection.allCases {
            if let index = path(for: section).firstIndex(where: isDropped) {
                paths[section] = Array(path(for: section)[..<index])
                forwardRoutes[section] = []
            } else if let forward = forwardRoutes[section], let index = forward.firstIndex(where: isDropped) {
                forwardRoutes[section] = Array(forward[..<index])
            }
        }
    }

    private func popToRoot(_ section: SidebarSection) {
        paths[section] = []
        forwardRoutes[section] = []
        scrollToTopRequests[section, default: 0] += 1
    }
}
