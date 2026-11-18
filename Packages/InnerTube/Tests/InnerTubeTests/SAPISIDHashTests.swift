import Testing
@testable import InnerTube

@Suite struct SAPISIDHashTests {
    // printf '%s' '1700000000 test-sapisid-value https://music.youtube.com' | shasum -a 1
    @Test func matchesIndependentlyComputedVector() {
        let hash = SAPISIDHash.make(sapisid: "test-sapisid-value", timestamp: 1_700_000_000, origin: "https://music.youtube.com")
        #expect(hash == "1700000000_0c0d2e2ebe5f3603ce622ae1dceaa2917419aeb8")
    }

    @Test func hasExpectedFormat() {
        let hash = SAPISIDHash.make(sapisid: "x", timestamp: 42, origin: "https://music.youtube.com")
        #expect(hash.wholeMatch(of: /\d+_[0-9a-f]{40}/) != nil)
    }
}
