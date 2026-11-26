import Foundation
import Testing
@testable import AppSettings

struct PreferencesTests {
    private let suite = "PreferencesTests-\(UUID().uuidString)"

    private func makePreferences() -> (Preferences, UserDefaults) {
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return (Preferences(defaults: defaults), defaults)
    }

    @Test func defaults() {
        let (preferences, _) = makePreferences()
        #expect(!preferences.sidebarCollapsed)
        #expect(preferences.volume == 1)
        #expect(preferences.repeatMode == "off")
        #expect(!preferences.shuffle)
        #expect(preferences.appLanguage == nil)
    }

    @Test func navigationStateRoundTripsAndRefusesOversize() {
        let (preferences, _) = makePreferences()
        #expect(preferences.navigationState == nil)
        preferences.navigationState = Data([1, 2, 3])
        #expect(preferences.navigationState == Data([1, 2, 3]))
        preferences.navigationState = Data(count: Preferences.maxNavigationStateBytes + 1)
        #expect(preferences.navigationState == nil)
        preferences.navigationState = nil
        #expect(preferences.navigationState == nil)
    }

    @Test func artworkColoursDefaultOn() {
        let (preferences, _) = makePreferences()
        #expect(preferences.useArtworkColors)
        preferences.useArtworkColors = false
        #expect(!preferences.useArtworkColors)
    }

    @Test func artworkColoursOffSurvivesANewInstance() {
        let (preferences, defaults) = makePreferences()
        preferences.useArtworkColors = false
        #expect(!Preferences(defaults: defaults).useArtworkColors)
        preferences.useArtworkColors = true
        #expect(Preferences(defaults: defaults).useArtworkColors)
    }

    @Test func navigationStateAtTheCapIsAccepted() {
        let (preferences, _) = makePreferences()
        let atCap = Data(count: Preferences.maxNavigationStateBytes)
        preferences.navigationState = atCap
        #expect(preferences.navigationState == atCap)
    }

    @Test func chartCountryAcceptsOnlyUppercaseLetters() {
        let (preferences, _) = makePreferences()
        #expect(preferences.chartCountry == nil)
        preferences.chartCountry = "de"
        #expect(preferences.chartCountry == nil)
        preferences.chartCountry = "DE"
        #expect(preferences.chartCountry == "DE")
        preferences.chartCountry = "D3"
        #expect(preferences.chartCountry == "DE")
        preferences.chartCountry = nil
        #expect(preferences.chartCountry == nil)
    }

    @Test func roundTrips() {
        let (preferences, _) = makePreferences()
        preferences.sidebarCollapsed = true
        preferences.volume = 0.4
        preferences.repeatMode = "one"
        preferences.shuffle = true
        #expect(preferences.sidebarCollapsed)
        #expect(preferences.volume == 0.4)
        #expect(preferences.repeatMode == "one")
        #expect(preferences.shuffle)
    }

    @Test func clampsVolume() {
        let (preferences, _) = makePreferences()
        preferences.volume = 3
        #expect(preferences.volume == 1)
        preferences.volume = -1
        #expect(preferences.volume == 0)
    }

    @Test func ignoresUnknownRepeatMode() {
        let (preferences, _) = makePreferences()
        preferences.repeatMode = "all"
        preferences.repeatMode = "bogus"
        #expect(preferences.repeatMode == "all")
    }

    @Test func languageMirrorsAppleLanguages() {
        let (preferences, defaults) = makePreferences()
        preferences.appLanguage = "uk"
        #expect(preferences.appLanguage == "uk")
        #expect(defaults.persistentDomain(forName: suite)?["AppleLanguages"] as? [String] == ["uk"])
        preferences.appLanguage = nil
        #expect(preferences.appLanguage == nil)
        #expect(defaults.persistentDomain(forName: suite)?["AppleLanguages"] == nil)
    }

    @Test func librarySectionAcceptsOnlyMusicBrowseIds() {
        let (preferences, _) = makePreferences()
        #expect(preferences.librarySection == nil)
        preferences.librarySection = "VLLM"
        #expect(preferences.librarySection == nil)
        preferences.librarySection = "FEmusic_liked_albums"
        #expect(preferences.librarySection == "FEmusic_liked_albums")
        preferences.librarySection = nil
        #expect(preferences.librarySection == nil)
    }

    @Test func librarySortIsStoredPerSection() {
        let (preferences, _) = makePreferences()
        preferences.setLibrarySort("A to Z", for: "FEmusic_liked_albums")
        preferences.setLibrarySort("local.za", for: "FEmusic_liked_videos")
        #expect(preferences.librarySort(for: "FEmusic_liked_albums") == "A to Z")
        #expect(preferences.librarySort(for: "FEmusic_liked_videos") == "local.za")
        #expect(preferences.librarySort(for: "FEmusic_liked_playlists") == nil)
        preferences.setLibrarySort(nil, for: "FEmusic_liked_albums")
        #expect(preferences.librarySort(for: "FEmusic_liked_albums") == nil)
        preferences.setLibrarySort("x", for: "bogus")
        #expect(preferences.librarySort(for: "bogus") == nil)
    }

