# Business Analysis: InnerTube models and parsers for home, explore, search and suggestions (backlog 2.2, issue #9)

## Sources

| Tag | Source | Notes |
|---|---|---|
| [ISSUE] | GitHub issue #9 | **Not fetched.** WebFetch returned 404 (private repo), and Bash/`gh` was not available in this phase. The only verified part of the issue comes from the orchestrator: fixtures are captured from **real guest and signed-in responses with personal data stripped**. Everything else below comes from the docs the brief lists. |
| [BL] | `docs/06-backlog.md` row 2.2 (line 42) | "Models; home, explore, search, suggestions parsers; fixtures without personal data; tests". Depends on 2.1 (merged, PR #53). |
| [RM] | `docs/03-roadmap.md` Stage 2 (lines 48–65) | Typed requests (51–52), parsers (55–57), models `Song`, `Album`, `Artist`, `Playlist`, `Shelf`, `SearchResults` (58), "save real responses and strip personal data" (59), a unit test for every parser (60). "Done when" also requires fetching a playlist, which is 2.3. |
| [ARCH] | `docs/02-architecture.md` | §5.2 endpoints: `browse FEmusic_home` / `FEmusic_explore`, `search`, `music/get_search_suggestions`. §5.3: parsers walk `JSONValue`, one file per page type, and skip unknown blocks. §11: parser tests run on fixtures with no personal data. §12: fixtures live at `Packages/InnerTube/Fixtures`. |
| [PRD] | `docs/00-prd.md` | F-BRW-1 (home: chips + shelves, paged; rows 2.2 and 4.2). F-BRW-2 (Explore: row **4.2 only**). F-SRC-1 (suggestions; 2.2 and 4.3). F-SRC-2 (filtered results; row 4.3). 7.2: unknown blocks are skipped. 7.3: no cookies in fixtures. |
| [UI] | `docs/08-ui-spec.md` | §3.1 suggestions and history (`feedbackToken`). §3.2 results page: filter chips, top result, sections, "did you mean", paging. §5 Home: chips, shelves, More, continuation. §6 Explore: tiles, shelves, subpages. §1.3 routes: `more(browseId, params)`, `explore.mood(params)`. |
| [RISK] | `docs/05-risks-and-scope.md` | Risk 2: the format changes, so parsers must be tolerant and fixture-tested. Line 39: cookie values never reach fixtures or test output. |
| [P21] | `docs/plans/issue-8/*` | 2.1 delivered `Page<T>`, the continuation helper, the skip-unknown rule, retry, and a transport seam. Open item: the continuation request/response format is still unverified against live traffic. |
| [CODE] | Current codebase | See "Codebase impact". |

The root has no `CLAUDE.md` or `README.md`. Conventions are inferred from the code and earlier plan folders.
`mattpocock-skills:grill-me` was skipped because the `mattpocock-skills_unavailable` flag is set. Stakeholder questions are listed at the end instead.

## Executive summary

Backlog 2.2 adds the first content layer on top of the 2.1 InnerTube core:
- typed models: song, album, artist, playlist, video, shelf, mood chip, search results, suggestions;
- tolerant parsers for Home, Explore, Search and search suggestions;
- public client entry points that fetch them for guests and signed-in users;
- fixture-based tests on real responses with personal data stripped.

The Home, Search and Search-suggestions screens (4.2 and 4.3) are built on this data layer, so the models must carry everything those screens need: the More target, navigation targets, playable IDs, chip params, `feedbackToken`, and corrections.

## Functional requirements

1. **FR-1 Models** [RM:58][ARCH §5.3][UI §3, §5, §6].
   - Sendable, Equatable value models for the item kinds that appear on Home, Explore and Search: song, video, album, artist, playlist.
   - A **shelf** with a title, optional strapline, optional "More" target (`browseId` + `params`) and items.
   - A **mood/genre chip** with a label and `params`.
   - **Search results**, **search suggestions** and **Explore**.
   - Every item carries what the UI needs to act on it: a title, subtitle parts, thumbnails, and a navigation target (album `MPREb…` / artist `UC…` / playlist `VL…`) or a playable ID (`videoId`, optionally `playlistId`). The models do not depend on the app or UI layers.
2. **FR-2 Home parser** [BL][UI §5][PRD F-BRW-1].
   - Parses `browse FEmusic_home` into the mood chips (in response order) and a `Page<Shelf>` whose continuation follows 2.1 paging.
   - Also parses a Home **continuation response** (the next batch of shelves). Its container differs from the first page; see G2.
   - Fetching Home with a chip's `params` uses the same parser.
3. **FR-3 Explore parser** [BL][UI §6][ARCH §5.2].
   - Parses `browse FEmusic_explore` into the navigation tiles (New releases, Charts, Moods & genres, each with a browse target) and its shelves.
   - Explore **subpages** (`FEmusic_new_releases`, `FEmusic_charts`, `FEmusic_moods_and_genres`, `…_category`) are **not settled**; see C1 and open question 1.
4. **FR-4 Search parser** [BL][UI §3.2].
   - Parses `search` with `query` and optional filter `params` into:
     - the filter chips the response offers (label + `params`);
     - with no filter: the top-result card and the per-type sections, each with its "Show all" target;
     - with a filter: a single `Page` of items of that type, including continuation pages;
     - the "did you mean / showing results for" correction, when present.
   - Unsupported result types (podcast, episode, profile) are skipped under the 2.1 rule until the PRD podcast question is settled (C4).
5. **FR-5 Suggestions parser** [BL][UI §3.1][PRD F-SRC-1].
   - Parses `music/get_search_suggestions` into text suggestions and entity suggestions (artist, album, song, with thumbnails and targets), in response order.
   - When the response holds history entries (signed in, empty input), each entry is parsed with its `feedbackToken` kept, so 2.4 can delete it without re-parsing.
   - An empty or unknown response gives an empty result, not an error (UI §3.1: suggestions are optional).
6. **FR-6 Client entry points** [RM:51–52][ARCH §5.3].
   - The InnerTube client exposes fetches for Home (optionally with chip params), Explore, Search (query + optional filter params), Suggestions (input), and the next page of Home and filtered Search. Each works in **both** modes: guest (`postGuest`) and signed in (`post` with cookies + `authUserIndex`).
   - The 2.1 retry, 401 and visitor rules apply unchanged.
   - The shape of the API is left to dev.
7. **FR-7 Fixtures and tests** [ISSUE][RM:59–60][ARCH §11][PRD 7.3].
   - Each parser has Swift Testing tests on fixtures captured from real responses (guest and signed-in, per the issue) with personal data stripped.
   - At least one test per parser drives fixture bytes end to end through the client's transport seam.
   - An automated check fails the build if any fixture contains secrets or personal data. Feasibility constraints are in G1.

## Non-functional requirements

- **Resilience** [PRD 7.2][RISK 2]:
  - An unknown or malformed shelf, card or chip is dropped through the existing `parseBlocks`, and its renderer key is logged. A page never fails as a whole.
  - A page fails (`unexpectedResponse`) only when its top-level container is missing.
  - Missing optional fields (subtitle, thumbnail, More target) give `nil`, never a dropped item. An item is dropped only when its identity or title is missing.
- **Locale independence:** parsers key on structure, renderer names and IDs, never on localized text such as shelf titles or chip labels. Requests already send `hl`/`gl` from `Locale.current`.
- **Security / privacy** [PRD 7.3][RISK]:
  - Fixtures, logs and test output contain no cookies, SAPISID, SAPISIDHASH, `visitorData`, account name, email, avatar URL, or the user's own channel ID.
  - The logger records only renderer keys, as in 2.1.
  - Thumbnail URLs pass through the existing host allowlist (`lastThumbnailURL`: https on `ytimg.com`, `googleusercontent.com`, `ggpht.com`).
- **Performance:** parsing a full Home response is cheap enough not to dominate the ≤ 2 s cold-start budget [PRD 7.1]. No measurement is required in 2.2. It is enough that parsing makes one pass with no repeated JSON decoding.
- **Testability:** all parser tests run offline. Fixture sizes are kept reasonable (trimmed to a few representative shelves) so the repo does not take on megabytes of JSON.

## User stories (Gherkin)

### Story 1: Home loads as typed shelves for guests and signed-in users
**As a** developer of the Home screen (4.2)
**I want** a typed Home result with mood chips and paged shelves
**So that** the screen renders without touching raw JSON

**Acceptance criteria:**
- Given the guest Home fixture, When it is parsed, Then the chips come back in response order, each with a non-empty `params`, and at least one shelf has a title, items with titles and navigation targets or video IDs, and an optional More target.
- Given the signed-in Home fixture, When it is parsed, Then the personalised shelves (for example Listen again) are returned with their strapline and do not break parsing.
- Given a Home fixture with one shelf replaced by an unknown renderer, When it is parsed, Then every other shelf is returned in order and the unknown key is logged.
- Given a Home first page with a continuation, When the next page is fetched and parsed, Then it yields more shelves and its own continuation, or `nil` on the last page.
- Given the client fetches Home as a guest, When the request is built, Then it carries `browseId=FEmusic_home` and no `Cookie`, `Authorization` or `X-Goog-AuthUser`. Signed in, it is signed as in 1.2.

### Story 2: Explore landing data
**As a** developer of the Explore screen (4.2)
**I want** Explore tiles and shelves as typed data
**So that** the landing page and its links to subpages can be built

**Acceptance criteria:**
- Given the Explore fixture, When it is parsed, Then the three tiles are returned with their browse targets, and the shelves (new albums & singles, top songs, moods & genres, trending, music videos) are returned with their items.
- *(Only if open question 1 puts subpages in 2.2)* Given each subpage fixture, When it is parsed, Then the New releases grid, the Charts lists with rank and trend, the Moods & genres sections of chips, and a mood category's playlist shelves are returned.

### Story 3: Search results with filters
**As a** listener (through 4.3)
**I want** search results grouped by type, with filters and paging
**So that** I can find a song, album, artist or playlist

**Acceptance criteria:**
- Given the unfiltered search fixture, When it is parsed, Then the filter chips (label + params), the top result and the per-type sections are returned, and every item has a type and a target or video ID.
- Given a filtered (songs) search fixture, When it is parsed, Then a `Page` of songs is returned with a continuation, and the continuation-page fixture parses into more songs.
- Given a fixture with a spelling correction, When it is parsed, Then the corrected query and the original query are exposed.
- Given a search with no results, When it is parsed, Then the result is empty and no error is thrown.
- Given a result section of an unsupported type (podcast, episode or profile), When it is parsed, Then it is skipped and logged and the others remain.

### Story 4: Search suggestions while typing
**As a** listener typing in the search field
**I want** text and entity suggestions, and my history when signed in
**So that** I can reach what I want in fewer keystrokes

**Acceptance criteria:**
- Given the guest suggestions fixture for a partial query, When it is parsed, Then text suggestions come first and entity suggestions (with type, title, thumbnail and target) follow, in response order.
- Given the signed-in empty-input fixture, When it is parsed, Then the history entries are returned, each with a non-empty `feedbackToken`.
- Given an empty or unrecognised suggestions response, When it is parsed, Then an empty result is returned with no error.

### Story 5: Fixtures are safe to commit
**As a** maintainer
**I want** a test that guards every committed fixture
**So that** no session or personal data ever lands in the repository

**Acceptance criteria:**
- Given all fixture files, When the guard test runs, Then none contains `SAPISID`, `__Secure-`, `SID=`, `Authorization`, an email-address pattern, or a non-placeholder `visitorData`/`VISITOR_DATA` value.
- Given the signed-in fixtures, When the guard test runs, Then the account name, the handle and the user's own channel ID that were captured are absent (replaced by documented placeholders).

## Data model sketch

Prose only; the exact Swift shapes are left to dev.

- **Thumbnail / artwork:** a URL plus optional width and height, filtered through the existing allowlist.
- **NavigationTarget:** a `browseId` plus optional `params`, and a page kind (album, artist, playlist, mood, more, unknown). It feeds the routes in UI §1.3.
- **Song / Video:** `videoId`, title, artists (name + optional channel ID), optional album (name + browse ID), optional duration text, thumbnails, and an explicit flag where present.
- **Album:** browse ID (`MPREb…`), optional audio playlist ID, title, artists, year or type text, thumbnails.
- **Artist:** channel ID (`UC…`), name, thumbnails, optional subscriber text.
- **Playlist:** playlist ID / browse ID (`VL…`), title, author text, thumbnails.
- **MusicItem:** a sum of the five kinds above. Shelves and search sections hold mixed kinds.
- **Shelf:** title, optional strapline, optional More target, items (`[MusicItem]`), and a presentation hint (cards / list rows such as Quick picks), because 4.2 renders them differently.
- **MoodChip:** label plus `params`. Used for Home chips and Explore moods.
- **HomeFeed:** chips plus `Page<Shelf>`.
- **ExploreFeed:** tiles (title + NavigationTarget) plus shelves.
- **SearchResults:**
  - filter chips (label + `params`);
  - optional top result (`MusicItem`);
  - sections (title + items + optional "Show all" filter `params`);
  - optional correction (corrected query, original query);
  - a filtered variant that is a `Page<MusicItem>`.
- **SearchSuggestions:** text suggestions (plain string, kept with its highlight runs if needed); entity suggestions (`MusicItem`); history entries (text + `feedbackToken`).
- **Relationships:**
  - `Page<T>` (existing) wraps shelves and filtered search items.
  - Items reference artists and albums by ID only. There is no object graph.

## API contract sketch

**Outbound (Google), all `POST https://music.youtube.com/youtubei/v1/<endpoint>?prettyPrint=false` with `context.client` from 2.1:**

| Endpoint | Body fields | Response root (to verify with captures) |
|---|---|---|
| `browse` | `browseId: FEmusic_home` (+ `params` for a chip) | `contents.singleColumnBrowseResultsRenderer.tabs[0]…sectionListRenderer` (chips in `header.chipCloudRenderer`) **[known, unverified]** |
| `browse` | `browseId: FEmusic_explore` | as above |
| `browse` | `continuation: <token>` (the form 2.1 sends) | `continuationContents.sectionListContinuation` or `onResponseReceivedActions[].appendContinuationItemsAction.continuationItems` **[unverified]** |
| `search` | `query`, optional `params` | `contents.tabbedSearchResultsRenderer…sectionListRenderer` (`musicCardShelfRenderer` top result, `musicShelfRenderer` sections, `itemSectionRenderer` correction) **[known, unverified]** |
| `search` | `continuation: <token>` | `continuationContents.musicShelfContinuation` **[unverified]** |
| `music/get_search_suggestions` | `input` | `contents[].searchSuggestionsSectionRenderer.contents[]` → `searchSuggestionRenderer` / `musicResponsiveListItemRenderer` / `historySuggestionRenderer` **[known, unverified]** |

Charts (`FEmusic_charts` with nested `formData.selectedValues`) applies only if the subpages are in scope (C1), and it does not fit the current body type (K3).

**Swift public surface (prose only):**
- Fetches for home, explore, search, suggestions and next page.
- Each comes in a guest form and a signed-in (cookies + index) form, mirroring `connectAsGuest` / `accountMenu`.
- Each returns the models above and throws the 2.1 `InnerTubeError`.

## Codebase impact

| File / area | Impact |
|---|---|
| `Packages/InnerTube/Sources/InnerTube/` (new files) | Models, plus one parser file per page type (home, explore, search, suggestions), as ARCH §5.3 requires. |
| `InnerTubeClient.swift` | New public fetch methods built on the existing `post` / `postGuest`. No change to transport, retry or error handling. |
| `InnerTubeRequest.swift` | No change, unless C1 brings in Charts (nested `formData`) and `attachPayload` must accept non-string values (K3). |
| `AccountInfo.swift` (`text`, `lastThumbnailURL`) | Reused. `text` probably needs a sibling that reads all runs (K1). Both are internal; they may move to a shared helpers file. |
| `Page.swift`, `Blocks.swift` | Reused as is. `nextContinuation` may need to handle continuation-response containers (K2). |
| `Packages/InnerTube/Package.swift` | The test target gains fixture resources (K4). |
| `Packages/InnerTube/Tests/InnerTubeTests/` | One test file per parser, the fixture privacy guard, and end-to-end tests through the `Script` transport-stub pattern from `ClientTransportTests`. |
| Fixture folder (new) | Real JSON captures, trimmed and scrubbed, plus a short README on how each was captured and what was replaced. |
| `docs/01-reverse-engineering.md` | Record the confirmed continuation request/response form (carry-over of issue-8 G1). |
| `App/*` | **No changes.** The screens are 4.2 and 4.3. |

### Codebase constraints

- **K1. `text()` reads only `runs[0]`.** Card subtitles are multi-run ("Song • Artist • Album"), and individual runs carry `navigationEndpoint`s for the artist and album links. The parsers need every run, and the per-run endpoints for artist and album references.
- **K2. Continuation responses have a different root.** `nextContinuation` reads a token from a first-page container (`continuations[]` or a trailing `continuationItemRenderer`). Page 2 arrives under `continuationContents…` or `onResponseReceivedActions…`, and no code extracts items or the next token from those. Home paging and filtered-search paging need this.
- **K3. `body: [String: String]`.** This is enough for `browseId`, `params`, `query`, `input` and `continuation`. It is **not** enough for Charts `formData`, which is nested. That matters only if C1 brings in the subpages.
- **K4. Fixture location conflict.**
  - ARCH §12 puts fixtures at `Packages/InnerTube/Fixtures`, next to `Tests`.
  - SwiftPM resources must sit under a target's path, and `Package.swift` declares no `resources` today.
  - Options: `Tests/InnerTubeTests/Fixtures` (then update ARCH §12), or a custom target `path`.
  - ARCH §11 "SwiftUI previews on fixtures" (4.x) would need the fixtures available outside the test target. That is out of scope here, but the location chosen now should not block it.
- **K5. Two auth paths.** The client splits `post` (signed) and `postGuest` (visitor-tracked). Every new fetch needs both modes [PRD F-AUTH-1].
- **K6. `JSONValue` and parser types are internal.** The public surface exposes only models. Tests use `@testable import`, as they do today.
- **K7. Logging.** Reuse `parserLog` / `blockKey`. Do not add new loggers or log values.

## Conflicts and gaps

- **C1. Who parses the Explore subpages?**
  - UI §6: "Stage: 2.2, 4.2. Subpages are part of 4.2."
  - PRD F-BRW-2: Explore belongs to row 4.2 only.
  - Backlog 2.2 just says "explore".
  - 4.2 depends on 2.2 for data, so if subpage parsing is not done in 2.2, 4.2 has to do it.
  - **Recommendation:** 2.2 parses the Explore landing only; the subpage parsers go to 4.2 (or a 2.2b), together with the K3 body change for Charts. This needs confirmation.
- **C2. Roadmap "Done when" covers more than 2.2.** It requires fetching a playlist, which is 2.3. The 2.2 AC cover home, explore and search only.
- **C3. Search filters.**
  - PRD F-SRC-2 assigns filtered results to row 4.3 only.
  - UI §3.2 says "Stage 2.2, 4.3".
  - **Recommendation:** 2.2 parses filter chips, filtered results and their continuation, because 4.3 has no parser scope.
- **C4. Podcasts, episodes and profiles** appear as search filters and result types (UI §3.2), but podcasts are P2 and depend on the PRD open question (F-BRW-5).
  - **Recommendation:** skip them under the 2.1 rule and log them; add no models.
- **G1. Fixture feasibility, real guest versus signed-in captures** (the orchestrator asked for this).
  - **Guest:** feasible in the automated pipeline. The dev agent can capture live through the same unauthenticated request shape the client uses. Use a fixed `hl=en`, `gl=US` for reproducibility.
    - "Stripped" still applies to guest captures: `responseContext.visitorData`, `serviceTrackingParams`, `trackingParams` / `clickTrackingParams` and similar opaque tracking blobs are replaced with placeholders.
    - Captures are trimmed to a few representative shelves or items.
  - **Signed-in:** **not feasible without the user.**
    - The agent must not read the Keychain or WebKit cookie store, or reuse the session (PRD 7.3, RISK line 39).
    - A signed-in Home response is personal by its very content: Listen again, history, library, and "Because you listened to…". Removing the name, avatar and channel ID still leaves the listening profile.
  - **Recommended handling:**
    1. Ship real scrubbed **guest** fixtures for every parser in 2.2.
    2. For the shapes that only signed-in responses have (Listen-again strapline with avatar, history suggestions with `feedbackToken`), add minimal **hand-built JSON** marked as synthetic. Model it on public descriptions of the shape, and replace it later.
    3. Real signed-in captures are a **user-supplied follow-up**: the user captures them (for example from the browser devtools Network tab), scrubs them with a documented checklist, and replaces the synthetic files. The privacy guard test (Story 5) runs on them.
  - This approach deviates from the literal issue text, so the stakeholder must accept it (open question 2).
- **G2. The continuation format is still unverified** (2.1 PR open item). The live guest captures in 2.2 are the first chance to confirm, for Home and Search:
  - the request form (body `continuation` vs query `ctoken`/`continuation`/`type`);
  - the response root.
  Record the result in `docs/01-reverse-engineering.md`. If the body form 2.1 sends is rejected, the request builder changes too.
- **G3. Shelf presentation kinds are not enumerated anywhere.** Quick picks (list rows in columns) versus carousels. The model needs a hint, but the set of kinds is learned from the captures.
- **G4. Issue text not verified.** Issue #9 could not be read. If it has AC beyond the backlog row, they are not reflected here. The dev phase should read it with `gh issue view 9`.

## Edge cases & error scenarios

- **Empty or minimal pages.** A Home or Explore response with zero shelves (new guest, region with little content) parses to an empty page, not an error. Search with no results gives an empty `SearchResults`.
- **Missing top-level container.** This includes a captcha or consent HTML returned as 200, or an `alerts`-only response. The result is `unexpectedResponse`, and only that page fails.
- **Malformed blocks.**
  - A shelf whose items all fail to parse: drop the shelf, or keep it empty? Recommend dropping it, so no empty headers show.
  - A card without a navigation target or `videoId`: drop it. An action without an ID is unusable.
- **Mixed item kinds.**
  - A shelf can hold mixed kinds (songs and videos in Quick picks, albums and playlists in "Mixed for you").
  - A video-type song (`MUSIC_VIDEO_TYPE_UGC/OMV/ATV`): keep the type so 4.x can show it as a video or a song.
- **Locale.**
  - Localized titles in non-English locales must not change parse results.
  - RTL text and emoji in titles are preserved verbatim.
- **Continuations.** A continuation token that repeats or comes back empty means no more pages (the existing helper already treats an empty token as `nil`). Home continuation responses may contain chip-less shelves only.
- **Suggestions.**
  - Highlighted-run text (bold typed prefix) is concatenated into a plain string.
  - Fast typing cancels requests, which the 2.1 cancellation rules already handle.
  - An empty input sent as a guest returns no history. That is not an error.
- **Signed-in versus guest.** Personalised shelves are absent for guests (UI §5). Account-only fields such as library status are optional in the models.
- **Thumbnails.**
  - URLs outside the host allowlist become `nil`.
  - Protocol-relative (`//lh3…`) and `http` URLs are rejected by the current rule. Check whether real captures contain them. If they do, the policy needs a decision; do not loosen it silently.
- **Fixture drift.** Google will change shapes, so fixtures are a snapshot. When a test fails after a recapture, that should be read as a format change, not a flaky test.

## Risks & dependencies

- Depends on 2.1 (merged): `Page`, `parseBlocks`, retry, transport seam, client version.
- Blocks 2.3 (it reuses the item models and run-parsing helpers), 4.2 (Home/Explore UI) and 4.3 (Search UI).
- Model design is the main long-term risk: 2.3, 2.4 and the whole 4.x UI will bind to these types. Missing fields (More target, `feedbackToken`, video type) are cheap to add now and costly later.
- Fixture privacy: a single careless capture can leak listening history or identifiers into git history permanently. The guard test plus the synthetic signed-in approach (G1) contain this risk.
- Wire shapes are `[known]` from open projects but not verified for the current WEB_REMIX version. The captures may disagree, and the parsers must follow the captures.

## Open questions for stakeholders

1. **(Blocking for scope, C1)** Are the Explore subpage parsers (New releases, Charts with country `formData`, Moods & genres, mood category) part of 2.2, or of 4.2? Recommendation: landing only in 2.2.
2. **(Blocking for fixtures, G1)** Do you accept real scrubbed **guest** fixtures plus minimal **synthetic** signed-in fixtures for 2.2, with real signed-in captures supplied by you later? The alternative is that you provide scrubbed signed-in captures before the dev phase.
3. **(C3/C4)** Confirm that 2.2 parses filtered search results and their paging (not 4.3), and that podcast, episode and profile results are skipped until the podcast question is settled.

## Estimated complexity

**Medium** if the Explore subpages stay out (recommended): about a dozen models, four parser files, client fetch methods, fixtures and a guard test, all in one package, with no app or UI changes.
**Large** if the subpages come in. That adds four more parsers and fixtures, plus the request body change for Charts `formData`.
