# Development plan: InnerTube parsers for album, artist, playlist, library, history and up next (backlog 2.3, issue #10)

Pass: PLAN. Aspect: `backend` (the `Packages/InnerTube` package only). No source code has been changed.

Sources:
- `_brief.md` (issue #10) and `01-business-analysis.md`, including its "Decisions from the user":
  - Q1: synthetic fixtures for signed-in-only shapes; no 2.3a/2.3b split;
  - Q2: parse the Up next queue, and the bridge stays the source of truth;
  - Q3: private and deleted playlists are one "not available" case.
- `docs/plans/issue-9/02-development-plan.md` and `02-development.md`: the 2.2 patterns this plan extends.
- The current code in `Packages/InnerTube`.
- **Live guest probes made during planning** (2026-11-19, `WEB_REMIX` `1.20261115.14.00`, `hl=en`, `gl=US`, the visitor header reused as in 2.2). The raw captures stay in the session scratchpad and were **not** committed.
- The public `ytmusicapi` sources (`parsers/library.py`, `mixins/library.py`, `parsers/songs.py`, `parsers/watch.py`, `mixins/playlists.py`) and YouTube.js (`GuideEntry`, `GuideSection`), for the shapes a guest cannot see.

Baseline: `swift test` in `Packages/InnerTube` passes **153 tests in 20 suites**.

## 0. Issue, spec and decisions

| # | Point | Plan follows |
|---|---|---|
| D1 | Fixtures | Real scrubbed **guest** captures for album, artist, artist Show-all, playlist (both layouts) and its continuation, missing playlist, `next` (radio, album queue, no lyrics, continuation), lyrics, no lyrics, and related. The **guest** library, history and `guide` responses are also real: they pin the guest outcome. **Synthetic** files cover the signed-in shapes: the five library sections, library continuation, `VLLM`, own playlist plus Suggestions, signed-in `guide`, history, and the `next` counterpart (user decision Q1). |
| D2 | Up next queue | Parsed (items, current marker, chips, source, tab ids, counterpart, automix, continuation). The doc comment says the bridge (3.2) owns the live queue (user decision Q2). |
| D3 | Not available | One typed case, `InnerTubeError.notAvailable`, for private, deleted and non-existent alike (user decision Q3). |
| D4 | "Done when: fetch a playlist longer than one page" | Deterministic transport-seam tests, plus one `INNERTUBE_LIVE=1` test that pages a 118-track public playlist. No temporary screen and no `App/` change. |
| D5 | Podcasts | Out of scope. Podcast items are already skipped and logged by `ItemParser.destination` (2.2). No new code. |
| D6 | Branch `feature/innertube-entities` in the issue | The pipeline branch is `feature/issue-10`. Noted for the PR body. |

## 1. Project shape

| Aspect | Value |
|---|---|
| Project system | XcodeGen (`project.yml`). The change is confined to the local SPM package `Packages/InnerTube`, so no project regeneration is needed. |
| Target / platform | Package `InnerTube`, `platforms: [.macOS(.v14)]`, tools 6.0 (Swift 6 mode, strict concurrency). It depends on `Auth`. No target changes. |
| Swift settings | Package defaults. Nothing is changed. |
| UI / state / persistence / navigation | Not touched (data layer only). |
| Networking | The `InnerTubeClient` actor, with private `fetch(_:body:credentials:)` sending to `post` (signed) or `postGuest` (visitor-tracked). Reused as is. |
| Parsing | `JSONValue`, `parseBlocks` (skip and log the renderer key), `Page<T>`, `nextContinuation`, `text()`, `lastThumbnailURL()`, `ItemParser`. All reused. |
| Tests | Swift Testing. `Script` / `Step` transport stub in `Tests/InnerTubeTests/Support/ScriptedTransport.swift`. `Fixture` loader. `FixturePrivacyTests` runs on every fixture and requires a README row for each. |
| Localization / design system | n/a. No user-facing strings: display text is passed through from the server. |
| Dependencies | None added. |

## 2. What the live probes established

These findings override the BA's **[known, unverified]** shapes. Every difference from the BA is listed in §9.

1. **Album** `browse MPREb_…`:
   - Layout: `contents.twoColumnBrowseResultsRenderer`.
   - **Header**: `tabs[0].tabRenderer.content.sectionListRenderer.contents[0].musicResponsiveHeaderRenderer`:
     - `title`;
     - `subtitle.runs` = type ("Album") • year ("1997");
     - `straplineTextOne.runs` = artist link(s) with `browseEndpoint` page type ARTIST;
     - `secondSubtitle.runs` = "12 songs • 53 minutes";
     - `description.musicDescriptionShelfRenderer.description`;
     - `thumbnail.musicThumbnailRenderer.thumbnail`;
     - `buttons[]`:
       - `musicPlayButtonRenderer.playNavigationEndpoint.watchPlaylistEndpoint.playlistId` = `OLAK5uy_…` (the audio playlist);
       - a `menuRenderer.items[].menuNavigationItemRenderer` with icon `MUSIC_SHUFFLE` (Shuffle) and icon `MIX` (Start mix), each holding a `watchPlaylistEndpoint{playlistId, params}`.
   - **Tracks**: `secondaryContents.sectionListRenderer.contents[0].musicShelfRenderer.contents[]` of `musicResponsiveListItemRenderer`:
     - the track number is `index.runs[0].text`;
     - the duration is **only** in `fixedColumns[0].musicResponsiveListItemFixedColumnRenderer.text`;
     - `flexColumns[1]` (artists) is **empty**;
     - identity comes from `flexColumns[0]…watchEndpoint` (`ATV`).
   - **Shelves**: the rest of `secondaryContents.sectionListRenderer.contents[]` are `musicCarouselShelfRenderer`s ("Other versions", "Releases for you"). They have no More button.
   - **No footer.** There is no release date, label or `℗` / `©` text anywhere in the response (counted: 0). The count and duration are only in `secondSubtitle`.
2. **Artist** `browse UC…`:
   - Layout: `singleColumnBrowseResultsRenderer` section list, plus `header.musicImmersiveHeaderRenderer`:
     - `title`;
     - `thumbnail`;
     - `description`;
     - `subscriptionButton.subscribeButtonRenderer{subscribed, channelId, longSubscriberCountText}`;
     - `playButton.buttonRenderer.navigationEndpoint.watchEndpoint` (Shuffle);
     - `startRadioButton.buttonRenderer.navigationEndpoint.watchEndpoint` (Mix);
     - `monthlyListenerCount`.
   - **The subscribe `channelId` (`UCq19-…`) differs from the page `browseId` (`UCr_iy…`).** 2.4 must use the former.
   - **A guest gets `subscribed: false`**, not an absent field.
   - Sections, in this order:
     - `musicShelfRenderer` "Top songs": 5 rows, with `bottomEndpoint.browseEndpoint` = `VLOLAK5uy_…` + `params`; the title run carries the same endpoint;
     - `musicCarouselShelfRenderer`s: Albums, Singles & EPs (More = `MPADUC…` + params, page type `ARTIST_DISCOGRAPHY`); Videos (More = `VLOLAK…` + params); Live performances and Playlists by … (More = `UC…` + params); Featured on and Fans might also like (no More);
     - `musicDescriptionShelfRenderer` About: `header` "About", `subheader` "5,409,889,352 views", `description`.
3. **Artist "Show all"**:
   - `MPADUC…` + params is a single-column section list with one `gridRenderer` of `musicTwoRowItemRenderer` and a `header.musicHeaderRenderer`.
   - `UC…` + params is a single-column section list with one `musicShelfRenderer`.
   - **Both already parse with the existing `browse(_:)` / `BrowsePage`.**
   - **`VLOLAK…` + params** (Top songs, Videos) is a **playlist** in the *single-column* layout:
     - `header.musicHeaderRenderer{title}`;
     - `singleColumnBrowseResultsRenderer.tabs[0]…sectionListRenderer.contents[0].musicPlaylistShelfRenderer` with 100 rows and a trailing `continuationItemRenderer`.
     - `BrowsePage` would drop this shelf, so it must go to the playlist parser.
4. **Playlist** `browse VL…`:
   - Layout: two-column, with the same `musicResponsiveHeaderRenderer` as the album:
     - `subtitle` "Playlist • 2025";
     - `secondSubtitle` "568 views • 11 tracks" or "50 songs • 3 hours, 8 minutes";
     - owner in `facepile.avatarStackViewModel{text.content, rendererContext.commandContext.onTap.innertubeCommand.browseEndpoint}`. That is a `USER_CHANNEL` link for user playlists and no link for "YouTube Music";
     - an own playlist wraps the header in `musicEditablePlaylistDetailHeaderRenderer.header` (ytmusicapi; synthetic).
   - Tracks: `secondaryContents.sectionListRenderer.contents[0].musicPlaylistShelfRenderer{playlistId, contents[]}`:
     - rows have `flexColumns` = title / artist / album, the duration in `fixedColumns`, and `playlistItemData.videoId`;
     - for a long list, **the last entry is a `continuationItemRenderer`** (100 tracks + token).
   - **Page 2** (body `{"continuation": token}`) is `onResponseReceivedActions[0].appendContinuationItemsAction.continuationItems[]`. On the last page (17 tracks of 118) it has no trailing continuation.
   - **A second, separate token** is `secondaryContents.sectionListRenderer.continuations[0].nextContinuationData`. Its response is `continuationContents.sectionListContinuation` holding the "Related playlists" carousel (guest). Per ytmusicapi, an own playlist's "Suggestions" `musicShelfRenderer` arrives the same way. **The existing `browseContinuation` already parses it.**
   - **Visitor rule (K5), sharper than in 2.2**: a playlist continuation sent **without** the issuing visitor does not fail. It silently returns page 1 again (99 of 100 ids repeated). With the visitor, page 2 had 0 overlap.
5. **Not available**:
   - `browse` with a non-existent `VL…`, `VLOLAK…`, `VLRDCLAK…`, `MPREb_…` or `UC…` id returns **HTTP 200 with no `contents` key** (only `trackingParams` and `microformat.noindex`). There are no `alerts`, and no 4xx.
   - A private playlist of another user could not be captured (no second account). It is assumed to behave the same; see risk R3.
6. **Guest library, `VLLM`, history**:
   - HTTP 200, single-column section list whose only content is `itemSectionRenderer.contents[0].messageRenderer` ("Looking for what you've liked?", "Sign in to view your history"). There is no shelf, no grid and no `header`.
7. **Guest `guide`** `{}`: `items[0].guideSectionRenderer.items[]` with Home / Explore / Library `guideEntryRenderer`s (`formattedTitle`, `navigationEndpoint.browseEndpoint.browseId`), and `items[1].guideSigninPromoRenderer`. There are no `VL…` entries.
8. **`next`** `{videoId, playlistId?, params?}`:
   - Root `contents.singleColumnMusicWatchNextResultsRenderer.tabbedRenderer.watchNextTabbedResultsRenderer.tabs[]` has **4 tabs**: Up next, Lyrics, **Comments**, Related.
   - The Lyrics and Related tabs carry `endpoint.browseEndpoint{browseId: MPLY… / MPTR…}` with page type `MUSIC_PAGE_TYPE_TRACK_LYRICS` / `MUSIC_PAGE_TYPE_TRACK_RELATED`.
   - **A track without lyrics keeps the Lyrics endpoint and adds `unselectable: true`.** Fetching that id returns the no-lyrics message.
   - Tab 0 `musicQueueRenderer`:
     - `header.musicQueueHeaderRenderer{title "Playing from", subtitle "Airbag Mix" / "OK Computer"}`. The subtitle has **no endpoint**;
     - `subHeaderChipCloud.chipCloudRenderer.chips[].chipCloudChipRenderer{text, isSelected, navigationEndpoint.queueUpdateCommand.fetchContentsCommand.watchEndpoint{playlistId, params}}` (radio only: All / Popular / …);
     - `content.playlistPanelRenderer{playlistId, contents[], continuations[0].nextRadioContinuationData.continuation}`.
   - Items are `playlistPanelVideoRenderer`:
     - `title`, `longBylineText.runs` (artist / album links), `lengthText`, `thumbnail`, `selected`, `videoId`;
     - `navigationEndpoint.watchEndpoint{videoId, playlistId, musicVideoType}`.
   - An album or bare-video queue ends with `automixPreviewVideoRenderer.content.automixPlaylistVideoRenderer.navigationEndpoint.watchPlaylistEndpoint{playlistId RDAMPL…, params}`.
   - **No `playlistPanelVideoWrapperRenderer` (counterpart) was returned to a guest** for 4 ATV ids and 1 OMV id, with or without `isAudioOnly`. The shape follows ytmusicapi `parse_watch_playlist` (`counterpart[0].counterpartRenderer.playlistPanelVideoRenderer`, `primaryRenderer.playlistPanelVideoRenderer`; `unplayableText` rows are skipped). The fixture is synthetic.
   - **Queue continuation**: body `{"continuation": token}` alone works. The response has `continuationContents.playlistPanelContinuation{contents, continuations[0].nextRadioContinuationData}` (and also a fresh `contents`, which is ignored).
9. **Lyrics** `browse MPLY…`:
   - Root `contents.sectionListRenderer.contents[0].musicDescriptionShelfRenderer{description.runs, footer.runs "Source: LyricFind"}`.
   - The text uses `\r\n` line breaks.
   - No lyrics: `contents.messageRenderer` ("Lyrics not available").
10. **Related** `browse MPTR…`:
    - Root `contents.sectionListRenderer` (no single-column wrapper).
    - Carousels: "You might also like" (rows), "Recommended playlists", "Other performances", "Similar artists", "<artist>". Then a `musicDescriptionShelfRenderer` "About the artist", which is skipped.
11. **Library (signed in, synthetic, after ytmusicapi)**:
    - Single-column section list.
    - The container is `itemSectionRenderer.contents[0]` → `gridRenderer{items}` (playlists, albums) or `musicShelfRenderer{contents}` (songs, artists, subscriptions). Both may also sit directly in the section list.
    - Paging: `continuations[0].nextContinuationData`. Page 2 is under `continuationContents.gridContinuation{items}` or `continuationContents.musicShelfContinuation{contents}`.
    - Sort (ytmusicapi comment in `prepare_order_params`): `itemSectionRenderer.header.itemSectionTabbedHeaderRenderer.endItems[].dropdownRenderer.entries[].dropdownItemRenderer{label, isSelected, onSelectCommand.browseEndpoint{browseId, params}}`.
    - The playlists grid starts with a "New playlist" card, whose endpoint is not a browse/watch endpoint, so it is dropped and logged. "Liked music" is a `VLLM` playlist card. Liked songs may start with a "Shuffle all" row, which carries a `watchPlaylistEndpoint` and would parse as a playlist; see §3 item 10.
12. **History (signed in, synthetic, after ytmusicapi `get_history`)**:
    - Single-column section list of `musicShelfRenderer{title "Today" / "Yesterday" …, contents[] musicResponsiveListItemRenderer}`.
    - The removal token is the `menu.menuRenderer.items[].menuServiceItemRenderer` whose `icon.iconType == "REMOVE_FROM_HISTORY"`, at `serviceEndpoint.feedbackEndpoint.feedbackToken`.
    - A `musicNotifierShelfRenderer` may replace the shelves. It is skipped and logged.
13. **Signed-in `guide` (synthetic, after YouTube.js `GuideSection` / `GuideEntry`)**: `guideEntryRenderer{formattedTitle, navigationEndpoint.browseEndpoint.browseId, thumbnail?, icon?}`. **YouTube.js shows no owner / subtitle field.** See §9 M6.

## 3. Design decisions

1. **One file per response shape, as in 2.2.**
   - New parsers: `AlbumParser`, `ArtistParser`, `PlaylistParser`, `LibraryParser` (library sections + `guide`), `HistoryParser`, `WatchNextParser`, `LyricsParser`.
   - **Related and artist Show-all need no parser.** They are section lists, and one line in `JSONValue.sectionList` (a third fallback, `contents.sectionListRenderer`) lets `BrowsePage` read Related. This keeps `BrowsePage` unchanged for existing callers (K3).
2. **`InnerTubeError.notAvailable` is the typed "not available" outcome** (D3, K4).
   - The discriminator is **`json["contents"] == nil`**, applied **only to first-page** album, artist and playlist parsing.
   - A playlist continuation response never has `contents` (only `onResponseReceivedActions`), so `Page<Song>(playlistContinuation:)` throws `.unexpectedResponse` when the append action is missing, never `.notAvailable`.
   - `contents` present but without a known root stays `.unexpectedResponse`.
   - A non-2xx stays `.httpStatus` (the transport is untouched). `isTransient` has a `default: false`, so the retry rules do not change.
   - A new error case, not a result enum, because:
     - every other fetch already reports failure through `throws InnerTubeError`;
     - the app has no exhaustive `switch` over the enum (`App/AccountModel.swift` uses `if case`), so adding a case breaks nothing.
3. **`WatchTarget` is the only new "endpoint" type.**
   - `public struct WatchTarget { videoId: String?; playlistId: String?; params: String? }`.
   - It is used for:
     - album Play / Shuffle / Mix and artist Shuffle / Mix;
     - queue chips and the automix split;
     - the input of `watchNext(_:)`.
   - `Chip` gains `watchTarget: WatchTarget? = nil` (additive, defaulted), so queue chips reuse `Chip` and `ItemParser.chips` reads one more endpoint key.
4. **Reuse before new types:**
   - The playlist track list is `Page<Song>`. The album track list is `[AlbumTrack]` (`number: Int?`, `song: Song`), a wrapper, so `Song` stays as it was.
   - Shelves stay `Shelf`.
   - Library items stay `MusicItem`.
   - **The sidebar list is `[Playlist]`.** Liked music is the entry with `browseId == BrowseTarget.likedMusic.browseId` (`"VLLM"`), so no `SidebarPlaylist` type is needed.
   - **Sort options and library sections are `[Chip]`**, whose `target` is the `BrowseTarget{browseId, params}` to fetch.
   - A history row is `HistoryEntry{song: Song, feedbackToken: String?}`, mirroring 2.2's `SearchHistoryEntry`.
   - A queue row is `QueueItem{song: Song, isCurrent: Bool, counterpart: Song?}`.
   - No lyrics is a `nil` `Lyrics?`.
5. **One header type shared by album and playlist:** `PageHeader` (`musicResponsiveHeaderRenderer` ⇄ `musicHeaderRenderer` for the single-column OLAK playlist). Fields:
   - `title`, `subtitle`, `secondSubtitle`, `description`, `thumbnailURL`;
   - `artists: [ItemRef]` (album strapline links, or the playlist facepile owner with its channel id when present);
   - `play`, `shuffle`, `radio: WatchTarget?`;
   - `isExplicit`.

   The album adds `type` (first subtitle run, display text), `year` (a subtitle run whose whole text is `\d{4}`) and `audioPlaylistId` (= `header.play?.playlistId`, exposed for clarity).
6. **The artist page is header fields + `[Shelf]` in server order + About.** "Top songs" is the `.list` shelf with `more` = its `VL…` playlist target. `ItemParser.section` gives `musicShelfRenderer` the `bottomEndpoint` and title-run endpoint as More candidates. The three changes in ItemParser:
   - **More candidates for `musicShelfRenderer`**: today its candidate list is empty.
   - **The duration also reads `fixedColumns`**: today it reads subtitle runs only, so album and playlist rows would have no duration.
   - **A queue-item builder** that reuses the private `destination` and `refs`.

   No existing fixture contains `bottomEndpoint` or `fixedColumns`, so the 2.2 expectations do not move.
7. **Routing contract:**
   - **every `VL…` target (with or without `params`) goes to `playlist(_:)`**;
   - `MPREb_…` goes to `album(_:)`;
   - `UC…` **without** params goes to `artist(_:)`;
   - `UC…` + params, `MPAD…` and every other browse target go to the existing `browse(_:)`.

   The playlist parser accepts both the two-column and the single-column root.
8. **Playlist sections token, not a fetch.** `PlaylistPage.sectionsContinuation` is the section-list token. The caller passes it to the existing `browseContinuation(_:)` and gets `Page<Shelf>`: Suggestions for an own playlist, Related playlists for others. No new method. This keeps Suggestions separate from the tracks (Story 1).
9. **Guest outcomes are defined, not crashes:**
   - library and history as a guest → an empty page / empty days, parsed from the real guest capture;
   - `guide` as a guest → no playlists → fallback to `FEmusic_liked_playlists` → empty;
   - `VLLM` as a guest → `.unexpectedResponse`, because there is no header and no shelf. The UI never asks for it as a guest (UI §4.3, §7 show the sign-in card), and the test pins this outcome.
   - The playlist parser requires a header and treats a missing shelf as an empty track page, so an empty own playlist is not an error.
10. **Drop rules (unchanged from 2.2, applied to the new containers):**
    - rows without identity or title, podcast items, the "New playlist" card, and `unplayableText` queue rows are dropped and logged by renderer key;
    - a history row without a token keeps `feedbackToken == nil`.
    - The liked-songs "Shuffle all" row is **not** special-cased until a real capture shows it; see risk R2.
11. **No new continuation fetch where an existing one fits.**
    - New fetches: `playlistContinuation` (append-action root), `libraryContinuation` (grid / shelf continuation roots) and `watchNextContinuation` (`playlistPanelContinuation`).
    - `nextContinuation` additionally reads `nextRadioContinuationData`.
12. **Text pass-through:**
    - Lyrics `\r\n` is normalised to `\n`, keeping blank lines.
    - Album type, history day titles, subscriber and view counts stay display strings.
    - Nothing keys on a localized label: tabs key on `pageType`, header buttons on `iconType`, the history token on `REMOVE_FROM_HISTORY`, and Liked music on `VLLM`.

## 4. Files to create

All paths are under `Packages/InnerTube/`.

| File | Type | Purpose |
|---|---|---|
| `Sources/InnerTube/EntityPages.swift` | model | Public `WatchTarget`, `PageHeader`, `AlbumTrack`, `AlbumPage`, `ArtistPage`, `PlaylistPage`, `LibraryPage`, `HistoryEntry`, `HistoryDay`, `QueueItem`, `WatchNext`, `Lyrics`. All are `Sendable`, `Equatable` and public with public memberwise `init`s, like `Shelf.swift`. |
| `Sources/InnerTube/PageHeaderParser.swift` | parser | `PageHeader(responsive:)` for `musicResponsiveHeaderRenderer` (also unwrapping `musicEditablePlaylistDetailHeaderRenderer.header`), `PageHeader(simple:)` for `musicHeaderRenderer`, and `JSONValue.twoColumnHeader` / `twoColumnSections` helpers. |
| `Sources/InnerTube/AlbumParser.swift` | parser | `AlbumPage(album:)`: header, type, year, numbered tracks (`index`), shelves via `ItemParser.section`. `contents == nil` → `.notAvailable`; no two-column header → `.unexpectedResponse`. |
| `Sources/InnerTube/ArtistParser.swift` | parser | `ArtistPage(artist:)`: immersive (or visual) header, subscribe button, Shuffle / Mix, shelves via `parseBlocks(…, ItemParser.section)`, About from `musicDescriptionShelfRenderer`. |
| `Sources/InnerTube/PlaylistParser.swift` | parser | `PlaylistPage(playlist:)` for both roots, and `Page<Song>(playlistContinuation:)` for the append-action root. |
| `Sources/InnerTube/LibraryParser.swift` | parser | `LibraryPage(library:)` (sections chips, sort `dropdownRenderer` entries, grid / shelf items, `itemSectionRenderer` unwrap), `Page<MusicItem>(libraryContinuation:)`, and `[Playlist](guide:)` (`VL…` `guideEntryRenderer`s in order). |
| `Sources/InnerTube/HistoryParser.swift` | parser | `[HistoryDay](history:)`: one day per `musicShelfRenderer`, rows through `ItemParser.item` + the `REMOVE_FROM_HISTORY` token. |
| `Sources/InnerTube/WatchNextParser.swift` | parser | `WatchNext(next:)`: tabs by `pageType` with `unselectable`, queue header, chips, panel items, automix, continuation. Also `Page<QueueItem>(nextContinuation:)`. |
| `Sources/InnerTube/LyricsParser.swift` | parser | `Lyrics?(lyrics:)`: description and footer text, or `nil` for `messageRenderer`, otherwise `.unexpectedResponse`. |
| `Tests/InnerTubeTests/AlbumParserTests.swift` | test | Header, type and year, audio playlist id, tracks 1…N with `fixedColumns` duration, shelves, unknown-shelf injection, not available. |
| `Tests/InnerTubeTests/ArtistParserTests.swift` | test | Header, `channelId` ≠ `browseId`, `isSubscribed == false` as guest, Top songs `.list` + `VL` more, every carousel's More target or `nil`, About, unknown-shelf injection, Show-all fixture through `BrowsePage`. |
| `Tests/InnerTubeTests/PlaylistParserTests.swift` | test | Two-column header + owner + tracks + track token + sections token; single-column OLAK top songs; continuation (last page `nil`); `VLLM`; own header unwrap; Suggestions through `BrowsePage(browse:)`; missing → `.notAvailable`; `{"contents":{}}` → `.unexpectedResponse`; a continuation without the append action → `.unexpectedResponse` (not `.notAvailable`); guest `VLLM` → `.unexpectedResponse`. |
| `Tests/InnerTubeTests/LibraryParserTests.swift` | test | Parameterised over the five library fixtures (kind + continuation); sections and sort chips; continuation; podcast and "New playlist" dropped; guest → empty; `guide` playlists in order with Liked music; guest `guide` → empty. |
| `Tests/InnerTubeTests/HistoryParserTests.swift` | test | Days in order with titles, `videoId` + `PLACEHOLDER_FEEDBACK_*` per row, a row without a token kept as `nil`, a video row, guest → empty. |
| `Tests/InnerTubeTests/WatchNextParserTests.swift` | test | Radio: items, `isCurrent`, chips with `watchTarget`, source, lyrics / related ids, continuation. Album queue: automix target, no chips. No-lyrics: `lyricsBrowseId == nil`, related present. Counterpart: synthetic, set or `nil`. Continuation fixture. |
| `Tests/InnerTubeTests/LyricsParserTests.swift` | test | Text with blank lines preserved and `\n` only, source line; no lyrics → `nil`; unknown root → `.unexpectedResponse`. Related fixture through `BrowsePage`. |
| `Tests/InnerTubeTests/EntityClientTests.swift` | test | One end-to-end test per new fetch through `Script` (path, body keys, auth headers when signed in, parse). Sidebar fallback: two steps, guest `guide` then `library-playlists`. A 404 on `playlist` stays `.httpStatus(404)`. The `INNERTUBE_LIVE=1` playlist paging test. |
| `Scripts/test_scrub_fixture.py` | test | A stdlib `unittest` self-test for the scrubber: a history menu keeps only the `REMOVE_FROM_HISTORY` item with a placeholder token; an email is scrubbed before the handle rule; a trailing `continuationItemRenderer` / `automixPreviewVideoRenderer` survives `--items`. It lives outside `Fixtures/` because its raw input would fail the privacy guard. Run with `python3 -I Scripts/test_scrub_fixture.py`. |
| `Tests/InnerTubeTests/Fixtures/*.json` | fixture | See §6. |

## 5. Files to modify

| File | Change | Why |
|---|---|---|
| `Sources/InnerTube/InnerTubeClient.swift` | Add `case notAvailable` to `InnerTubeError`. Add the public fetches listed in §7. Update the `browse(_:)` doc comment to route `VL…` to `playlist(_:)`. Document the K5 "silent restart" on `playlistContinuation`. | FR-1…FR-6, K4, K5 |
| `Sources/InnerTube/MusicItem.swift` | Add `BrowseTarget` statics: `likedPlaylists`, `likedSongs` (`FEmusic_liked_videos`), `likedAlbums`, `libraryArtists` (`FEmusic_library_corpus_track_artists`), `librarySubscriptions` (`FEmusic_library_corpus_artists`), `history`, `likedMusic` (`VLLM`). | Typed ids for 4.1 / 4.5; no string literals in the app |
| `Sources/InnerTube/Shelf.swift` | `Chip` gains `public let watchTarget: WatchTarget?` and an init parameter defaulted to `nil`. | Queue chips (§3 item 3); existing call sites compile unchanged |
| `Sources/InnerTube/ItemParser.swift` | (a) `chips`: read `navigationEndpoint.queueUpdateCommand.fetchContentsCommand.watchEndpoint` into `watchTarget`. (b) `section`: `musicShelfRenderer` More candidates = `[renderer["bottomEndpoint"], title run endpoint]`. (c) `listRow`: the duration also reads `fixedColumns[].musicResponsiveListItemFixedColumnRenderer.text.runs`. (d) `static func queueItem(_ renderer:) -> Song?` for `playlistPanelVideoRenderer` (title, `longBylineText` refs, `lengthText`, thumbnail, `navigationEndpoint` destination). (e) `static func watchTarget(_ endpoint:) -> WatchTarget?` for `watchEndpoint` / `watchPlaylistEndpoint`. (f) `refs` and `destination` stay private. The new builders live in this file. | Reuse; keeps item-kind rules in one place |
| `Sources/InnerTube/BrowseParser.swift` | `sectionList` adds a third fallback `self["contents"]?["sectionListRenderer"]`. | Related (and any bare section list) through `BrowsePage` |
| `Sources/InnerTube/Page.swift` | `nextContinuation`: also read `continuations[0].nextRadioContinuationData.continuation`. | Radio queue paging |
| `Scripts/scrub-fixture.py` | (1) Menu rule: instead of dropping every non-multi-select `menu`, keep a minimal `menu.menuRenderer.items` with only the `menuServiceItemRenderer`s whose `icon.iconType == "REMOVE_FROM_HISTORY"` (icon + `serviceEndpoint.feedbackEndpoint.feedbackToken` → placeholder via `TOKEN_KEYS`); otherwise drop as today. (2) L1: replace email addresses (`[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}` → `placeholder email`) **before** the `@handle` rule. (3) `trim_list`: when a list is cut to `--items`, re-append its last element if that is a `continuationItemRenderer` or `automixPreviewVideoRenderer`. (4) Trim `continuationItems` like `contents` / `items`. | K2, L1, Story 4 scrubber criterion, Story 1 continuation in a trimmed fixture |
| `Tests/InnerTubeTests/Fixtures/README.md` | One row per new fixture, in the "Real guest captures" or "Synthetic files" table. A note for lyrics (text replaced, structure and source kept). History capture steps: tokens stay as placeholders, titles and ids are replaced with public catalogue items. | `fixtureIsDocumented` |
| `Tests/InnerTubeTests/DiscoveryClientTests.swift` | Not changed. The `{"contents":{}}` → `.unexpectedResponse` test stays as it is. | — |
| `docs/01-reverse-engineering.md` §4.9 | Add rows and bullets: album, artist, Show-all, playlist (two roots, two tokens, append action, visitor restart), not available (200 without `contents`), `next` (tabs by pageType, `unselectable`, chips, automix, radio continuation), lyrics, related, and the guest library / history / guide shapes. Mark the signed-in shapes as following ytmusicapi / YouTube.js and unverified. | ARCH §5.3, BA "record the roots" |
| `docs/00-prd.md` §5 | The F-LIB-2, F-LIB-4, F-PLY-4 and F-PLY-5 "Rows" column gains `2.3`. | BA C2 (traceability only) |

## 6. Fixtures

Capture as in 2.2: guest, `hl=en`, `gl=US`, client `1.20261115.14.00`, with the visitor header from the first response reused. Scrub with `Scripts/scrub-fixture.py` and read every result by eye. No private individual appears in any real fixture: playlists are YouTube Music-owned (`RDCLAK…`) or artist-owned (`OLAK…`).

| File | Kind | Request body (besides `context`) | Trim / notes |
|---|---|---|---|
| `album.json` | real | `browse {"browseId":"MPREb_yXhSI4FCUo6"}` (OK Computer) | `--items 3` (tracks 1–3), both carousels |
| `artist.json` | real | `browse {"browseId":"UCr_iyUANcn9OX_yy9piYoLw"}` (Radiohead) | `--sections 20 --items 2`, so About survives |
| `artist-albums.json` | real | `browse` Albums title-run target `MPADUCr_…` + params | `--items 3` |
| `playlist.json` | real | `browse {"browseId":"VLRDCLAK5uy_nZiG9ehz_MQoWQxY5yElsLHCcG0tv9PRg"}` (118 tracks) | `--items 3` + the trailing continuation kept; the section-list token kept |
| `playlist-continuation.json` | real | `browse {"continuation": <track token>}` + visitor | `--items 3`, last page (no token) |
| `playlist-top-songs.json` | real | `browse` artist Top songs target `VLOLAK5uy_mk1…` + `ggMCCAI%3D` | single-column root, `--items 3` + trailing continuation |
| `playlist-missing.json` | real | `browse {"browseId":"VLPLdoesnotexist0000000000000000000"}` | as returned (scrubbed) |
| `playlist-own.json` | synthetic | own playlist | `musicEditablePlaylistDetailHeaderRenderer.header.musicResponsiveHeaderRenderer` + 2 tracks + section-list token |
| `playlist-suggestions.json` | synthetic | `browse {"continuation": <section-list token of an own playlist>}` | `continuationContents.sectionListContinuation` with a `musicShelfRenderer` "Suggestions" of 2 public catalogue rows |
| `liked-music.json` | synthetic | `browse {"browseId":"VLLM"}` | two-column, "Liked music" header (no owner link), 2 public catalogue rows, trailing continuation |
| `liked-music-guest.json` | real | the same, as a guest | sign-in `messageRenderer` |
| `library-playlists.json` | synthetic | `FEmusic_liked_playlists` | `itemSectionRenderer` → `gridRenderer`: "New playlist" card, Liked music `VLLM`, 1 public playlist; section chips; sort dropdown; `continuations` |
| `library-songs.json` | synthetic | `FEmusic_liked_videos` | `musicShelfRenderer`, 2 rows (song, video) + continuation |
| `library-albums.json` | synthetic | `FEmusic_liked_albums` | grid of 2 albums + 1 podcast show (skipped) |
| `library-artists.json` | synthetic | `FEmusic_library_corpus_track_artists` | shelf of 2 artists |
| `library-subscriptions.json` | synthetic | `FEmusic_library_corpus_artists` | shelf of 2 artists |
| `library-continuation.json` | synthetic | `browse {"continuation": …}` | `continuationContents.gridContinuation`, 1 item, no token |
| `library-guest.json` | real | `FEmusic_liked_playlists` as a guest | sign-in message |
| `guide.json` | synthetic | `guide {}` signed in | Home / Explore / Library section + a playlist section: Liked music `VLLM` then 2 `VLPL…` placeholder playlists |
| `guide-guest.json` | real | `guide {}` as a guest | no playlist section |
| `history.json` | synthetic | `FEmusic_history` | "Today": 2 rows (song with token, video with token); "Yesterday": 1 row without a token; `PLACEHOLDER_FEEDBACK_*` |
| `history-guest.json` | real | `FEmusic_history` as a guest | sign-in message |
| `next-radio.json` | real | `next {"videoId":"jNY_wLukVW0","playlistId":"RDAMVMjNY_wLukVW0"}` | `--items 3` (current first), chips, continuation |
| `next-album.json` | real | `next {"videoId":"jNY_wLukVW0","playlistId":"OLAK5uy_nc6afxSnmK8OFML8dF9q_0D1MBMXsGnL4"}` | `--items 2` + automix kept |
| `next-no-lyrics.json` | real | `next {"videoId":"L7p47zYKJoM"}` (Treefingers) | `--items 2`; Lyrics tab `unselectable` |
| `next-counterpart.json` | synthetic | radio queue with one `playlistPanelVideoWrapperRenderer` (ATV primary, OMV counterpart) and one plain row | after ytmusicapi `parse_watch_playlist` |
| `next-continuation.json` | real | `next {"continuation": <radio token>}` | `--items 2` |
| `lyrics.json` | real structure | `browse {"browseId":"MPLYt_yXhSI4FCUo6-1"}` | **description replaced** by `"Placeholder line 1\r\nPlaceholder line 2\r\n\r\nPlaceholder line 3"`; footer "Source: LyricFind" kept |
| `lyrics-none.json` | real | `browse {"browseId":"MPLYt_ob5cslgCNc0-5"}` | as returned |
| `related.json` | real | `browse {"browseId":"MPTRt_yXhSI4FCUo6-1"}` | `--sections 6 --items 2` |

That makes 30 fixtures (18 real, 12 synthetic). Every synthetic file uses IDs, titles and thumbnails copied from the real guest fixtures, `PLACEHOLDER_*` tokens, and no account data.

## 7. Contract for frontend

The consumers are #16 (4.1 sidebar), #19 (4.4 entity pages), #22 (4.8 player tabs), 2.4 (#11, mutations), 4.5 (library) and 4.6 (queue). They use the public API of `InnerTube`. Every method is `async throws` (`InnerTubeError`) on the `InnerTubeClient` actor and takes `credentials: Credentials?` (`nil` = guest).

### 7.1. Fetches

| Method | Returns | Notes |
|---|---|---|
| `album(_ target: BrowseTarget, credentials:)` | `AlbumPage` | `MPREb_…` (+ optional `params` from an "Other versions" card). `.notAvailable` when missing. |
| `artist(_ target: BrowseTarget, credentials:)` | `ArtistPage` | `UC…` without params. `.notAvailable` when missing. |
| `browse(_ target: BrowseTarget, credentials:)` (existing) | `BrowsePage` | Artist "Show all" for `MPAD…` and `UC…` + params, the Related page (`WatchNext.relatedBrowseId`), and every non-entity section list. |
| `playlist(_ target: BrowseTarget, credentials:)` | `PlaylistPage` | **Every `VL…` target**, including `VLLM` and Show-all `VLOLAK…` + params. `.notAvailable` for private, deleted or non-existent. |
| `playlistContinuation(_ token: String, credentials:)` | `Page<Song>` | `PlaylistPage.tracks.continuation`. As a guest, a lost visitor silently restarts at page 1: after `resetGuestVisitor()`, reload page 1. |
| `browseContinuation(_ token: String, credentials:)` (existing) | `Page<Shelf>` | `PlaylistPage.sectionsContinuation` → "Suggestions" (`.list`, own playlist) and/or "Related playlists". |
| `library(_ target: BrowseTarget, credentials:)` | `LibraryPage` | `BrowseTarget.likedPlaylists / .likedSongs / .likedAlbums / .libraryArtists / .librarySubscriptions`, or a `Chip.target` from `sections` / `sortOptions`. Guest → empty page. |
| `libraryContinuation(_ token: String, credentials:)` | `Page<MusicItem>` | `LibraryPage.items.continuation` |
| `sidebarPlaylists(credentials:)` | `[Playlist]` | `guide`, falling back to `library(.likedPlaylists)` when the guide has no `VL…` entries. Liked music: `browseId == BrowseTarget.likedMusic.browseId`. Guest → `[]`. |
| `history(credentials:)` | `[HistoryDay]` | Guest → `[]`. |
| `watchNext(_ target: WatchTarget, credentials:)` | `WatchNext` | body `videoId?`, `playlistId?`, `params?`. Accepts `Chip.watchTarget`, `WatchNext.automix` and header `play` / `shuffle` / `radio` as is. |
| `watchNextContinuation(_ token: String, credentials:)` | `Page<QueueItem>` | `WatchNext.queue.continuation` |
| `lyrics(_ browseId: String, credentials:)` | `Lyrics?` | `WatchNext.lyricsBrowseId`. `nil` = "Lyrics not available". |

### 7.2. Types

All are `public struct …: Sendable, Equatable`, with public `let`s and a public init.

- `WatchTarget { videoId: String?; playlistId: String?; params: String? }`
- `Chip` adds `watchTarget: WatchTarget?` (queue chips). Library sections and sort options use `target`.
- `PageHeader`:
  - `title: String`;
  - `subtitle: String?` ("Album • 1997", "Playlist • 2025");
  - `secondSubtitle: String?` ("12 songs • 53 minutes");
  - `description: String?`;
  - `thumbnailURL: URL?`;
  - `artists: [ItemRef]` (album artists; playlist owner, whose `browseId` is `nil` when the owner has no link);
  - `play: WatchTarget?`, `shuffle: WatchTarget?`, `radio: WatchTarget?`;
  - `isExplicit: Bool`.
- `AlbumTrack { number: Int?; song: Song }`. `song.artists` is usually empty on album rows: show `header.artists`.
- `AlbumPage`:
  - `header: PageHeader`;
  - `type: String?` (display text);
  - `year: String?`;
  - `audioPlaylistId: String?` (`OLAK5uy_…`);
  - `tracks: [AlbumTrack]`;
  - `shelves: [Shelf]` (Other versions, More from / Releases for you).
- `ArtistPage`:
  - `name: String`;
  - `thumbnailURL: URL?`;
  - `subscriberCountText: String?` ("5.47M subscribers");
  - `isSubscribed: Bool?` (`nil` only when the page has no subscribe button);
  - `channelId: String?` (**use this for subscribe, not the page id**);
  - `shuffle: WatchTarget?`, `radio: WatchTarget?`;
  - `shelves: [Shelf]` (server order; "Top songs" is the `.list` shelf, whose `more` is a `VL…` target → `playlist(_:)`);
  - `description: String?`;
  - `viewCountText: String?`.
- `PlaylistPage`:
  - `header: PageHeader`;
  - `tracks: Page<Song>`;
  - `sectionsContinuation: String?`.
- `LibraryPage`:
  - `sections: [Chip]`;
  - `sortOptions: [Chip]` (`isSelected` marks the current one);
  - `items: Page<MusicItem>`.
- `HistoryDay { title: String; entries: [HistoryEntry] }`
- `HistoryEntry { song: Song; feedbackToken: String? }`. The token is for the 2.4 `feedback` mutation; `nil` = not removable.
- `QueueItem { song: Song; isCurrent: Bool; counterpart: Song? }`. `song.isVideo` tells ATV from OMV; `counterpart` is the other one (signed-in only in practice).
- `WatchNext`:
  - `queue: Page<QueueItem>`;
  - `automix: WatchTarget?`;
  - `chips: [Chip]`;
  - `playingFrom: String?`;
  - `playlistId: String?` (the queue source id; "Playing from" has no endpoint);
  - `lyricsBrowseId: String?` (`nil` when the tab is `unselectable`);
  - `relatedBrowseId: String?`.

  **The bridge (3.2) stays the source of truth for the live queue.** These items are for the initial display and for chip switching.
- `Lyrics { text: String; source: String? }`. The text uses `\n` line breaks and keeps blank lines.
- `InnerTubeError.notAvailable`: shows "This playlist isn't available" (UI §8.1) and the equivalents for album and artist.

## 8. Implementation order

1. **Models and errors.** Add `EntityPages.swift`, the `Chip.watchTarget` parameter, the `BrowseTarget` statics and `InnerTubeError.notAvailable`. Build.
2. **Shared parsing.** `ItemParser` (a)–(e), the `sectionList` fallback, `nextContinuation` radio data. Run the 2.2 suite: it must stay at 153 passing.
3. **Scrubber.** Make the four changes, add `test_scrub_fixture.py`, and run it.
4. **Real captures.** Capture and scrub every real fixture in §6 (one guest session, visitor reused), replace the lyric text, and add README rows. Run `swift test --filter FixturePrivacyTests`.
5. **Parsers, each with its test file (TDD), in this order:**
   1. `PageHeaderParser`;
   2. `AlbumParser`;
   3. `PlaylistParser` (both roots, continuation, not available);
   4. `ArtistParser` (+ Show-all through `BrowsePage`);
   5. `LyricsParser` + Related through `BrowsePage`;
   6. `WatchNextParser`.
6. **Synthetic fixtures + parsers:** `LibraryParser` (+ guide), `HistoryParser`, `playlist-own`, `playlist-suggestions`, `liked-music`, `next-counterpart`.
   - Check each synthetic shape against the ytmusicapi / YouTube.js source again before writing it (Context7 `ytmusicapi`, `youtubei.js`).
7. **Client fetches + `EntityClientTests`,** including the sidebar fallback, the 404 → `.httpStatus` test and the live paging test. Run it once with `INNERTUBE_LIVE=1`.
8. **Docs:** RE §4.9 and the PRD rows.
9. **Full `swift test`,** then `xcodebuild -project Redwave.xcodeproj -scheme Redwave -destination 'platform=macOS' -quiet build` (the root holds two projects, so `-project` is required) to prove the app still links: the package API grew, but nothing in `App/` changes.

## 9. API mismatches against the BA spec (each is a BLOCKER for the gate to accept)

| # | BA assumption | Wire / plan | Effect |
|---|---|---|---|
| M1 | Album footer: release date, track count and total duration, label | No footer exists. Only `secondSubtitle` ("12 songs • 53 minutes") is present; release date and label are absent (counted: 0). | `AlbumPage` has no release-date / label fields. 4.4 shows `header.secondSubtitle`. |
| M2 | Not available: "200 + `alerts[]` or 4xx" | 200 with **no `contents` key**, no alerts, for playlist, album and artist alike. | Discriminator = missing `contents`. Private playlists are not captured (R3). |
| M3 | Artist subscribe state "missing as a guest (`nil`, not `false`)" | A guest receives `subscribed: false` and a `channelId`. | `isSubscribed` is `false` for guests. The UI must gate Subscribe on sign-in, not on `nil`. |
| M4 | Artist channel id = page id | The subscribe `channelId` (`UCq19-…`) ≠ the page `browseId` (`UCr_iy…`). | 2.4 must use `ArtistPage.channelId`. |
| M5 | "Playing from" source has a name **and a target** | Header subtitle text only, no endpoint. | `WatchNext.playlistId` (from `playlistPanelRenderer`) is the closest target. The UI already knows what it started. |
| M6 | Sidebar entries have "title, owner and target" | The guide entry shape (YouTube.js) has title, endpoint, icon and thumbnail. **No owner field is known.** | Guide-sourced `Playlist.subtitle` is `nil` until a real signed-in capture shows an owner. The fallback (`liked_playlists`) has it. 4.1 must allow a missing owner. |
| M7 | Counterpart id in `next` | No `playlistPanelVideoWrapperRenderer` was returned to a guest (5 ids, with and without `isAudioOnly`). | Parsed per ytmusicapi on a synthetic fixture. `counterpart` is `nil` for guests. |
| M8 | Lyrics disabled tab has no endpoint | The endpoint is present, with `unselectable: true`. | `lyricsBrowseId` is `nil` when `unselectable`. |
| M9 | Artist "Show all" parses with the grid / section-list parsing | True for `MPAD…` and `UC…` + params. **False for Top songs and Videos**: those are `VLOLAK…` single-column playlists. | They route to `playlist(_:)` (§7.1). |
| M10 | Own-playlist Suggestions in the playlist response | They arrive via the section-list continuation (ytmusicapi); guests get "Related playlists" there. | `PlaylistPage.sectionsContinuation` + existing `browseContinuation`. |

## 10. Risks and edge cases

- **R1. Synthetic share.** 12 of 30 fixtures (library ×5 + continuation, guide, history, own playlist, Suggestions, `VLLM`, counterpart) are hand-built. The library chips location (`sectionListRenderer.header.chipCloudRenderer`), the sort `dropdownItemRenderer.label` key and the guide playlist section are the least certain. Wrong guesses surface in 4.1 / 4.5 and need real scrubbed captures (README procedure).
- **R2. Liked songs "Shuffle all" row** (ytmusicapi pops it when there are ≥ 2 rows). It would parse as a `.playlist` item at the top of `library(.likedSongs)`. It is left as is until a real capture confirms it; the 4.5 UI should tolerate a leading playlist item.
- **R3. Private playlist of another user** was not captured. Assumed: 200 without `contents`, like a missing id. If it is a 4xx instead, it stays `.httpStatus` (BA: never turn other 4xx into not-available).
- **R4. Guest continuation (K5).** Without the issuing visitor, page 2 silently repeats page 1. The live test asserts disjoint ids, and the doc comment tells callers to reload page 1 after `resetGuestVisitor()`.
- **R5. Shared ItemParser changes** (`musicShelfRenderer` More, `fixedColumns` duration, chip `watchTarget`) touch 2.2 behaviour. No existing fixture has those keys, and the 153 baseline tests must stay green.
- **R6. Scrubber menu allowance** must keep only the history removal item. Like / library / share menu items must still be dropped. The self-test covers this.
- **R7. Lyrics copyright.** Real lyric text must never reach a fixture. The README row and the review check this.
- **R8. Playlist owner privacy.** Real user playlists expose the owner name and channel in `facepile`, a shape that `mask_name_links` and the privacy regex do not cover. Only YouTube Music-owned or artist-owned playlists are captured.
- **R9. Size.** About 9 new source files, 9 test files and 30 fixtures. The order in §8 keeps every step green.
- Edge cases covered by tests:
  - an empty playlist (no shelf → empty page);
  - the last page (`nil` token);
  - an unknown shelf injected into the album and artist pages;
  - a history row without a token;
  - the current item not at index 0 (the parser uses `selected`, not position);
  - lyrics blank lines;
  - a guest for each account-only fetch;
  - a 404 on `playlist` → `.httpStatus(404)`.

## 11. Skills to invoke during implementation

- `swift-foundation:swift-conventions`: value types, `Sendable`, typed throws, access control.
- `swift-foundation:swift-testing`: parameterised fixture tests, `#require`, the env-gated live test.
- `swift-foundation:swift-tooling`: `swift test` in the package, the `xcodebuild` link check.
- `apple-plugin:apple-testing`: transport-seam doubles.
- `superpowers:test-driven-development` (per parser) and `superpowers:verification-before-completion`.
- Context7 (`ytmusicapi`, `youtubei.js`) before each synthetic fixture.
- Not applicable, because there is no UI in this aspect: `swiftui-*`, `macos-app`, `ios-ipados`, `watchos-app`.
