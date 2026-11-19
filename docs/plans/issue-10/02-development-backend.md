# Development report: InnerTube parsers for album, artist, playlist, library, history and up next (issue #10, backlog 2.3)

Aspect: `backend` (`Packages/InnerTube` plus the docs rows named in the plan). Nothing committed. No `App/` change.

## Result

- `swift test` in `Packages/InnerTube`: **220 tests in 28 suites pass** (baseline 153 / 20, plus 67 new tests in 8 new suites).
- `INNERTUBE_LIVE=1 swift test --filter livePlaylistPagesPastOneHundredTracks`: passes (100 tracks, then page 2 with no overlap).
- `python3 -I Scripts/test_scrub_fixture.py`: 4 tests pass.
- `xcodebuild -project Redwave.xcodeproj -scheme Redwave -destination 'platform=macOS' -quiet build`: clean.
- `swift build`: no warnings.

## Project shape

XcodeGen app, local SPM package `InnerTube` (macOS 14, tools 6.0, Swift 6 mode). No project, setting, entitlement or dependency change. Swift Testing. No UI.

## Files created (Packages/InnerTube)

Sources: `EntityPages.swift` (models), `PageHeaderParser.swift`, `AlbumParser.swift`, `ArtistParser.swift`, `PlaylistParser.swift`, `LibraryParser.swift` (library, continuation, guide), `HistoryParser.swift`, `WatchNextParser.swift`, `LyricsParser.swift`.

Tests: `AlbumParserTests`, `ArtistParserTests`, `PlaylistParserTests`, `LibraryParserTests`, `HistoryParserTests`, `WatchNextParserTests`, `LyricsParserTests`, `EntityClientTests` (incl. the env-gated live test).

`Scripts/test_scrub_fixture.py`. 30 fixtures (18 real guest captures, 12 synthetic): album, artist, artist-albums, playlist, playlist-continuation, playlist-top-songs, playlist-missing, liked-music-guest, library-guest, guide-guest, history-guest, next-radio, next-album, next-no-lyrics, next-continuation, lyrics, lyrics-none, related (real); playlist-own, playlist-suggestions, liked-music, library-playlists / songs / albums / artists / subscriptions / continuation, guide, history, next-counterpart (synthetic).

## Files modified

- `Sources/InnerTube/InnerTubeClient.swift`: `InnerTubeError.notAvailable`; `album`, `artist`, `playlist`, `playlistContinuation`, `library`, `libraryContinuation`, `sidebarPlaylists`, `history`, `watchNext`, `watchNextContinuation`, `lyrics`; private `fetchBrowse`; `browse` doc comment (routing) and the K5 note on `playlistContinuation`.
- `Sources/InnerTube/ItemParser.swift`: queue chip `watchTarget`; `musicShelfRenderer` More candidates (`bottomEndpoint`, title run); duration also from `fixedColumns`; new `watchTarget`, `queueItem`, `song`; `refs`, `isExplicit`, `pageType` made internal (were private).
- `Sources/InnerTube/Shelf.swift` (`Chip.watchTarget`, defaulted), `MusicItem.swift` (`BrowseTarget` statics), `BrowseParser.swift` (`contents.sectionListRenderer` fallback), `Page.swift` (`nextRadioContinuationData`).
- `Scripts/scrub-fixture.py`: removal-menu allowance, email before handle, trailing continuation / automix survive `--items`, `continuationItems` trimmed.
- `Tests/InnerTubeTests/Fixtures/README.md`, `docs/01-reverse-engineering.md` section 4.9, `docs/00-prd.md` section 5 (F-LIB-2, F-LIB-4, F-PLY-4, F-PLY-5 gain `2.3`).

## Key design decisions

