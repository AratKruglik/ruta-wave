import Foundation
import Testing
@testable import InnerTube

private let credentials = Credentials(
    cookies: [HTTPCookie(properties: [.name: "SAPISID", .value: "test-sapisid", .domain: ".youtube.com", .path: "/"])!],
    authUserIndex: 1)

private func body(_ request: URLRequest) throws -> JSONValue {
    try JSONDecoder().decode(JSONValue.self, from: #require(request.httpBody))
}

private func ok(_ json: String = "{}") -> Step { .status(200, json) }

@Suite struct MutationClientTests {
    @Test(arguments: [(Rating.like, "like"), (.dislike, "dislike"), (.indifferent, "removelike")])
    func rateVideoSendsTheEndpointAndTarget(rating: Rating, path: String) async throws {
        let script = Script([ok()])
        try await script.client().rate(videoId: "v1", rating, credentials: credentials)
        let request = script.requests[0]
        #expect(request.url?.path == "/youtubei/v1/like/\(path)")
        #expect(try body(request)["target"]?["videoId"]?.string == "v1")
        #expect(request.value(forHTTPHeaderField: "Authorization")?.hasPrefix("SAPISIDHASH") == true)
    }

    @Test func nonJSONSuccessBodyStillSucceeds() async throws {
        let script = Script([ok("")])
        try await script.client().rate(videoId: "v1", .like, credentials: credentials)
    }

    @Test func ratePlaylistStripsVL() async throws {
        let script = Script([ok()])
        try await script.client().rate(playlistId: "VLPLabc", .like, credentials: credentials)
        #expect(try body(script.requests[0])["target"]?["playlistId"]?.string == "PLabc")
    }

    @Test(arguments: ["", "VL", "LM", "VLLM"])
    func ratePlaylistRejectsEmptyAndLikedMusic(id: String) async {
        let script = Script([ok()])
        await #expect(throws: InnerTubeError.invalidArgument) { try await script.client().rate(playlistId: id, .like, credentials: credentials) }
        #expect(script.requests.isEmpty)
    }

    @Test func createSendsTrimmedTitleAndPrivateByDefault() async throws {
        let script = Script([try .fixture("playlist-create")])
        let id = try await script.client().createPlaylist(title: "  Mix \n", credentials: credentials)
        let sent = try body(script.requests[0])
        #expect(script.requests[0].url?.path == "/youtubei/v1/playlist/create")
        #expect(id == "PLplaceholder00000000000000000000")
        #expect(sent["title"]?.string == "Mix")
        #expect(sent["privacyStatus"]?.string == "PRIVATE")
        #expect(sent["description"]?.string == "")
        #expect(sent["videoIds"] == nil)
    }

    @Test func createSendsVideoIdsAndPrivacy() async throws {
        let script = Script([try .fixture("playlist-create")])
        _ = try await script.client().createPlaylist(
            title: "Mix", description: "d", privacy: .unlisted, videoIds: ["a", "b"], credentials: credentials)
        let sent = try body(script.requests[0])
        #expect(sent["videoIds"]?.array?.compactMap(\.string) == ["a", "b"])
        #expect(sent["privacyStatus"]?.string == "UNLISTED")
    }

    @Test func createTitleLimitsCountCharacters() async throws {
        let script = Script([try .fixture("playlist-create")])
        let client = script.client()
        _ = try await client.createPlaylist(title: String(repeating: "🎵", count: 150), credentials: credentials)
        await #expect(throws: InnerTubeError.invalidArgument) {
            try await client.createPlaylist(title: String(repeating: "🎵", count: 151), credentials: credentials)
        }
        await #expect(throws: InnerTubeError.invalidArgument) { try await client.createPlaylist(title: " \n ", credentials: credentials) }
        await #expect(throws: InnerTubeError.invalidArgument) {
            try await client.createPlaylist(title: "x", videoIds: [""], credentials: credentials)
        }
        #expect(script.requests.count == 1)
    }

    @Test func createWithoutPlaylistIdIsUnexpected() async {
        let script = Script([ok("{}")])
        await #expect(throws: InnerTubeError.unexpectedResponse) { try await script.client().createPlaylist(title: "x", credentials: credentials) }
    }

    @Test func deleteStripsVL() async throws {
        let script = Script([ok()])
        try await script.client().deletePlaylist("VLPLabc", credentials: credentials)
        #expect(script.requests[0].url?.path == "/youtubei/v1/playlist/delete")
        #expect(try body(script.requests[0])["playlistId"]?.string == "PLabc")
    }

    @Test func deleteRejectsLikedMusic() async {
        let script = Script([ok()])
        await #expect(throws: InnerTubeError.invalidArgument) { try await script.client().deletePlaylist("LM", credentials: credentials) }
        #expect(script.requests.isEmpty)
    }

    @Test func editSendsEveryActionInOneRequestInOrder() async throws {
        let script = Script([try .fixture("edit-playlist")])
        let rows = try await script.client().editPlaylist(
            "VLPLabc",
            [
                .add(videoId: "v1"), .remove(videoId: "v2", setVideoId: "s2"), .move(setVideoId: "s3", before: "s4"),
                .move(setVideoId: "s5", before: nil), .rename(" New "), .setDescription("d"), .setPrivacy(.public),
            ],
            credentials: credentials)
        #expect(script.requests.count == 1)
        #expect(script.requests[0].url?.path == "/youtubei/v1/browse/edit_playlist")
        let sent = try body(script.requests[0])
        #expect(sent["playlistId"]?.string == "PLabc")
        let actions = try #require(sent["actions"]?.array)
        #expect(actions.count == 7)
        #expect(actions[0].object?.mapValues(\.string) == ["action": "ACTION_ADD_VIDEO", "addedVideoId": "v1", "dedupeOption": "DEDUPE_OPTION_SKIP"])
        #expect(actions[1].object?.mapValues(\.string) == ["action": "ACTION_REMOVE_VIDEO", "setVideoId": "s2", "removedVideoId": "v2"])
        #expect(actions[2].object?.mapValues(\.string) == ["action": "ACTION_MOVE_VIDEO_BEFORE", "setVideoId": "s3", "movedSetVideoIdSuccessor": "s4"])
        #expect(actions[3].object?.mapValues(\.string) == ["action": "ACTION_MOVE_VIDEO_BEFORE", "setVideoId": "s5"])
        #expect(actions[4].object?.mapValues(\.string) == ["action": "ACTION_SET_PLAYLIST_NAME", "playlistName": "New"])
        #expect(actions[5].object?.mapValues(\.string) == ["action": "ACTION_SET_PLAYLIST_DESCRIPTION", "playlistDescription": "d"])
        #expect(actions[6].object?.mapValues(\.string) == ["action": "ACTION_SET_PLAYLIST_PRIVACY", "playlistPrivacy": "PUBLIC"])
        #expect(rows == [
            AddedPlaylistRow(videoId: "PLACEHOLDER_V1", setVideoId: "PLACEHOLDER_SET_1"),
            AddedPlaylistRow(videoId: "PLACEHOLDER_V2", setVideoId: "PLACEHOLDER_SET_2"),
        ])
    }

    @Test func editWithoutResultsReturnsNoRows() async throws {
        let script = Script([ok(#"{"status":"STATUS_SUCCEEDED"}"#)])
        let rows = try await script.client().editPlaylist("PLabc", [.rename("x")], credentials: credentials)
        #expect(rows.isEmpty)
    }

    @Test func failedEditStatusIsUnexpected() async {
        let script = Script([ok(#"{"status":"STATUS_FAILED"}"#)])
        await #expect(throws: InnerTubeError.unexpectedResponse) {
            try await script.client().editPlaylist("PLabc", [.rename("x")], credentials: credentials)
        }
    }

    @Test(arguments: [
        [], [PlaylistEdit.rename("  ")], [.rename(String(repeating: "a", count: 151))], [.add(videoId: "")],
        [.remove(videoId: "v", setVideoId: "")], [.remove(videoId: "", setVideoId: "s")], [.move(setVideoId: "", before: nil)],
        [.move(setVideoId: "s", before: "")],
    ])
    func invalidEditsSendNothing(edits: [PlaylistEdit]) async {
        let script = Script([ok(#"{"status":"STATUS_SUCCEEDED"}"#)])
        await #expect(throws: InnerTubeError.invalidArgument) { try await script.client().editPlaylist("PLabc", edits, credentials: credentials) }
        #expect(script.requests.isEmpty)
    }

    @Test(arguments: [(true, "subscribe"), (false, "unsubscribe")])
    func subscribeUsesChannelIdsArray(subscribed: Bool, path: String) async throws {
        let script = Script([ok()])
        try await script.client().setSubscribed(subscribed, channelId: "UCx", credentials: credentials)
        #expect(script.requests[0].url?.path == "/youtubei/v1/subscription/\(path)")
        #expect(try body(script.requests[0])["channelIds"]?.array?.compactMap(\.string) == ["UCx"])
    }

    @Test func feedbackSendsTokens() async throws {
        let script = Script([try .fixture("feedback")])
        try await script.client().sendFeedback(["PLACEHOLDER_FEEDBACK_1", "PLACEHOLDER_FEEDBACK_2"], credentials: credentials)
        #expect(script.requests[0].url?.path == "/youtubei/v1/feedback")
        #expect(try body(script.requests[0])["feedbackTokens"]?.array?.compactMap(\.string) == ["PLACEHOLDER_FEEDBACK_1", "PLACEHOLDER_FEEDBACK_2"])
    }

    @Test(arguments: [#"{"feedbackResponses":[{"isProcessed":false}]}"#, #"{"feedbackResponses":[]}"#, "{}"])
    func unprocessedFeedbackIsUnexpected(json: String) async {
        let script = Script([ok(json)])
        await #expect(throws: InnerTubeError.unexpectedResponse) { try await script.client().sendFeedback(["t"], credentials: credentials) }
    }

    @Test(arguments: [[], [""], ["t", ""]])
    func invalidFeedbackSendsNothing(tokens: [String]) async {
        let script = Script([ok()])
        await #expect(throws: InnerTubeError.invalidArgument) { try await script.client().sendFeedback(tokens, credentials: credentials) }
        #expect(script.requests.isEmpty)
    }

    @Test func emptyIdsAreInvalid() async {
        let script = Script([ok()])
        let client = script.client()
        await #expect(throws: InnerTubeError.invalidArgument) { try await client.rate(videoId: "", .like, credentials: credentials) }
        await #expect(throws: InnerTubeError.invalidArgument) { try await client.setSubscribed(true, channelId: "", credentials: credentials) }
        #expect(script.requests.isEmpty)
    }

    @Test func unauthorizedAndMissingSAPISID() async {
        let script = Script([.status(401, "{}")])
        await #expect(throws: InnerTubeError.unauthorized) { try await script.client().rate(videoId: "v", .like, credentials: credentials) }
        let noCookie = Credentials(cookies: [], authUserIndex: 0)
        let silent = Script([ok()])
        await #expect(throws: InnerTubeError.missingSAPISID) { try await silent.client().rate(videoId: "v", .like, credentials: noCookie) }
        #expect(silent.requests.isEmpty)
    }

    private func everyMutation(_ client: InnerTubeClient, _ credentials: Credentials?) -> [() async throws -> Void] {
        [
            { try await client.rate(videoId: "v", .like, credentials: credentials) },
            { try await client.rate(playlistId: "PLa", .like, credentials: credentials) },
            { _ = try await client.createPlaylist(title: "t", credentials: credentials) },
            { try await client.deletePlaylist("PLa", credentials: credentials) },
            { try await client.editPlaylist("PLa", [.rename("t")], credentials: credentials) },
            { try await client.setSubscribed(true, channelId: "UCx", credentials: credentials) },
            { try await client.sendFeedback(["t"], credentials: credentials) },
        ]
    }

    @Test func aGuestNeverSendsARequest() async {
        let script = Script([ok()])
        for call in everyMutation(script.client(), nil) {
            await #expect(throws: InnerTubeError.signInRequired) { try await call() }
        }
        #expect(script.requests.isEmpty)
    }

    @Test(arguments: [Step.status(503, "{}"), .fail(.timedOut)])
    func mutationsAreNeverRetried(failure: Step) async {
        for index in 0..<7 {
            let script = Script([failure, ok(#"{"status":"STATUS_SUCCEEDED","playlistId":"PLa"}"#)])
            let call = everyMutation(script.client(), credentials)[index]
            await #expect(throws: InnerTubeError.self) { try await call() }
            #expect(script.requests.count == 1)
        }
    }
}
