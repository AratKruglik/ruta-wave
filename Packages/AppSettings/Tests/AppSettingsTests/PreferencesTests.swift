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
}
