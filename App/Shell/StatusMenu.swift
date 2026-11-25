import AppKit
import AppSettings

/// The menu bar item and the Dock menu. Both menus are built when they open, so they never go stale or need observing.
@MainActor
final class StatusMenu: NSObject {
    private let nowPlaying: NowPlayingModel
    private let showMainWindow: () -> Void
    private let showMiniPlayer: () -> Void
    private var item: NSStatusItem?

    init(nowPlaying: NowPlayingModel, showMainWindow: @escaping () -> Void, showMiniPlayer: @escaping () -> Void) {
        self.nowPlaying = nowPlaying
        self.showMainWindow = showMainWindow
        self.showMiniPlayer = showMiniPlayer
    }

    func setVisible(_ isVisible: Bool) {
        if isVisible, item == nil {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            if let button = item.button {
                button.image = NSImage(systemSymbolName: "music.note", accessibilityDescription: "RutaWave")
                button.toolTip = "RutaWave"
                button.target = self
                button.action = #selector(clicked)
                button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            }
            self.item = item
        } else if !isVisible, let item {
            NSStatusBar.system.removeStatusItem(item)
            self.item = nil
        }
    }

    func dockMenu() -> NSMenu {
        playbackMenu()
    }

    private func statusMenu() -> NSMenu {
        let menu = playbackMenu()
        menu.addItem(.separator())
        menu.addItem(item(String(localized: "Mini Player"), #selector(miniPlayer)))
        menu.addItem(item(String(localized: "Show RutaWave"), #selector(show)))
        menu.addItem(withTitle: String(localized: "Quit RutaWave"), action: #selector(NSApplication.terminate), keyEquivalent: "q")
        return menu
    }

    private func playbackMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        let player = nowPlaying.player
        let hasSong = player.song != nil
        let title = player.song.map { "\($0.title) — \($0.artist)" } ?? String(localized: "Not playing")
        let header = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        menu.addItem(.separator())
        menu.addItem(item(String(localized: player.isPaused ? "Play" : "Pause"), #selector(togglePlay), isEnabled: hasSong))
        menu.addItem(item(String(localized: "Previous"), #selector(previous), isEnabled: hasSong))
        menu.addItem(item(String(localized: "Next"), #selector(next), isEnabled: hasSong))
        return menu
    }

    private func item(_ title: String, _ action: Selector, isEnabled: Bool = true) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.isEnabled = isEnabled
        return item
    }

    @objc private func clicked() {
        let event = NSApp.currentEvent
        let wantsMenu = event?.type == .rightMouseUp || event?.modifierFlags.contains(.option) == true
        if !wantsMenu, Preferences().menuBarClickTogglesPlay, nowPlaying.player.song != nil {
            nowPlaying.togglePlay()
            return
        }
        guard let item else { return }
        item.menu = statusMenu()
        item.button?.performClick(nil)
        item.menu = nil
    }

    @objc private func togglePlay() { nowPlaying.togglePlay() }
    @objc private func previous() { nowPlaying.previous() }
    @objc private func next() { nowPlaying.next() }
    @objc private func show() { showMainWindow() }
    @objc private func miniPlayer() { showMiniPlayer() }
}
