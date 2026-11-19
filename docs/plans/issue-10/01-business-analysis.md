# Business Analysis: InnerTube parsers for album, artist, playlist, library, history and up next (backlog 2.3, issue #10)

## Sources

| Tag | Source | Notes |
|---|---|---|
| [ISSUE] | GitHub issue #10, reproduced in `docs/plans/issue-10/_brief.md` | Scope checklist (9 items), "Done when" (3 items), the podcast note, dependencies (blocked by #9, blocks #16, #19, #22) |
| [BL] | `docs/06-backlog.md` row 2.3 (line 43) | "Album, artist, playlist, library, history, `next` (up next) parsers; tests". Depends on 2.2 |
| [PRD] | `docs/00-prd.md` §5 | F-BRW-3 (album, artist with Subscribe, playlist pages; long playlists paged; rows 2.3, 4.4). F-LIB-1 (library sections; 2.3, 4.5). F-LIB-2 (sidebar playlists; **4.1, 4.5**). F-LIB-4 (history with removal; **2.4, 4.5**). F-PLY-4 (Up next; **3.2, 4.6**). F-PLY-5 (player page, Lyrics/Related; **4.8**) |
| [ARCH] | `docs/02-architecture.md` | §4.4: the queue belongs to the web page; Swift reads it through the bridge and keeps no copy that acts as the source of truth. §5.2: `browse` ids, `next` = queue, radio, related, lyrics id. §5.3: one parser file per page type; unknown blocks are skipped |
| [UI] | `docs/08-ui-spec.md` | §4.3 sidebar list (`guide`, fallback `FEmusic_liked_playlists`, "Liked music" pinned). §7 Library (sections, sort, paging, History by day, `VLLM`). §8.1–8.3 playlist, album and artist pages. §10.1–10.5 player page (counterpart id, Up next, chips, Playing from, Lyrics, Related) |
| [RE] | `docs/01-reverse-engineering.md` §4 (lines 252–269) | Wire shapes confirmed in 2.2: roots, continuation body and visitor rule, item-kind rule, thumbnail hosts |
| [P22] | `docs/plans/issue-9/*`, PR #54 | Models, `ItemParser`, `BrowsePage`, fixture README, scrubber and privacy guard. Synthetic signed-in fixtures were accepted as a precedent. Security lows L1–L3 are still open |
| [CODE] | `Packages/InnerTube/` | See "Codebase impact" |

There is no root `CLAUDE.md` or `README.md`. Conventions are inferred from the code and earlier plan folders. `grill-me` was skipped (`mattpocock-skills_unavailable`), and stakeholder questions are listed at the end.

## Executive summary

Backlog 2.3 adds the read side of the entity pages, the library and the player page to the InnerTube package:
- typed parsers and client fetches for album, artist, playlist (with paging and a typed "not available" result), the five library sections plus Liked music, the sidebar playlist list, history (grouped by day, with removal tokens), `next` (Up next metadata and queue), and the Lyrics and Related pages;
- fixtures with no personal data, and a unit test for every parser.

Screens #16 (4.1 shell and sidebar), #19 (4.4 entity pages) and #22 (4.8 player page tabs) bind to these models. Their shape is therefore the main long-term risk. No `App/` changes.

## Functional requirements

1. **FR-1 Album page** [ISSUE][UI §8.2][PRD F-BRW-3]
   - Parses `browse MPREb…` into:
     - a header: title, type (Album / Single / EP), year, artist link(s), cover, the explicit flag, and the audio playlist id that Play and Shuffle need;
     - the track list in server order, with each track's number;
     - a footer: release date, track count and total duration, label (whichever the response carries);
     - the "Other versions" and "More from <artist>" shelves, as `Shelf`s.
