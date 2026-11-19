# Development plan: InnerTube models and parsers for home, explore, search and suggestions (backlog 2.2, issue #9)

Pass: PLAN. No source code has been changed.

Sources:
- `_brief.md`, which holds the verbatim issue #9 body and the user decisions. These override the BA open questions and its "issue not read" caveats.
- `01-business-analysis.md`.
- `docs/plans/issue-8/*` for the 2.1 patterns.
- The current code in `Packages/InnerTube`.
- **Live guest probes made during planning** (`hl=en`, `gl=US`, client `1.20261115.14.00`, 2026-11-19). The raw captures stay in the session scratchpad and were **not** committed.

Baseline: `swift test` in `Packages/InnerTube` passes 87 tests in 13 suites.

## 0. Issue, spec and decisions

| # | Point | Plan follows |
|---|---|---|
| D1 | Explore subpages (new releases, charts with `formData` country + trend arrows, moods & genres, category + params) | **In scope** (user decision Q1). This includes the request-body change for Charts (K3). |
| D2 | Fixtures | Real, scrubbed **guest** captures, fetched live by the dev agent. Minimal **synthetic** JSON, clearly marked, for the signed-in-only shapes. The user adds real signed-in captures later, and the privacy guard covers them automatically (user decision Q2). |
| D3 | Search filters | **In scope**: filter chips from the response, filtered results, continuation. Podcast, episode and profile results are skipped and logged (they depend on #7). |
| D4 | Issue names the models `Song`, `Album`, `Artist`, `Playlist`, `Shelf`, `SearchResults` | Those six are the item and page models. Video folds into `Song` (`isVideo`) so the issue's set stays. |
| D5 | Issue "Done when: from a temporary screen **or a test** you can fetch Home and the results of a search query" | Deterministic transport-seam tests, plus one env-gated live smoke test. No temporary screen, so no app change. |
| D6 | Branch `feature/innertube-browse-search` in the issue | The pipeline branch is `feature/issue-9`. Noted only. |

## 1. Project shape

| Aspect | Value |
|---|---|
| Project system | XcodeGen (`project.yml`). The change is confined to the local SPM package `Packages/InnerTube`. No project regeneration is needed: no app files change. |
| Target / platform | Package `InnerTube`, `platforms: [.macOS(.v14)]`, tools 6.0, so Swift 6 language mode with strict concurrency. It depends on `Auth`. |
| Swift settings | Package defaults. No default actor isolation. Nothing is changed. |
| State / UI / persistence / navigation | Not touched (data layer only). |
| Networking | `InnerTubeClient` actor, `URLSession` behind the `Transport` seam, `post` (signed) and `postGuest` (visitor-tracked). Both are reused. |
| Parsing | `JSONValue` enum, `parseBlocks` (skip + log renderer key), `Page<T>`, `nextContinuation`, `text()`, `lastThumbnailURL()`. All are reused. |
| Tests | Swift Testing. `@testable import InnerTube`. The private `Script` transport stub lives in `ClientTransportTests`. |
| Localization / design system | n/a (no user-facing strings) |
| Dependencies | None added |

## 2. What the live probes established

These findings override the BA's **[known, unverified]** wire shapes. Each one that differs from the BA is listed in §9 as an API mismatch.

1. **Home** `browse FEmusic_home`:
   - Root: `contents.singleColumnBrowseResultsRenderer.tabs[0].tabRenderer.content.sectionListRenderer`.
   - Chips are in `header.chipCloudRenderer.chips[].chipCloudChipRenderer`: `text` and `navigationEndpoint.browseEndpoint{browseId: FEmusic_home, params}`.
   - Shelves are `musicCarouselShelfRenderer`, with header `musicCarouselShelfBasicHeaderRenderer{title, strapline?, moreContentButton?}`. Items are `musicTwoRowItemRenderer` (cards) or `musicResponsiveListItemRenderer` (rows).
   - The guest feed also has `musicTastebuilderShelfRenderer`. It is skipped and logged.
   - Paging uses the **older** form `sectionListRenderer.continuations[0].nextContinuationData.continuation`. A guest feed ran 4 pages.
2. **Continuation** (closes the issue-8 G1 carry-over):
   - Body `{"continuation": token}` (the 2.1 form) works. The query form `ctoken=&continuation=&type=next` gives the same result.
   - **The guest request must carry the same `X-Goog-Visitor-Id`.** Without it, the 200 response holds an empty tab and no `continuationContents`. `postGuest` already sends the stored visitor, so this works as long as `GuestVisitor` is not reset between pages.
   - Page-2 roots:
     - Home: `continuationContents.sectionListContinuation{contents, continuations}`.
     - Filtered search: `continuationContents.musicShelfContinuation{contents, continuations}`.
   - The existing `nextContinuation` works unchanged when it is called on those objects. **K2 needs only a container switch, not a `Page.swift` change.**
3. **More target:**
   - `moreContentButton.buttonRenderer.navigationEndpoint` is either a `browseEndpoint` (More) or a `watchEndpoint` ("Play all").
   - Only a browse endpoint becomes the `Shelf.more` target. The title run's `navigationEndpoint.browseEndpoint` is used as a fallback.
   - More targets observed: `FEmusic_moods_and_genres_category`+params, `FEmusic_moods_and_genres`, `FEmusic_new_releases_albums`/`_videos`, and playlists `VL…`.
   - A More page (`FEmusic_new_releases_albums`) is a section list holding a single `gridRenderer{items[musicTwoRowItemRenderer]}`.
4. **Explore** `FEmusic_explore`:
   - Section list. The first section is a `gridRenderer` of three `musicNavigationButtonRenderer{buttonText, clickCommand.browseEndpoint}` tiles: New releases / Charts / Moods & genres.
   - Then come carousels: New albums & singles, Moods & genres (holding `musicNavigationButtonRenderer` items whose targets are `FEmusic_moods_and_genres_category`+params), Trending (rows) and New music videos.
5. **Subpages:**
   - All subpages have a top-level `header.musicHeaderRenderer` (page title) and the same section list.
   - `FEmusic_new_releases`: grid + carousels.
   - `FEmusic_moods_and_genres`: `gridRenderer` sections with `header.gridHeaderRenderer.title` and `musicNavigationButtonRenderer` items.
   - `FEmusic_moods_and_genres_category`+params: carousels of playlists.
6. **Charts** `FEmusic_charts`:
   - Request body `formData: {"selectedValues": ["US"]}` works. **This needs a nested body (K3).**
   - **Without `formData` the country follows the caller's IP, not `gl`**: the probe got the capturer's country. The fixture must therefore be captured with explicit `formData` US.
   - The country selector is the first section: `musicShelfRenderer.subheaders[0].musicSideAlignedItemRenderer.startItems[0].musicSortFilterButtonRenderer.menu.musicMultiSelectMenuRenderer.options[].musicMultiSelectMenuItemRenderer{title, formItemEntityKey}`.
   - The country code is found **only** in `frameworkUpdates.entityBatchUpdate.mutations[].payload.musicFormBooleanChoice{id, opaqueToken, selected}`. It is joined to the menu option on `formItemEntityKey == id`. `ZZ` = Global.
   - Ranked rows carry `customIndexColumn.musicCustomIndexColumnRenderer{text: "1", icon.iconType}` with `ARROW_DROP_UP` / `ARROW_DROP_DOWN` / `ARROW_CHART_NEUTRAL`, or no icon.
   - US charts also have a "Weekly top podcast shows" shelf, whose items are `MUSIC_PAGE_TYPE_PODCAST_SHOW_DETAIL_PAGE`. All of its items are skipped, so the shelf is dropped.
7. **Search** `search`:
   - Root: `contents.tabbedSearchResultsRenderer.tabs[0].tabRenderer.content.sectionListRenderer`.
   - Filter chips: `header.chipCloudRenderer.chips[].chipCloudChipRenderer.navigationEndpoint.searchEndpoint{query, params}`. The guest probe offered 9: Artists, Albums, Episodes, Songs, Community playlists, Videos, Featured playlists, Profiles, Podcasts.
   - **Unfiltered results are not titled per-type `musicShelfRenderer` sections with "Show all".** They are a `musicCardShelfRenderer` top-result card, then ~28 `itemSectionRenderer`s, each holding **one** `musicResponsiveListItemRenderer`. There is no continuation. This was confirmed on 4 queries (radiohead, bohemian rhapsody, taylor swift, lofi beats).
   - The top-result card has `title` runs, `subtitle` runs, `thumbnail` and `onTap` (a browse or watch endpoint).
   - Filtered (`params`): one `musicShelfRenderer{title, contents[20], continuations}` in the older form. Page 2 is under `musicShelfContinuation`.
   - Correction: `itemSectionRenderer.contents[0].showingResultsForRenderer{correctedQueryEndpoint.searchEndpoint.query, originalQueryEndpoint.searchEndpoint{query, params}}`. The parser also accepts `didYouMeanRenderer{correctedQueryEndpoint}` (the BA's "did you mean"). That variant was not observed, so the parser reads it only through the same endpoint keys.
   - The nonsense query `zxqvjkwpqzzqq ywyw` still returned a card and results. The "no results" case is therefore a **synthetic** fixture.
   - Item kinds seen: song, video, album, playlist, artist, Episode (`MUSIC_VIDEO_TYPE_PODCAST_EPISODE`), Profile (`MUSIC_PAGE_TYPE_USER_CHANNEL`), and Podcast (`MUSIC_PAGE_TYPE_PODCAST_SHOW_DETAIL_PAGE`).
8. **Suggestions** `music/get_search_suggestions`:
   - `contents[].searchSuggestionsSectionRenderer.contents[]`, in two sections:
     - text: `searchSuggestionRenderer{suggestion.runs (bold prefix), navigationEndpoint.searchEndpoint.query}`;
     - entities: `musicResponsiveListItemRenderer` with `navigationEndpoint` browse (artist / album) or watch (song / video).
   - History (signed in, empty input) was not observable as a guest. Synthetic shape, after the public `ytmusicapi` suggestions parser: `historySuggestionRenderer{suggestion.runs, navigationEndpoint.searchEndpoint.query, serviceEndpoint.feedbackEndpoint.feedbackToken}`. **The dev must check this with Context7 (`ytmusicapi` `parse_search_suggestions`) before writing the synthetic fixture.**
9. **Item discrimination**: by structure only, never by the localized "Song"/"Album" text.
   - The item's **own** endpoint decides:
     - `musicTwoRowItemRenderer.navigationEndpoint`;
     - `musicResponsiveListItemRenderer.navigationEndpoint`, otherwise `flexColumns[0]…runs[0].navigationEndpoint.watchEndpoint`, otherwise `overlay…musicPlayButtonRenderer.playNavigationEndpoint.watchEndpoint`, otherwise `playlistItemData.videoId`;
     - `musicCardShelfRenderer.onTap`.
   - Unfiltered-search songs have no top-level `navigationEndpoint`.
   - **Never search recursively** (no `values(forKey:)` pattern). Menus contain artist, album and `MUSIC_PAGE_TYPE_TRACK_CREDITS` endpoints, which would be mistaken for the item's own.
   - Browse endpoint: `pageType` ALBUM → `Album`, ARTIST → `Artist`, PLAYLIST → `Playlist`. USER_CHANNEL, PODCAST_SHOW_DETAIL_PAGE and anything else → skip.
   - Watch endpoint: `watchEndpointMusicSupportedConfigs.watchEndpointMusicConfig.musicVideoType`. ATV, or a missing type → song. OMV / UGC → `isVideo`. PODCAST_EPISODE → skip.
10. **Thumbnails:**
    - Hosts: `yt3.googleusercontent.com`, `lh3.googleusercontent.com`, `i.ytimg.com`, `yt3.ggpht.com`, all inside the existing allowlist.
    - 7 thumbnails on `www.youtube.com` / `music.youtube.com` (icon-like) are outside it and become `nil`. The policy is not loosened.
    - No `http` or protocol-relative URLs were seen.
11. **Other item fields:**
    - The explicit flag is `badges[].musicInlineBadgeRenderer.icon.iconType == MUSIC_EXPLICIT_BADGE`.
    - Duration is the last subtitle run when it matches `^\d+(:\d{2})+$`. Search rows carry no `fixedColumns`.

## 3. Design decisions

1. **One shared section parser feeds every section-list page.** Home, Explore, New releases, Moods & genres, mood category, the More page, the Home continuation, and the shelf part of Charts all have the same `sectionListRenderer` shape.
   - `section(_:) -> Shelf?` maps the three containers to `Shelf`: `musicCarouselShelfRenderer.contents`, `gridRenderer.items` and `musicShelfRenderer.contents`.
   - `item(_:) -> MusicItem?` maps the four item renderers.
   - **One parser file per page type** (the issue rule) means one file per **response shape**:
     - `BrowseParser`: every section-list browse page, its continuation, and Home chips as its header;
     - `ChartsParser`: browse page + countries + ranks;
     - `SearchParser`;
     - `SuggestionsParser`;
     - `ItemParser`: shared renderers.
   - Explore and its subpages are not split into separate files. They differ only in content, not shape, and separate files would duplicate code.
2. **Models keep the issue's six types and as little extra as possible.**
   - Thumbnails are a single `URL?`: the largest one that passes the allowlist, through the existing `lastThumbnailURL`.
   - The subtitle is a joined `String?` for display, plus structured `artists` / `album` refs for navigation.
   - No page-kind enum: `BrowseTarget{browseId, params}` is enough for the 4.x routes in UI §1.3.
3. **Auth mode is a parameter, not a method pair.**
   - `public struct Credentials {cookies, authUserIndex}`.
   - Every new fetch takes `credentials: Credentials?` (`nil` = guest). One private `fetch(_:body:credentials:)` sends to the existing `post` / `postGuest`.
   - This avoids 14 near-duplicate methods. Retry, 401 and visitor rules are unchanged, because both paths are reused as they are.
   - Existing `accountMenu` / `connectAsGuest` are not touched.
4. **K3: request body widens from `[String: String]` to `[String: any Sendable]`.** This allows Charts' nested `formData`.
   - Existing call sites and tests (string literals) compile unchanged.
   - `attachPayload` adds a `JSONSerialization.isValidJSONObject` guard that throws `.unexpectedResponse`. `data(withJSONObject:)` raises an Objective-C exception on invalid input, and the current `do/catch` does not catch that.
5. **K1: `text()` joins all runs**, and an empty result returns `nil`.
   - The three existing callers (`AccountInfo` name and handle, `AccountListItem` name and handle) read single-run values, so their behavior does not change.
   - This fixes subtitles, and highlighted suggestion text (bold prefix + rest).
6. **K4: fixtures live in `Packages/InnerTube/Tests/InnerTubeTests/Fixtures/`** and the test target declares `resources: [.copy("Fixtures")]`. They are loaded with `Bundle.module`.
   - SwiftPM requires resources under the target path, so ARCH §12's sibling `Fixtures/` is not possible without a custom target `path`.
   - The ARCH §12 tree line is updated.
   - SwiftUI previews (4.x) can later copy or reference the same files, so this location does not block them.
7. **Drop rules:**
   - An item without identity or title → `nil` (logged via `parseBlocks`).
   - A shelf whose items all drop → `nil` (logged), so no empty headers appear.
   - A page with no root container → `InnerTubeError.unexpectedResponse`.
   - An empty or unknown suggestions response → empty `SearchSuggestions`, no throw.

## 4. Files to create

All paths are under `Packages/InnerTube/`.

| Path | Type | Purpose |
|---|---|---|
| `Sources/InnerTube/MusicItem.swift` | model | Public `BrowseTarget`, `ItemRef`, `Song`, `Album`, `Artist`, `Playlist`, `NavigationLink`, `ChartRank`, `MusicItem` (sum type). All are `Sendable, Equatable`, with public memberwise inits so 4.x previews and tests can build values. |
| `Sources/InnerTube/Shelf.swift` | model | Public `Shelf`, `Shelf.Layout`, `Chip`, `BrowsePage`, `ChartsPage`, `ChartCountry` |
| `Sources/InnerTube/SearchResults.swift` | model | Public `SearchResults`, `SearchCorrection`, `SearchSuggestions`, `SearchHistoryEntry` |
| `Sources/InnerTube/ItemParser.swift` | parser | Internal helpers:<br>• `item(_:)`: the four renderers → `MusicItem?`<br>• `section(_:)`: three containers → `Shelf?`<br>• `browseTarget(_:)`<br>• `itemRefs(runs)`<br>• `explicit`, `duration`, `rank` |
| `Sources/InnerTube/BrowseParser.swift` | parser | `BrowsePage(browse:)`: first page or `sectionListContinuation`, chips from `header.chipCloudRenderer`, title from `header.musicHeaderRenderer` |
| `Sources/InnerTube/ChartsParser.swift` | parser | `ChartsPage(charts:)`: the `BrowsePage` plus countries, joined from the selector options and `frameworkUpdates` mutations |
| `Sources/InnerTube/SearchParser.swift` | parser | `SearchResults(search:)`: first page, or `musicShelfContinuation` for filtered page 2 |
| `Sources/InnerTube/SuggestionsParser.swift` | parser | `SearchSuggestions(suggestions:)` |
| `Tests/InnerTubeTests/Fixtures/*.json` | fixture | See §6 |
| `Tests/InnerTubeTests/Fixtures/README.md` | doc | How each file was captured (endpoint, body, `hl`/`gl`, date, client version) and which files are synthetic. Includes the scrub checklist for the user's signed-in captures. |
| `Scripts/scrub-fixture.py` (package-local) | tool | Python 3, standard library only. Reads a raw capture, deletes the privacy and tracking keys, replaces continuation tokens, trims lists, and writes the fixture. Kept for recaptures after format drift and for the user's signed-in captures. Not part of any target. |
| `Tests/InnerTubeTests/Support/ScriptedTransport.swift` | test helper | `Script` / `Step` moved out of `ClientTransportTests` (now internal) so the end-to-end tests reuse them. Adds `Step.fixture(String)`. |
| `Tests/InnerTubeTests/Support/Fixture.swift` | test helper | `Fixture.json(_ name:) -> JSONValue`, `Fixture.data(_:)`, `Fixture.all` (every file URL in the bundle's `Fixtures` dir) |
| `Tests/InnerTubeTests/BrowseParserTests.swift` | test | Home (guest + synthetic signed-in), Home continuation, Explore, New releases, Moods & genres, mood category, More page, injected unknown shelf |
| `Tests/InnerTubeTests/ChartsParserTests.swift` | test | Countries, selected country, ranks and trends, podcast shelf dropped |
| `Tests/InnerTubeTests/SearchParserTests.swift` | test | Unfiltered, filtered + continuation page, correction, synthetic no-results, unsupported kinds skipped |
| `Tests/InnerTubeTests/SuggestionsParserTests.swift` | test | Guest text + entities in order, synthetic history with `feedbackToken`, empty / unknown → empty |
| `Tests/InnerTubeTests/ItemParserTests.swift` | test | Small inline-JSON cases: kind discrimination, menu endpoints ignored, video vs song, explicit, missing title/ID dropped, disallowed thumbnail → nil |
| `Tests/InnerTubeTests/DiscoveryClientTests.swift` | test | End to end through `Script`:<br>• request bodies (`browseId`, `params`, `query`, `input`, `continuation`, Charts `formData`);<br>• guest has no auth headers, signed has SAPISIDHASH;<br>• fixture bytes → models;<br>• the env-gated live smoke test (`INNERTUBE_LIVE=1`) fetches Home and a search |
| `Tests/InnerTubeTests/FixturePrivacyTests.swift` | test | Guard over **every** file in `Fixtures/`, see §6 |

## 5. Files to modify

| Path | Change | Why |
|---|---|---|
| `Packages/InnerTube/Package.swift` | `.testTarget(name: "InnerTubeTests", dependencies: ["InnerTube"], resources: [.copy("Fixtures")])` | K4 |
| `Sources/InnerTube/AccountInfo.swift` | `text()` joins all runs, empty → `nil` | K1, fixed once in shared code |
| `Sources/InnerTube/InnerTubeRequest.swift` | `body: [String: any Sendable]` in `make` / `makeGuest` / `attachPayload`, plus the `isValidJSONObject` guard | K3 (Charts `formData`) |
| `Sources/InnerTube/InnerTubeClient.swift` | `body` type in `post` / `postGuest` (K3), the public `Credentials`, a private `fetch`, and the public fetch methods (§7) | FR-6 |
| `Tests/InnerTubeTests/ClientTransportTests.swift` | Remove the private `Script` / `Step` (moved to Support). No test logic changes. | Shared stub |
| `Tests/InnerTubeTests/JSONValueTests.swift` (or `AccountParsingTests`) | One multi-run `text()` test, plus one empty-runs → `nil` test | K1 |
| `docs/01-reverse-engineering.md` | New subsection "4.9 InnerTube discovery endpoints (verified 2026-11-19)": roots, continuation form and visitor requirement, the Charts `formData` + country token join, the flat search shape | Closes the issue-8 G1 carry-over |
| `docs/02-architecture.md` line 338 | `InnerTube/ — Sources, Tests (fixtures in Tests/InnerTubeTests/Fixtures)` | K4 |

`App/*`, `project.yml`, `Info.plist`, entitlements: **no changes.**

## 6. Fixtures

**Capture step (dev, live, guest only):**
- Use `curl` or the script with `hl=en`, `gl=US` and the current `ClientVersion.builtIn`.
- Use the visitor from the first Home response for the follow-up calls (continuations and subpages).
- Raw captures go to the scratchpad and never to the repo.

| File | Request | Kind |
|---|---|---|
| `home.json` | `browse {browseId: FEmusic_home}` | real |
| `home-continuation.json` | `browse {continuation}` + visitor header | real |
| `home-signed-in.json` | Listen again shelf with strapline, a chip row, one normal shelf | **synthetic** |
| `explore.json` | `browse FEmusic_explore` | real |
| `new-releases.json` | `browse FEmusic_new_releases` | real |
| `moods-and-genres.json` | `browse FEmusic_moods_and_genres` | real |
| `mood-category.json` | `browse FEmusic_moods_and_genres_category` + params from explore | real |
| `more-albums.json` | `browse FEmusic_new_releases_albums` + params (More page) | real |
| `charts.json` | `browse {browseId: FEmusic_charts, formData: {selectedValues: ["US"]}}` | real, **must** use explicit US |
| `search.json` | `search {query: "radiohead"}` | real |
| `search-songs.json` | `search {query, params: <Songs chip params>}` | real |
| `search-songs-continuation.json` | `search {continuation}` + visitor | real |
| `search-correction.json` | `search {query: "radiohed"}` | real |
| `search-empty.json` | Section list with only chips and no contents | **synthetic** |
| `suggestions.json` | `music/get_search_suggestions {input: "radi"}` | real |
| `suggestions-history.json` | `historySuggestionRenderer` entries with `feedbackToken` | **synthetic** (shape checked against ytmusicapi via Context7) |

**Scrub and trim (script, then a manual review):**
- **Delete** `visitorData` / `VISITOR_DATA` everywhere, and the whole `responseContext`.
  - Do not use a placeholder: a valid-looking value would be accepted into `GuestVisitor.shared` by the end-to-end tests. That would race the visitor-header assertion in `ClientTransportTests`, because only that suite is `.serialized`.
- Delete `trackingParams`, `clickTrackingParams`, `serviceTrackingParams`, `loggingContext`, `accessibility*`, and `menu` (it is unused and makes up most of the bytes).
- Delete `frameworkUpdates` **except** `musicFormBooleanChoice` payloads in `charts.json`.
- Replace every continuation token with `PLACEHOLDER_CONTINUATION_<n>`. Tokens are visitor-bound.
- Replace third-party profile handles in the search Profile item with `@placeholder`.
- Trim:
  - Home: 3 shelves × 3 items, including both card and row items.
  - Explore: tiles + 1 shelf of each kind.
  - Grids: 3 items.
  - Search: card + one item of each kind (album, song, video, playlist, artist, episode, profile, podcast).
  - Chart rows: one item per trend.
  - Target: each file under ~30 KB.
- Before committing: `grep` every fixture for the raw `visitorData` value seen during capture, `SAPISID`, `__Secure-`, and `@` email patterns.

**README scrub checklist for the user's real signed-in captures** (written out in full in the README):
1. Delete `responseContext`, every `visitorData` / `VISITOR_DATA`, and all tracking keys. Running the script does this.
2. Replace every `feedbackToken` with `PLACEHOLDER_FEEDBACK_<n>`, and every continuation token with `PLACEHOLDER_CONTINUATION_<n>`.
3. History suggestions: replace each `query` and the `suggestion.runs` text with generic queries (`placeholder query 1`).
4. Listen again, Recently played, Mixed for you, "Because you listened to …" and other personalised shelves:
   - keep at most 2 items;
   - replace them with public catalogue items taken from the guest fixtures (title, IDs, thumbnails);
   - replace a strapline that names the user, and the header avatar thumbnail, with placeholders.
5. Remove anything that holds the account name, handle, own channel ID (`UC…` of the account), avatar URL or email.
6. Run `swift test --filter FixturePrivacyTests`, then read the diff by eye before committing.
The synthetic `suggestions-history.json` already follows rules 2–3.

**Privacy guard (`FixturePrivacyTests`)**:
- It runs over every `*.json` in `Fixtures/`, including future user-added signed-in captures. The README is excluded because its scrub checklist names these keys.
- It fails if any file contains:
  - cookie names as JSON keys or cookie assignments at a word boundary (`\b(SAPISID|__Secure-[0-9A-Za-z-]+|SID|HSID|SSID|APISID|LOGIN_INFO)=`, and `"SAPISID"`), or the keys `"Authorization"` / `"Cookie"`. Bare `SID` / `HSID` substrings are not matched, because they occur inside base64 thumbnail URLs;
  - an email pattern `[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}`;
  - a `visitorData` / `VISITOR_DATA` key, `responseContext`, `activeAccountHeaderRenderer`, or `accountName`;
  - a `continuation`, `token` or `feedbackToken` key whose value is not `PLACEHOLDER_…`.
- It also requires every `*.json` to have a README row, so no capture goes undocumented.

## 7. Contract for frontend

These are the public surface 4.2 (Home / Explore) and 4.3 (Search) bind to. All types are `public`, `Sendable`, `Equatable`. All fetches are plain `async throws`, as the existing methods are. Errors are the 2.1 `InnerTubeError` (`.unauthorized` on 401, `.network`, `.httpStatus`, `.unexpectedResponse` when the root container is missing). Cancellation propagates as `CancellationError`.

**Auth**
- `struct Credentials: Sendable { cookies: [HTTPCookie]; authUserIndex: Int }`. Checked during planning: this type-checks under `-swift-version 6`, because `HTTPCookie` is Sendable in the SDK.
- `nil` = guest (visitor-tracked). Signed-in requests are SAPISIDHASH-signed as in 1.2.

**Fetches on `InnerTubeClient`**
- `home(params: String? = nil, credentials: Credentials?) -> BrowsePage`
  - `params` is a Home chip's `target.params`.
- `browse(_ target: BrowseTarget, credentials: Credentials?) -> BrowsePage`
  - Covers Explore (`.explore`), New releases (`.newReleases`), Moods & genres (`.moodsAndGenres`), a mood category / tile / chip target, and any `Shelf.more`.
  - Static targets: `BrowseTarget.home`, `.explore`, `.newReleases`, `.moodsAndGenres`, `.charts`.
- `browseContinuation(_ token: String, credentials: Credentials?) -> Page<Shelf>`
  - The next Home (or any section-list) page.
- `charts(country: String? = nil, credentials: Credentials?) -> ChartsPage`
  - `country` is a `ChartCountry.code`. `nil` means the server default (IP-based).
- `search(_ query: String, params: String? = nil, credentials: Credentials?) -> SearchResults`
- `searchContinuation(_ token: String, credentials: Credentials?) -> Page<MusicItem>`
  - Filtered results only.
- `searchSuggestions(_ input: String, credentials: Credentials?) -> SearchSuggestions`

**Models (fields)**
- `BrowseTarget { browseId: String; params: String? }`
- `ItemRef { name: String; browseId: String? }`: an artist (`UC…`) or album (`MPREb…`) link inside a subtitle.
- `Song { videoId: String; playlistId: String?; title: String; subtitle: String?; artists: [ItemRef]; album: ItemRef?; duration: String?; thumbnailURL: URL?; isExplicit: Bool; isVideo: Bool; rank: ChartRank? }`
- `Album { browseId: String; title: String; subtitle: String?; artists: [ItemRef]; thumbnailURL: URL?; isExplicit: Bool }`
- `Artist { browseId: String; name: String; subtitle: String?; thumbnailURL: URL?; rank: ChartRank? }`
- `Playlist { browseId: String; title: String; subtitle: String?; thumbnailURL: URL? }`
  - `browseId` is `VL…` (or `RD…` for radio cards).
- `NavigationLink { title: String; target: BrowseTarget }`: Explore tiles, mood and genre buttons.
- `ChartRank { position: Int; trend: Trend? }`, `enum Trend { up, down, neutral }`
- `enum MusicItem { song(Song), album(Album), artist(Artist), playlist(Playlist), link(NavigationLink) }`
- `Shelf { title: String?; strapline: String?; more: BrowseTarget?; layout: Layout; items: [MusicItem] }`
  - `enum Layout { cards, rows, grid, list }`:
    - `cards`: a carousel of two-row items;
    - `rows`: a carousel of list rows (Quick picks, Trending, charts);
    - `grid`: `gridRenderer`;
    - `list`: `musicShelfRenderer`.
- `Chip { title: String; target: BrowseTarget?; searchParams: String?; isSelected: Bool }`
  - A Home chip uses `target`. A search filter chip uses `searchParams`.
- `BrowsePage { title: String?; chips: [Chip]; shelves: Page<Shelf> }`
- `ChartCountry { code: String; name: String }`
- `ChartsPage { page: BrowsePage; countries: [ChartCountry]; selectedCountry: String? }`
- `SearchCorrection { correctedQuery: String; originalQuery: String; originalParams: String? }`
  - "Showing results for X, search instead for Y". `originalParams` forces the original query.
- `SearchResults { chips: [Chip]; topResult: MusicItem?; items: Page<MusicItem>; correction: SearchCorrection? }`
  - Unfiltered: a flat list in server order, with `continuation == nil`.
  - Filtered: one type, paged.
- `SearchHistoryEntry { query: String; feedbackToken: String }`
- `SearchSuggestions { queries: [String]; items: [MusicItem]; history: [SearchHistoryEntry] }`

**Behavioural contract**
- Item and section order is the server order.
- Unknown and unsupported blocks (podcasts, episodes, profiles, tastebuilder, the chart podcast shelf) are absent. They are never surfaced as placeholders.
- A guest continuation works only while the guest visitor is unchanged. After `resetGuestVisitor()`, restart from page 1.

## 8. Implementation order

1. **K1** `text()` + test. **K3** body type + `isValidJSONObject` guard. Run `swift test`; still 87+ tests green.
2. Models (`MusicItem.swift`, `Shelf.swift`, `SearchResults.swift`).
3. `ItemParser` + `ItemParserTests` (inline JSON). **TDD:** write the tests first (superpowers:test-driven-development).
4. Capture → scrub → trim fixtures. Add `Package.swift` resources, the README and the `Fixture` helper. Write `FixturePrivacyTests` **before** committing any fixture.
5. `BrowseParser` + tests, then `ChartsParser`, `SearchParser`, `SuggestionsParser`, each with its tests.
6. Client: `Credentials`, `fetch`, the public methods. Move `Script` to Support. Add `DiscoveryClientTests`, including the live smoke test.
7. Docs: the RE §4.9 and ARCH line 338 updates.
8. Verify:
   - `swift build` and `swift test` in `Packages/InnerTube`;
   - `INNERTUBE_LIVE=1 swift test --filter DiscoveryClientTests` once, manually;
   - `xcodebuild -project Redwave.xcodeproj -scheme Redwave -destination 'platform=macOS' -quiet build`, because the app links the package and the K3 signature change must not break it.

## 9. API mismatches against the BA spec (each is a BLOCKER for the gate to accept)

**AC amendments proposed for gate sign-off**
- **Story 3 AC1** becomes: "Given the unfiltered search fixture, When it is parsed, Then the filter chips (title + params), the top result and a flat, server-ordered list of items are returned, and every item has a type and a target or video ID." The per-type sections and "Show all" targets no longer exist live (mismatch 1).
- **Story 3 AC4** ("no results") is tested on a synthetic fixture (mismatch 6).
- **Story 2 AC1**: Explore tiles are `NavigationLink`s, and the Explore shelves are whatever the live page holds. The probe saw New albums & singles, Moods & genres, Trending and New music videos; there was no "top songs" shelf. The parser is not bound to shelf titles.

**Mismatches**

1. Unfiltered search has **no per-type sections or "Show all" targets**. It is a top card + a flat list. `SearchResults` exposes `items: Page<MusicItem>` and has no `sections`. If 4.3 wants grouping, it groups by `MusicItem` case on the client side.
2. The guest continuation needs the **same visitor header**. The body `continuation` form is confirmed. Page-2 roots are `continuationContents.sectionListContinuation` (Home) and `.musicShelfContinuation` (filtered search). `onResponseReceivedActions` was not seen.
3. The Charts country defaults to the **caller IP**, not `gl`. Country codes exist only in `frameworkUpdates` mutations (`opaqueToken`).
4. `moreContentButton` can be a "Play all" `watchEndpoint`. That is not a More target; it is ignored.
5. Explore tiles and mood buttons are `musicNavigationButtonRenderer`, and their targets are full `browseId` + `params` (`FEmusic_moods_and_genres_category`), not params alone. They are modelled as `NavigationLink`. The BA's `MoodChip{label, params}` is kept only for Home chips (`Chip.target`).
6. The "no results" search could not be reproduced live (Google returns fuzzy results). Its fixture is synthetic.

## 10. Risks and edge cases

- **Format drift.** The fixtures are a 2026-11-19 snapshot. The scrub script and README make recapture repeatable, and a failing test after recapture means a format change.
- **The synthetic signed-in shapes may be wrong.** History `feedbackToken` path and Listen again header are not observed. They are marked synthetic, checked against ytmusicapi, and are expected to be replaced by user captures. The guard test covers those captures.
- **Privacy leak in the git history.** Mitigations:
  - the guard test is written before the first fixture;
  - `visitorData` and `responseContext` are deleted rather than placeholdered;
  - Charts is captured with explicit US;
  - the raw-visitor grep runs before commit.
- **Parallel tests and `GuestVisitor.shared`.** End-to-end tests through `postGuest` run with fixtures that have no `visitorData`. `.serialized` orders tests only within its own suite, so `DiscoveryClientTests` never asserts that `X-Goog-Visitor-Id` is absent or present: `ClientTransportTests` changes the shared visitor at the same time. Any test that needs a visitor goes into the existing `.serialized` suite.
- **Item misclassification from menu endpoints.** The parser reads only the item's own endpoint paths (§2.9), and a test has a menu holding an artist endpoint on a song row.
- **The K3 body type is non-Sendable `Any` at serialization.** It is guarded by `isValidJSONObject`. The values stay `any Sendable` across the actor boundary.
- **The More target is a playlist (`VL…`).** `browse()` on it returns the playlist page shape (2.3), which `BrowseParser` will not recognise (`unexpectedResponse`, or empty). 4.x routes `VL…` targets to the playlist screen (2.3). This is documented in the contract.
- **The app build.** No app call site uses the changed `body` parameter: `post` / `postGuest` are internal. The app build is still part of verification.

## 11. Skills to invoke during implementation

`swift-foundation:swift-conventions`, `swift-foundation:swift-testing`, `swift-foundation:swift-tooling` (package resources), `apple-plugin:apple-testing`, `superpowers:test-driven-development`, `superpowers:verification-before-completion`.

The UI and platform skills (`swiftui-*`, `macos-app`) do not apply: there is no UI or app change. Context7 (`ytmusicapi`) is used only to check the synthetic history-suggestion shape.
