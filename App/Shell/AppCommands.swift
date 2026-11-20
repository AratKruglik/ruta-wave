import SwiftUI

struct AppCommands: Commands {
    let nowPlaying: NowPlayingModel
    @FocusedValue(\.navigation) private var navigation: NavigationModel?

    private var hasSong: Bool { nowPlaying.player.song != nil }

    var body: some Commands {
        CommandGroup(replacing: .printItem) {}
        CommandGroup(replacing: .saveItem) {}
        CommandMenu("Go") {
            Button("Back") { navigation?.back() }
                .keyboardShortcut("[")
                .disabled(navigation?.canGoBack != true)
            Button("Forward") { navigation?.forward() }
                .keyboardShortcut("]")
                .disabled(navigation?.canGoForward != true)
            Divider()
            ForEach(SidebarSection.allCases, id: \.self) { section in
                Button(String(localized: section.title)) { navigation?.select(section) }
                    .keyboardShortcut(KeyEquivalent(section.shortcutDigit))
                    .disabled(navigation == nil)
            }
        }
        CommandMenu("Controls") {
            Group {
                Button("Play / Pause", action: nowPlaying.togglePlay)
                Button("Previous", action: nowPlaying.previous)
                    .keyboardShortcut(.leftArrow)
                Button("Next", action: nowPlaying.next)
                    .keyboardShortcut(.rightArrow)
                Button("Seek Back 10 Seconds") { nowPlaying.skip(by: -10) }
                    .keyboardShortcut(.leftArrow, modifiers: [.command, .shift])
                Button("Seek Forward 10 Seconds") { nowPlaying.skip(by: 10) }
                    .keyboardShortcut(.rightArrow, modifiers: [.command, .shift])
                Divider()
                Button("Volume Up") { nowPlaying.adjustVolume(steps: 1) }
                    .keyboardShortcut(.upArrow)
                Button("Volume Down") { nowPlaying.adjustVolume(steps: -1) }
                    .keyboardShortcut(.downArrow)
                Button("Mute", action: nowPlaying.toggleMute)
                    .keyboardShortcut(.downArrow, modifiers: [.command, .option])
                Divider()
                Button("Repeat", action: nowPlaying.cycleRepeat)
                    .keyboardShortcut("r")
                Button("Shuffle", action: nowPlaying.toggleShuffle)
                    .keyboardShortcut("s")
                Button("Like", action: nowPlaying.toggleLike)
                    .keyboardShortcut("l", modifiers: [.command, .option])
                Button("Dislike", action: nowPlaying.toggleDislike)
                    .keyboardShortcut("d", modifiers: [.command, .option])
            }
            .disabled(!hasSong)
            Divider()
            Button("Player Page") { navigation?.isPlayerPagePresented.toggle() }
                .keyboardShortcut("p")
                .disabled(navigation == nil)
        }
    }
}
