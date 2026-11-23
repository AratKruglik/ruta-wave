import SwiftUI

struct AppCommands: Commands {
    let nowPlaying: NowPlayingModel
    @FocusedValue(\.navigation) private var navigation: NavigationModel?

    private var hasSong: Bool { nowPlaying.player.song != nil }
    /// A disabled item does not take its key, so the text field gets ⌘←, ⌘→ and friends.
    private var isEditingText: Bool { navigation?.isSearchFocused == true }

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Playlist…") { navigation?.requestNewPlaylist() }
                .keyboardShortcut("n")
                .disabled(navigation == nil)
        }
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
            Divider()
            Button("Search") { navigation?.requestSearchFocus() }
                .keyboardShortcut("f")
                .disabled(navigation == nil)
            Button("Go to Search Field") { navigation?.requestSearchFocus() }
                .keyboardShortcut("l")
                .disabled(navigation == nil)
        }
        CommandMenu("Controls") {
            Group {
                Button("Play / Pause", action: nowPlaying.togglePlay)
                Button("Previous", action: nowPlaying.previous)
                    .keyboardShortcut(.leftArrow)
                    .disabled(isEditingText)
                Button("Next", action: nowPlaying.next)
                    .keyboardShortcut(.rightArrow)
                    .disabled(isEditingText)
                Button("Seek Back 10 Seconds") { nowPlaying.skip(by: -10) }
                    .keyboardShortcut(.leftArrow, modifiers: [.command, .shift])
                    .disabled(isEditingText)
                Button("Seek Forward 10 Seconds") { nowPlaying.skip(by: 10) }
                    .keyboardShortcut(.rightArrow, modifiers: [.command, .shift])
                    .disabled(isEditingText)
                Divider()
                Button("Volume Up") { nowPlaying.adjustVolume(steps: 1) }
                    .keyboardShortcut(.upArrow)
                    .disabled(isEditingText)
                Button("Volume Down") { nowPlaying.adjustVolume(steps: -1) }
                    .keyboardShortcut(.downArrow)
                    .disabled(isEditingText)
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
