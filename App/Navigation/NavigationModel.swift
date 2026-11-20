import Foundation
import Observation

@MainActor @Observable
final class NavigationModel {
    private(set) var selection: SidebarSection = .home
    var isPlayerPagePresented = false
    private(set) var scrollToTopRequests: [SidebarSection: Int] = [:]
    private var paths: [SidebarSection: [Route]] = [:]
    /// The first route is the next one forward.
    private var forwardRoutes: [SidebarSection: [Route]] = [:]

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
        if section == selection {
            popToRoot(section)
        } else {
            selection = section
        }
    }

    func goHome() {
        selection = .home
        popToRoot(.home)
    }

    func push(_ route: Route) {
        paths[selection, default: []].append(route)
        forwardRoutes[selection] = []
    }

    func back() {
        guard let route = paths[selection]?.popLast() else { return }
        forwardRoutes[selection, default: []].insert(route, at: 0)
    }

    func forward() {
        guard var queued = forwardRoutes[selection], !queued.isEmpty else { return }
        let route = queued.removeFirst()
        forwardRoutes[selection] = queued
        paths[selection, default: []].append(route)
    }

    func dropAccountRoutes() {
        paths[.library] = []
        forwardRoutes[.library] = []
        for section in SidebarSection.allCases {
            if let index = path(for: section).firstIndex(where: \.requiresAccount) {
                paths[section] = Array(path(for: section)[..<index])
            }
            forwardRoutes[section] = forwardRoutes[section]?.filter { !$0.requiresAccount }
        }
        if selection == .library { selection = .home }
    }

    private func popToRoot(_ section: SidebarSection) {
        paths[section] = []
        forwardRoutes[section] = []
        scrollToTopRequests[section, default: 0] += 1
    }
}