1. One parser file per response shape, as in 2.2. Related and artist Show-all need no parser: `JSONValue.sectionList` got one fallback.
2. `.notAvailable` is decided only on first-page album, artist and playlist parsing (`json["contents"] == nil`). A playlist continuation without the append action is `.unexpectedResponse`. A 404 stays `.httpStatus`.
3. `WatchTarget` is the only new endpoint type. The sidebar is `[Playlist]` (Liked music = `VLLM`); sort options and library sections are `[Chip]`.
4. Routing contract: every `VL…` target goes to `playlist(_:)` (including Top songs / Videos Show-all, which are single-column playlists), `MPREb_…` to `album`, `UC…` without params to `artist`, the rest to `browse`.
5. Lyrics: `LyricsParser.parse(_:) throws(InnerTubeError) -> Lyrics?` (a static function, not a failable init, because "not available" is `nil` while a bad root throws).

## Deviations from the plan

- `Lyrics?(lyrics:)` became the static `LyricsParser.parse(_:)` (a failable init cannot separate `nil` from a throw).
- `ItemParser.refs`, `isExplicit` and `pageType` changed from `private` to internal so the header, watch-next and library parsers reuse them. `destination` stays private.
- Synthetic shapes were checked against the ytmusicapi and YouTube.js sources saved in the planning scratchpad (Context7 not used). Confirmed: sort path (`itemSectionTabbedHeaderRenderer.endItems[].dropdownRenderer.entries[].dropdownItemRenderer.onSelectCommand.browseEndpoint.params`), history token (`menuServiceItemRenderer`, icon `REMOVE_FROM_HISTORY`, `serviceEndpoint.feedbackEndpoint.feedbackToken`), counterpart path, `musicEditablePlaylistDetailHeaderRenderer.header.musicResponsiveHeaderRenderer`. **Still unverified:** the library chip location (`sectionListRenderer.header.chipCloudRenderer`), the `dropdownItemRenderer.label` key (the parser accepts runs, simpleText or a plain string) and the real nesting of guide playlists (the parser walks any nesting, keys sorted, including `headerEntry` / `sectionItems`).
- `related.json`: the "Recommended playlists" and "Other performances" cards were removed, because they held private individuals (user playlists and uploader channels, for example names and channel ids). The fixture keeps 3 shelves plus About. The plan expected "Recommended playlists" to stay.
- `lyrics-none.json` is the real Treefingers capture (`MPLYt_ob5cslgCNc0-5`), as planned.
- No temporary screen (D4); paging is tested through the transport seam plus the live test.

## Verification notes

- The 2.2 suite stayed green after the shared `ItemParser`, `sectionList` and `nextContinuation` edits.
- `FixturePrivacyTests` passes on all 46 fixtures (every one has a README row). Real captures hold only YouTube Music-owned or artist-owned playlists. Lyric text is replaced.
- Fixture token numbering follows scrubber traversal order: in `playlist.json` the track token is `PLACEHOLDER_CONTINUATION_1` and the section-list token is `_2`.

## Blockers and open items for the next phases (API mismatches M1 to M10 of the plan all stand)

- M1 no album footer (no release date or label); M2 not available = 200 without `contents`; M3 guest `isSubscribed == false`; M4 `ArtistPage.channelId` differs from the page id (2.4 must use it); M5 "Playing from" has no endpoint (`WatchNext.playlistId` instead); M6 guide entries have no owner (`Playlist.subtitle == nil`); M7 counterpart never seen as a guest; M8 disabled lyrics tab keeps the endpoint (`lyricsBrowseId == nil`); M9 Top songs and Videos Show-all are playlists; M10 Suggestions come via `sectionsContinuation` + `browseContinuation`.
- R1 12 of 30 fixtures are synthetic; library chips location, sort `label` key and the guide playlist section are the least certain. R2 the liked-songs "Shuffle all" row is not special-cased and would parse as a leading `.playlist` item. R3 private playlists of another user were not captured.
- The playlist owner for a user playlist is a `PageHeader.artists` entry with a channel `browseId`; for YouTube Music it has `browseId == nil`.