2. **FR-2 Artist page** [ISSUE][UI §8.3][PRD F-BRW-3]
   - Parses `browse UC…` into:
     - a header: name, image, subscriber count text, subscribe state, the channel id that subscribe needs, and the Shuffle and Radio endpoints;
     - "Top songs" with its "Show all" target (the artist's songs playlist);
     - every other shelf (Albums, Singles & EPs, Videos, Featured on, Fans might also like, Playlists) with its "Show all" `browseId` + `params`;
     - About: description and view count.
   - A "Show all" page (`browse` + `params`) parses with the existing grid / section-list parsing.
3. **FR-3 Playlist page** [ISSUE][UI §8.1, §7][PRD F-BRW-3]
   - Parses `browse VL<id>` into:
     - a header: title, owner (+ channel link), "Playlist • year", track count and duration text, description, cover;
     - tracks as a `Page` with a continuation; the continuation fetch returns the next page and the next token, or `nil` on the last page;
     - the own-playlist "Suggestions" shelf, when present.
   - Liked music (`VLLM`) parses with the same parser.
   - A private, deleted or non-existent playlist yields a **typed "not available" outcome**, distinct from `unexpectedResponse`, network and HTTP errors.
4. **FR-4 Library and sidebar list** [ISSUE][UI §7, §4.3][PRD F-LIB-1, F-LIB-2]
   - Parses each of these into a paged list of items:
     - `FEmusic_liked_playlists` (playlists grid);
     - `FEmusic_liked_videos` (songs);
     - `FEmusic_liked_albums` (albums);
     - `FEmusic_library_corpus_track_artists` (artists of liked songs);
     - `FEmusic_library_corpus_artists` (subscriptions).
   - Also exposes, when the response offers them:
     - the sections the response offers (chips with targets);
     - the sort options (label + whatever token or params selects them).
   - The sidebar playlist list comes from the `guide` endpoint: the user's own and saved playlists in site order, each with title, owner and target, and Liked music identified. When `guide` is unusable, the same list comes from `FEmusic_liked_playlists`.
   - Podcasts (`FEmusic_library_non_music_audio_list`) are **out of scope** until docs/05 question 4 / issue #7 is answered. A podcast section or item is skipped and logged.
5. **FR-5 History** [ISSUE][UI §7][PRD F-LIB-4]
   - Parses `browse FEmusic_history` into day groups, keeping the server's group titles ("Today", "Yesterday"…) and order.
   - Each row is a song or video item that carries its **removal feedback token**, so 2.4 / 4.5 can remove it without re-parsing.
   - Removal itself (the `feedback` mutation) belongs to 2.4.
6. **FR-6 `next`, Lyrics and Related** [ISSUE][UI §10][ARCH §5.2][PRD F-PLY-4, F-PLY-5]
   - Parses `next` (for a `videoId` with optional `playlistId` / `params`) into:
     - the Up next queue items: id, title, artists, duration, thumbnail, the current-item marker, and the autoplay split when present;
     - radio chips (label + the endpoint that switches the queue);
     - the "Playing from" source name and target;
     - the lyrics `browseId` and related `browseId` (each absent when the tab is disabled);
     - the audio / video counterpart id (ATV ↔ OMV) when the item has one.
   - Parses the Lyrics page (`browse` with the lyrics id) into plain text plus the source line, or a typed "no lyrics" result.
   - Parses the Related page into `Shelf`s that reuse 2.2 item parsing.
7. **FR-7 Fixtures and tests** [ISSUE][P22][PRD 7.3]
   - Every parser has Swift Testing tests on fixtures documented in `Fixtures/README.md` that pass `FixturePrivacyTests`.
   - At least one end-to-end test per client fetch goes through the transport seam (`ScriptedTransport`).
   - One `INNERTUBE_LIVE=1`-gated test fetches a public playlist longer than one page and follows its continuation.
   - The scrubber keeps the fields this task needs (see K2).

## Non-functional requirements

- **Resilience** [PRD 7.2][ARCH §5.3]:
  - Unknown shelves, rows and header parts are skipped through `parseBlocks` and logged by renderer key. They never fail a page.
  - A page throws only when its top-level container is missing. The exception is FR-3 "not available", which is a typed outcome and not a failure.
  - Optional fields (year, label, subscriber count, description, lyrics source) are `nil` when absent.
- **Locale independence:** parsers key on renderer names, endpoint types and ids, never on localized labels such as "Album", "Show all", "Today" or "Songs". The album type and history day titles are passed through as display text.
- **Privacy** [PRD 7.3][P22 L1–L3]:
  - Library, history, guide and `VLLM` responses are personal by content. Fixtures must not contain the account's name, handle, own channel id, avatar, email, real listening history or real private playlist titles and ids.
  - Logs record renderer keys only.
- **Auth modes** [K5 of 2.2]:
  - Every fetch takes `Credentials?`.
  - Library, history, guide and `VLLM` are account-only. A guest call must still return a defined outcome (typed error or empty), never a crash or a mis-parse.
- **Copyright:** lyric text must not be committed verbatim in fixtures. Keep the structure and the source line, and replace the body with placeholder lines.
- **Performance:** no requirement beyond a single pass per response. Long playlists are fetched page by page and never all at once.

## User stories (Gherkin)

### Story 1: A long playlist pages, and an unavailable one is typed
**As a** developer of the playlist page (4.4)
**I want** a typed playlist header and paged tracks, plus a typed "not available" result
**So that** long playlists load incrementally and broken links show "This playlist isn't available"

**Acceptance criteria:**
- Given the public playlist fixture, When it is parsed, Then the header has a title, owner, count text and cover, the tracks are songs/videos with `videoId`, and the page has a non-nil continuation.
- Given the playlist continuation fixture, When it is parsed, Then it yields more tracks and either a next token or `nil`.
- Given `INNERTUBE_LIVE=1` and a known public playlist with more than one page, When the playlist is fetched as a guest and its continuation is followed once, Then the second page holds tracks that are not on the first.
- Given a private, deleted or non-existent playlist (captured response, whether 200 + alert or 4xx), When it is fetched through the client, Then the caller receives the typed not-available outcome, not `unexpectedResponse`, a parse error or `httpStatus`.
- Given the `VLLM` fixture, When it is parsed, Then it parses with the same parser as any playlist.
- Given an own-playlist fixture with a Suggestions shelf, When it is parsed, Then the shelf is returned separately from the tracks.

### Story 2: Album and artist pages
**As a** developer of the album and artist pages (4.4)
**I want** typed headers, track lists and shelves
**So that** the pages render without touching raw JSON

**Acceptance criteria:**
- Given the album fixture, When it is parsed, Then the header has title, type, year, artist ref(s) and the audio playlist id, the tracks are numbered 1…N in order, the footer exposes its date / count / label text, and "Other versions" and "More from" come back as shelves when present.
- Given the artist fixture, When it is parsed, Then the header has name, subscriber text, a subscribed flag and the channel id, Top songs has items and a Show-all target, every other shelf has a title and, where offered, a `browseId` + `params` target, and About has the description.
- Given a "Show all" fixture fetched with a shelf's `params`, When it is parsed, Then its items are returned.
- Given an album or artist fixture with one shelf replaced by an unknown renderer, When it is parsed, Then the rest is returned and the key is logged.

### Story 3: Library sections and the sidebar list
**As a** signed-in listener (through 4.1 and 4.5)
**I want** my playlists, songs, albums, artists and subscriptions, and my sidebar playlist list
**So that** I can reach my music

**Acceptance criteria:**
- Given each of the five library fixtures, When it is parsed, Then a page of items of the expected kind is returned, with its continuation when present.
- Given a library fixture that offers section chips and a sort menu, When it is parsed, Then the sections and sort options come back with their selection tokens.
- Given the `guide` fixture, When it is parsed, Then the playlist entries come back in order with title, owner and target, and Liked music is identifiable.
- Given a `guide` response without a playlist section, When the sidebar list is requested, Then the `FEmusic_liked_playlists` result is the fallback.
- Given a podcast section or item in a library response, When it is parsed, Then it is skipped and logged.

### Story 4: History with removal tokens
**As a** signed-in listener (through 4.5, with 2.4 doing the removal)
**I want** history grouped by day, with each row removable
**So that** I can see and clean up what I played

**Acceptance criteria:**
- Given the history fixture, When it is parsed, Then the day groups come back in server order with their titles, and every row has a `videoId` and a non-empty removal token (`PLACEHOLDER_FEEDBACK_*` in the fixture).
- Given a raw history capture run through the scrubber, When the output is inspected, Then the per-row removal tokens are still present as placeholders.

### Story 5: Player page data from `next`, Lyrics and Related
**As a** developer of the player page (4.6, 4.8)
**I want** the Up next metadata, queue, chips and tab ids, plus the Lyrics and Related pages
**So that** the player page can show its tabs and the Song/Video toggle

**Acceptance criteria:**
- Given a `next` fixture for a radio queue, When it is parsed, Then the queue items, the current-item marker, the radio chips, the "Playing from" source, the lyrics id and the related id are returned.
- Given a `next` fixture for a song that has a video counterpart, When it is parsed, Then the counterpart id is exposed. For a track without one, the counterpart is `nil`.
- Given a `next` fixture for a track without lyrics, When it is parsed, Then the lyrics id is `nil`.
- Given the lyrics fixture, When it is parsed, Then the text and the source line are returned. Given a no-lyrics response, Then the typed "no lyrics" result is returned.
- Given the related fixture, When it is parsed, Then its shelves come back with items, as Home does.

## Data model sketch

Prose only; the Swift shapes are left to dev. All are `Sendable`, `Equatable` and public.

- **Reused from 2.2:** `Song`, `Album`, `Artist`, `Playlist`, `MusicItem`, `ItemRef`, `Shelf`, `Chip`, `BrowseTarget`, `Page<T>`.
- **Additive changes to existing types (public API, used by #16, #19 and #22):**
  - an album's audio playlist id (`OLAK5uy…`), for Play;
  - a track number on tracks inside an album (or a wrapper that pairs the number with the song);
  - a removal token on a history row (or a wrapper; see the existing `SearchHistoryEntry` precedent).
- **PageHeader:**
  - title, subtitle text, second-subtitle text (counts, duration), description, cover URL;
  - owner / artist `ItemRef`s;
  - play and shuffle / radio endpoints.
  - Shared by album and playlist, or kept as two types; the choice is left to dev.
- **AlbumPage:** header + type text + year + audio playlist id + tracks + footer text + shelves.
- **ArtistPage:**
  - header: name, image, subscriber text, subscribed flag, channel id, shuffle and radio targets;
  - Top songs (items + Show-all target);
  - shelves (`Shelf` with `more` = `browseId` + `params`);
  - About (description, view count text).
- **PlaylistPage:** header + `Page` of tracks + optional suggestions shelf. "Not available" is a separate outcome: a case of a result enum, or a dedicated error. Dev decides, but it must be distinguishable by type.
- **LibraryPage:** offered sections (`Chip`s) + sort options (label + selection token + selected flag) + `Page<MusicItem>`.
- **SidebarPlaylist:** title, owner text, target, and a Liked-music / pinned marker. Thumbnails are optional.
- **HistoryPage:** `[HistoryDay]`, where each day has a title and rows (item + removal token).
- **WatchNext (`next`):**
  - queue items (video id, playlist id, title, artists, duration, thumbnail, isCurrent, counterpart id);
  - an autoplay split;
  - chips (label + endpoint payload);
  - source (name + target);
  - lyrics id and related id (both optional);
  - a continuation for long queues, if present.
- **Lyrics:** text + source line, or "none".
- **Related:** `[Shelf]`.
- **Relationships:** items reference albums, artists and playlists by id only, as in 2.2. There is no object graph.

## API contract sketch

**Outbound** (all `POST https://music.youtube.com/youtubei/v1/<endpoint>?prettyPrint=false`, `context.client` WEB_REMIX). Roots are **[known, unverified]** from open projects and must be confirmed on capture, then recorded in `docs/01-reverse-engineering.md` §4.

| Endpoint | Body | Expected root / notes |
|---|---|---|
| `browse` | `browseId: MPREb…` | two-column layout: header in `tabs[0]…sectionListRenderer.contents[0].musicResponsiveHeaderRenderer`, tracks in `secondaryContents.sectionListRenderer` (`musicShelfRenderer`), then carousels |
| `browse` | `browseId: UC…` | `singleColumnBrowseResultsRenderer…sectionListRenderer` + `header.musicImmersiveHeaderRenderer` / `musicVisualHeaderRenderer` (subscribe button) |
| `browse` | `browseId: UC…` or a shelf's browse id + `params` | "Show all": section list with a `gridRenderer` or `musicShelfRenderer` |
| `browse` | `browseId: VL<id>` / `VLLM` | two-column layout, `musicPlaylistShelfRenderer` (or `musicShelfRenderer`) with a trailing `continuationItemRenderer` |
| `browse` | `continuation: <token>` | playlist page 2: `onResponseReceivedActions[].appendContinuationItemsAction.continuationItems` or `continuationContents.musicPlaylistShelfContinuation` |
| `browse` | `browseId: VL<missing>` | 200 with `alerts[]` and no contents, **or** a 4xx. Unknown; capture decides |
| `browse` | `FEmusic_liked_playlists` / `_liked_videos` / `_liked_albums` / `_library_corpus_track_artists` / `_library_corpus_artists` | single-column section list; chips in the header; sort in a `musicSortFilterButtonRenderer` (or similar) |
| `guide` | `{}` | `items[].guideSectionRenderer.items[].guideEntryRenderer` (playlist entries) |
| `browse` | `FEmusic_history` | section list of `musicShelfRenderer`s, one per day; the removal token is probably inside each row's `menu` (`feedbackEndpoint`) |
| `next` | `videoId`, optional `playlistId`, `params`, `isAudioOnly` | `contents.singleColumnMusicWatchNextResultsRenderer.tabbedRenderer.watchNextTabbedResultsRenderer.tabs[]`: tab 0 is `musicQueueRenderer.content.playlistPanelRenderer` (items `playlistPanelVideoRenderer` / `playlistPanelVideoWrapperRenderer` with the counterpart; `title`; chips in `subHeaderChipCloud`), tabs 1–2 are the lyrics and related `browseEndpoint`s (with `unselectable` when disabled) |
| `browse` | lyrics `MPLY…` | `contents.sectionListRenderer.contents[].musicDescriptionShelfRenderer{description, footer}` or a message renderer for none |
| `browse` | related `MPTR…` | `contents.sectionListRenderer` of carousels |

**Swift public surface** (prose only):
- On `InnerTubeClient`, fetches for: album, artist, artist "Show all", playlist, playlist continuation, library section (with optional sort token), library continuation, sidebar playlists, history, watch-next, lyrics and related.
- Each takes `Credentials?` and throws `InnerTubeError`.
- The existing `browse(_:credentials:)` stays for section-list pages.

## Codebase impact

| File / area | Impact |
|---|---|
| `Sources/InnerTube/` (new parser files) | One file per page type (ARCH §5.3): album, artist, playlist, library (+ guide), history, watch-next, lyrics / related |
| `MusicItem.swift`, `Shelf.swift` | Additive fields (album audio playlist id, track number, removal token) and new page models. Public API |
| `BrowseParser.swift` (`JSONValue.sectionList`) | Reaches only the single-column first page and `sectionListContinuation`. Two-column pages (album, playlist), bare `contents.sectionListRenderer` (lyrics, related) and playlist continuations need new roots |
| `Page.swift` (`nextContinuation`) | Already handles a trailing `continuationItemRenderer` in a `contents` array. The playlist page 2 container (`appendContinuationItemsAction`) is new |
| `ItemParser.swift` | Reused for rows and cards. Not reusable as-is for `playlistPanelVideoRenderer` queue items, `guideEntryRenderer` or header renderers. Row-level menu reading (history token) is new. The current rule "menus hold unrelated endpoints, ignore them" must stay intact for item kind |
| `InnerTubeClient.swift` | New public fetches built on `fetch(_:body:credentials:)`. Line 91's comment ("`VL…` … route it to the playlist screen") will now point to the new playlist fetch. Not-available mapping may touch `attemptOnce` if Google answers 4xx |
| `InnerTubeError` | Possibly a new case, or a result enum on the playlist fetch, for "not available" (dev decides) |
| `Scripts/scrub-fixture.py` | Line 47 drops every `menu` that is not multi-select. That would erase the history removal tokens and possibly the library sort and subscribe data. Needs an allowance. Also issue-9 L1 (scrub emails before the `@handle` substitution) becomes live with signed-in captures |
| `Tests/InnerTubeTests/Fixtures/` + `README.md` | New fixtures, each with a README row (enforced by `fixtureIsDocumented`) |
| `Tests/InnerTubeTests/` | A parser test file per page type, end-to-end tests through `ScriptedTransport`, and an `INNERTUBE_LIVE` playlist paging test (pattern: `DiscoveryClientTests.swift:114`) |
| `docs/01-reverse-engineering.md` §4 | Add the confirmed roots for these pages |
| `App/*` | **No changes.** The "Done when" item about a temporary screen is met by the live-gated test |

### Codebase constraints

- **K1. Fixture feasibility is inverted from 2.2.**
  - Guest-capturable: album, artist, artist Show-all, public playlist + continuation, a missing playlist id, `next`, lyrics, related.
  - Signed-in only: all five library ids, `VLLM`, `guide`, `FEmusic_history`, and the own-playlist Suggestions shelf.
  - The agent cannot capture signed-in data (no Keychain or cookie access; PRD 7.3). By the PR #54 precedent, those parsers ship on **synthetic** fixtures (shape from public `ytmusicapi` parsers), marked in the README, with real scrubbed captures supplied by the user later.
  - Most of FR-4 and FR-5 would then be verified only against synthetic shapes. This is the top risk (open question 1).
- **K2. The scrubber drops `menu`** (`scrub-fixture.py:47`). The history removal token, and possibly subscribe or sort data, live in menus. Raw signed-in captures processed by the current script would lose them silently.
- **K3. Single root assumption.** `sectionList` and `BrowsePage` assume one layout. The new pages need their own roots. Keep `BrowsePage` unchanged for existing callers.
- **K4. Errors.** Today any missing container is `.unexpectedResponse`, and non-2xx is `.httpStatus` before parsing. "Not available" must be separated from both without changing the 2.1 retry rules (4xx is not retried today, which is correct).
- **K5. Guest continuation** requires the same `X-Goog-Visitor-Id` as the page that issued it [RE line 262]. Playlist paging inherits this rule and its doc comment.
- **K6. The body is already `[String: any Sendable]`** (resolved in 2.2), so `next` with several keys and `guide` with an empty body fit without transport changes.

## Conflicts and gaps

- **C1. Queue ownership.**
  - ARCH §4.4 and UI §10.2 say the queue lives in the page and Swift reads it through the bridge (3.2). The chips and source come from `next`.
  - The issue asks the `next` parser for the "Up next queue" too.
  - Parsing queue items is cheap, but its consumer is unclear: initial display before the bridge reports, chip switching (the new upcoming list), or nothing.
  - **Recommendation:** parse the items (chip switching needs them), and document that the bridge stays the source of truth. Needs confirmation (open question 2).
- **C2. PRD row mapping.** The issue lists F-LIB-2, F-LIB-4, F-PLY-4 and F-PLY-5 as 2.3 requirements, but the PRD table maps them to 4.1/4.5, 2.4/4.5, 3.2/4.6 and 4.8. UI §7, §4.3 and §10 do put the parsers in 2.3. This is a traceability gap only: update the PRD "Rows" column to add 2.3.
- **C3. Podcasts.** The library section is excluded until issue #7 / docs/05 question 4 is answered. Skip and log, as in 2.2.
- **C4. Branch name.** The issue says `feature/innertube-entities`; the pipeline runs on `feature/issue-10`. Harmless, but the PR body should mention it.
- **G1. "Not available" wire shape is unknown** (200 + alerts vs 4xx, and whether private and deleted differ). The guest capture of a non-existent id settles one case. A private playlist of another user may behave differently and should be captured too if possible.
- **G2. Library sort.** UI §7 says sort is server-side "when the response offers it, otherwise locally". Which library sections offer server sort, and in what form (chip params vs menu), is unknown until captured, and that needs a signed-in capture.
- **G3. Comments tab** (F-PLY-6, UI §10.4) is not in this issue and is not specified. Out of scope.
- **G4. `next` request flavours.** The source of a radio (`RDAMVM…` playlist + `params`) vs an album or playlist queue gives different shapes (chips only for radio). The fixtures need at least one radio and one non-radio `next`.

## Edge cases & error scenarios

- **Playlist**
  - Empty playlist (0 tracks): empty page, no continuation, not an error.
  - Tracks that are unavailable or deleted inside a playlist (greyed rows with no `videoId` / a `musicItemThumbnailOverlayRenderer` but no play endpoint) are dropped and logged, or kept as non-playable. Recommend keeping the count consistent by dropping only rows with no identity.
  - A continuation token that returns an empty page means the end.
  - A guest continuation after `resetGuestVisitor()` fails (K5): restart from page 1.
- **Not available:** a 4xx that is **not** "not available" (for example 400 bad request, 429) must stay `httpStatus` and must not be turned into "not available".
- **Album:** singles with one track; an album whose tracks have several artists (per-row artist refs); a missing footer; an explicit badge on the header vs on rows.
- **Artist:** a channel with no Top songs (non-music channel or profile `UC…` id), subscriber count absent, subscribe state missing as a guest (`nil`, not `false`); "Show all" `params` without a `browseId` change.
- **Library:** empty sections ("Songs you like appear here"), a guest call to a library id (sign-in alert or redirect payload → typed outcome), very large libraries (paging), "New playlist" and "Liked music" cards inside `FEmusic_liked_playlists` (keep Liked music as a playlist; drop or flag the "New playlist" action card).
- **Guide:** a signed-out guide with no playlist section; a brand account with a different list (via `X-Goog-AuthUser`).
- **History:** an empty history; rows that are videos (`OMV`/`UGC`); a missing token on one row (drop the row or keep it non-removable; recommend keeping it with a `nil` token so the list stays complete).
- **`next`:** a track with no lyrics; a track with no related; video-only uploads (no ATV counterpart); a queue continuation for long radio; the current item not first in the list.
- **Lyrics:** multi-line text with blank lines preserved; an RTL / CJK script; a missing source line.
- **Privacy:** a signed-in capture that contains the account handle in a playlist owner, in "Liked music" ownership or in a history row; emails in descriptions (L1).
- **Concurrency:** none beyond 2.1's actor rules. Page fetches are independent and stateless; the caller keeps paging state per identity (P22 L3).

## Risks & dependencies

- Depends on 2.2 (merged, PR #54): `ItemParser`, `Shelf`, `Page`, `BrowseTarget`, fixtures, scrubber, privacy guard.
- Blocks #16 (4.1 sidebar list), #19 (4.4 entity pages), #22 (4.8 player tabs). 2.4 (#11) relies on the history removal tokens and on the subscribe and channel ids parsed here.
- **Synthetic-fixture ratio (K1).** More than half of the parsers may be checked only against hand-built shapes. Wrong guesses surface only in 4.1 and 4.5.
- **Scrubber gap (K2)** could silently strip the very tokens 2.4 needs, or let a signed-in identity slip through (L1).
- **Size.** This is the widest 2.x row: about 8 parser files, about 15 fixtures and several new public models.
- **Wire drift.** All roots are `[known, unverified]`. The captures win over this document.

## Open questions for stakeholders

1. **(Blocking for fixtures, K1)** Do you accept synthetic fixtures for the signed-in-only parsers (library × 5, `VLLM`, `guide`, history, own-playlist Suggestions), as in 2.2, with real scrubbed captures supplied by you later? Or will you provide scrubbed signed-in captures before the dev phase? This is the PR #54 precedent and the recommended default.
2. **(Scope, C1)** What is the parsed Up next queue for, given that the bridge owns the queue (ARCH §4.4)? Recommendation: parse items, chips, source, tab ids and counterpart; the bridge stays the source of truth.
3. **(Behaviour, G1)** Should "not available" cover private and deleted alike (one case), or should they differ? Recommendation: one case. UI §8.1 shows one message.

## Estimated complexity

**Large.** Eight-plus page types, new response roots, a new item renderer for the queue, new public models for three downstream screens, scrubber changes, and a fixture set that is mostly synthetic on the signed-in side. It all stays in one package with no `App/` changes. If the stakeholder agrees, it could be split into 2.3a (album, artist, playlist, `next`, lyrics, related: guest-capturable) and 2.3b (library, guide, history: signed-in).

## Decisions from the user (after BA)

- Q1: Accept synthetic fixtures now for signed-in-only parsers (library x5, VLLM, guide, history, Suggestions), as in PR #54; real scrubbed captures later. No 2.3a/2.3b split — full scope in this run.
- Q2: Parse the Up next queue from `next` (items, chips, source, tab ids, counterpart); the bridge stays the source of truth for the live queue.
- Q3: Private and deleted playlists are one typed "not available" case.
