import Testing
@testable import PlayerEngine

struct CleanupNameTests {
    @Test(arguments: [
        ("Radiohead - Topic", "Radiohead"),
        ("Rihanna VEVO", "Rihanna"),
        ("RIHANNAVEVO", "RIHANNA"),
        ("Song (Official Video)", "Song"),
        ("Song [Official Video]", "Song"),
        ("Song (Lyrics)", "Song"),
        ("Song (Lyric Video)", "Song"),
        ("Song (Visualizer)", "Song"),
        ("Song (Audio)", "Song"),
        ("Song (Performance Video)", "Song"),
        ("Song (Clip Official)", "Song"),
        ("Song (Video Version)", "Song"),
        ("Song (HD)", "Song"),
        ("Song (HQ Audio)", "Song"),
        ("Song (Live)", "Song"),
        ("Song (4K Upgrade)", "Song"),
        ("Song (4K)", "Song"),
        ("Song (official lyrics) more", "Song more"),
        ("Plain Title", "Plain Title"),
        ("", ""),
    ])
    func cleans(input: String, expected: String) {
        #expect(SongInfo.cleanupName(input) == expected)
    }

    @Test func replacesFirstMatchOnly() {
        #expect(SongInfo.cleanupName("A (Official Video) B (Official Audio)") == "A B (Official Audio)")
    }

    @Test(arguments: ["Song (Live) remix", "Song (HD) remix", "Song (4K) remix"])
    func anchoredPatternsIgnoreMidString(input: String) {
        #expect(SongInfo.cleanupName(input) == input)
    }
}