    @Test func settingsDefaults() {
        let (preferences, _) = makePreferences()
        #expect(preferences.resumeOnStart)
        #expect(preferences.lastPlayback == nil)
        #expect(preferences.startingPage == nil)
        #expect(!preferences.alwaysOnTop)
        #expect(preferences.showDislikeButton)
        #expect(!preferences.karaokeEnabled)
    }

    @Test func lastPlaybackRoundTripsThroughItsThreeKeys() {
        let (preferences, defaults) = makePreferences()
        preferences.lastPlayback = LastPlayback(videoId: "dQw4w9WgXcQ", playlistId: "RDAMVM_x-1", elapsed: 42.5)
        #expect(preferences.lastPlayback == LastPlayback(videoId: "dQw4w9WgXcQ", playlistId: "RDAMVM_x-1", elapsed: 42.5))
        #expect(defaults.string(forKey: "lastVideoId") == "dQw4w9WgXcQ")
        #expect(defaults.string(forKey: "lastPlaylistId") == "RDAMVM_x-1")
        #expect(defaults.double(forKey: "lastElapsed") == 42.5)
        preferences.lastPlayback = LastPlayback(videoId: "abc", playlistId: nil, elapsed: 1)
        #expect(defaults.object(forKey: "lastPlaylistId") == nil)
        preferences.lastPlayback = nil
        for key in ["lastVideoId", "lastPlaylistId", "lastElapsed"] { #expect(defaults.object(forKey: key) == nil) }
    }

    @Test func lastPlaybackRefusesInvalidIdsAndPositions() {
        let (preferences, defaults) = makePreferences()
        preferences.lastPlayback = LastPlayback(videoId: "a b", playlistId: nil, elapsed: 1)
        #expect(preferences.lastPlayback == nil)
        preferences.lastPlayback = LastPlayback(videoId: "abc", playlistId: "PL/../x", elapsed: -5)
        #expect(preferences.lastPlayback == LastPlayback(videoId: "abc", playlistId: nil, elapsed: 0))
        preferences.lastPlayback = LastPlayback(videoId: "abc", playlistId: nil, elapsed: .nan)
        #expect(preferences.lastPlayback?.elapsed == 0)
        defaults.set(String(repeating: "a", count: 65), forKey: "lastVideoId")
        #expect(preferences.lastPlayback == nil)
        defaults.set("abc", forKey: "lastVideoId")
        defaults.set("<script>", forKey: "lastPlaylistId")
        defaults.set(Double.infinity, forKey: "lastElapsed")
        #expect(preferences.lastPlayback == LastPlayback(videoId: "abc", playlistId: nil, elapsed: 0))
    }

    @Test func startingPageAcceptsOnlySections() {
        let (preferences, defaults) = makePreferences()
        for page in Preferences.startingPages {
            preferences.startingPage = page
            #expect(preferences.startingPage == page)
        }
        preferences.startingPage = "settings"
        #expect(preferences.startingPage == "library", "an unknown value is refused, not stored")
        defaults.set("settings", forKey: "startingPage")
        #expect(preferences.startingPage == nil)
        preferences.startingPage = nil
        #expect(defaults.object(forKey: "startingPage") == nil)
    }

    @Test func togglesRoundTrip() {
        let (preferences, _) = makePreferences()
        preferences.resumeOnStart = false
        preferences.alwaysOnTop = true
        preferences.showDislikeButton = false
        preferences.karaokeEnabled = true
        #expect(preferences.karaokeEnabled)
        #expect(!preferences.resumeOnStart)
        #expect(preferences.alwaysOnTop)
        #expect(!preferences.showDislikeButton)
    }

    @Test func menuBarAndNotificationDefaults() {
        let (preferences, _) = makePreferences()
        #expect(!preferences.showMenuBarExtra)
        #expect(!preferences.menuBarClickTogglesPlay)
        #expect(!preferences.hideDockIcon)
    }

    @Test func dockIconStaysVisibleWithoutTheMenuBarItem() {
        let (preferences, defaults) = makePreferences()
        defaults.set(true, forKey: "hideDockIcon")
        #expect(!preferences.hideDockIcon, "a hand-edited value cannot hide both")
        preferences.showMenuBarExtra = true
        preferences.hideDockIcon = true
        #expect(preferences.hideDockIcon)
        preferences.showMenuBarExtra = false
        #expect(!preferences.hideDockIcon)
        #expect(defaults.object(forKey: "hideDockIcon") == nil)
    }
}
