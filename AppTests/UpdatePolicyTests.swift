import Testing

struct UpdatePolicyTests {
    @Test(arguments: [
        (String?.none, "0.2.0", UpdateChannel.stable),
        (nil, "0.2.0-beta.1", .beta),
        ("stable", "0.2.0-beta.1", .stable),
        ("beta", "0.2.0", .beta),
        ("nightly", "0.2.0", .stable),
    ])
    func channel(stored: String?, runningVersion: String, expected: UpdateChannel) {
        #expect(UpdateChannel(stored: stored, runningVersion: runningVersion) == expected)
    }

    @Test func onlyBetaAllowsTheBetaChannel() {
        #expect(UpdateChannel.stable.sparkleChannels.isEmpty)
        #expect(UpdateChannel.beta.sparkleChannels == ["beta"])
    }

    @Test(arguments: [
        (true, true, true), (true, false, true),
        (false, true, false), (false, false, true),
    ])
    func sparkleShowsScheduledUpdate(immediateFocus: Bool, notificationsEnabled: Bool, expected: Bool) {
        #expect(UpdateReminder.sparkleShowsScheduledUpdate(
            immediateFocus: immediateFocus, notificationsEnabled: notificationsEnabled) == expected)
    }
}
