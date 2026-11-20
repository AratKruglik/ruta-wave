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
}
