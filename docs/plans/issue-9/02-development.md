# Development report: InnerTube models and parsers for home, explore, search and suggestions (issue #9, backlog 2.2)

Branch `feature/issue-9`. Nothing committed (the documentation phase commits). Scope: `Packages/InnerTube` plus the two doc updates from the approved plan.

## Result

- `swift build`: clean, no warnings.
- `swift test` in `Packages/InnerTube`: 152 tests in 20 suites pass (baseline 87).
- `INNERTUBE_LIVE=1 swift test --filter DiscoveryClientTests`: the live guest smoke test (Home + search) passed.
- `xcodebuild -project Redwave.xcodeproj -scheme Redwave -destination 'platform=macOS' build`: `** BUILD SUCCEEDED **`.
- `App/`, `project.yml`, `Info.plist` and entitlements are untouched. No dependency added. Project system is XcodeGen; no project regeneration needed.

## Files created (all under `Packages/InnerTube/` unless noted)

| Path | Type |
|---|---|
| `Sources/InnerTube/MusicItem.swift` | model: `BrowseTarget`, `ItemRef`, `ChartRank`, `Song`, `Album`, `Artist`, `Playlist`, `NavigationLink`, `MusicItem` |
| `Sources/InnerTube/Shelf.swift` | model: `Shelf`, `Chip`, `BrowsePage`, `ChartCountry`, `ChartsPage` |
| `Sources/InnerTube/SearchResults.swift` | model: `SearchResults`, `SearchCorrection`, `SearchHistoryEntry`, `SearchSuggestions` |
| `Sources/InnerTube/ItemParser.swift` | parser (shared): item kinds, shelves, chips, endpoints |
| `Sources/InnerTube/BrowseParser.swift` | parser: `BrowsePage(browse:)`, first page and continuation |
| `Sources/InnerTube/ChartsParser.swift` | parser: `ChartsPage(charts:)` |
| `Sources/InnerTube/SearchParser.swift` | parser: `SearchResults(search:)` |
| `Sources/InnerTube/SuggestionsParser.swift` | parser: `SearchSuggestions(suggestions:)` |
| `Scripts/scrub-fixture.py` | tool (Python 3 stdlib): scrub and trim a raw capture |
| `Tests/InnerTubeTests/Fixtures/*.json` (16) + `README.md` | fixtures: 13 real guest captures, 3 synthetic |
| `Tests/InnerTubeTests/Support/Fixture.swift`, `Support/ScriptedTransport.swift` | test helpers |
| `Tests/InnerTubeTests/{ItemParser,BrowseParser,ChartsParser,SearchParser,SuggestionsParser,DiscoveryClient,FixturePrivacy}Tests.swift` | tests |

## Files modified

- `Package.swift`: test target `resources: [.copy("Fixtures")]` (K4).
- `Sources/InnerTube/AccountInfo.swift`: `text()` joins all runs; empty gives `nil` (K1).
- `Sources/InnerTube/InnerTubeRequest.swift`: body type `[String: any Sendable]`, `isValidJSONObject` guard (K3).
- `Sources/InnerTube/InnerTubeClient.swift`: body type (K3), public `Credentials`, private `fetch`, public `home`, `browse`, `browseContinuation`, `charts`, `search`, `searchContinuation`, `searchSuggestions`.
- `Tests/InnerTubeTests/ClientTransportTests.swift`: `Step` / `Script` moved to Support (no logic change).
- `Tests/InnerTubeTests/JSONValueTests.swift`: two `text()` tests. `InnerTubeRequestTests.swift`: nested body test and invalid-body test.
- `docs/01-reverse-engineering.md`: new section 4.9. `docs/02-architecture.md`: fixtures path line.

## Key design decisions

1. **One shared section parser.** `ItemParser.section` and `ItemParser.item` feed Home, Explore, subpages, More pages, the Home continuation and the Charts shelves. One file per response shape, as in the plan.
2. **Kind comes from the item's own endpoint only** (top-level `navigationEndpoint`, then the first title run, then the overlay play endpoint, then `playlistItemData.videoId`). The first endpoint found decides, even when it classifies as unsupported, so an episode row (title run is a `NON_MUSIC_AUDIO_TRACK_PAGE` link) can never fall through to the `playlistItemData` song fallback. No recursive search; a test puts artist and album endpoints in a song row menu.
3. **Auth is a parameter.** `Credentials?` (`nil` = guest) on every fetch; both `post` and `postGuest` are reused unchanged, so retry, 401 and visitor rules did not change.
4. **Suggestion queries come from `navigationEndpoint.searchEndpoint.query`**, falling back to the joined `suggestion` runs. The history shape was checked against the upstream `ytmusicapi` source (`parse_search_suggestions`) fetched from GitHub, not Context7.
5. **Charts countries** join the menu options to the `musicFormBooleanChoice` mutations on the entity key. The scrub script keeps that menu and those mutations, trimmed to 4 countries (3 + the selected one).

## Fixtures

- Captured live on 2026-11-19 as a guest (`hl=en`, `gl=US`, `1.20261115.14.00`, Charts with explicit US `formData`). The raw captures were in the session scratchpad only.
- Scrub: `responseContext` and every `visitorData` removed (not placeholdered), tracking and accessibility keys and item menus removed, continuation and feedback tokens replaced by `PLACEHOLDER_*`, profile items blanked, `@handles` replaced, two private individuals' names masked (a community-playlist author and a podcast host).
- Verified: grep of every fixture for the raw captured visitor value, `SAPISID`, `__Secure-` and emails: no hits. `FixturePrivacyTests` fails on a file with `visitorData`, an unscrubbed continuation and an email (checked by hand with a temporary bad file).
- Charts keeps a fixed country subset (`ZZ`, `AR`, `DE`, selected `US`) so the capturer's country does not leak. Guest Home, Explore and New releases content still follows the capturer's IP (Ukrainian content, a `UA` tastebuilder image); this is noted in the fixtures README and cannot be fixed without another exit IP.

## Project shape

XcodeGen project, change confined to local SPM package `InnerTube` (tools 6.0, Swift 6 mode, `macOS(.v14)`, depends on `Auth`). No UI, state, persistence or navigation change. Swift Testing. No pbxproj edit, no manifest change besides `Package.swift` test resources.

## API mismatches against the BA spec (all accepted at the plan gate, section 9)

1. Unfiltered search has no per-type sections or "Show all" targets: a top card plus a flat list.
2. Guest continuations need the same visitor header; page-2 roots are `sectionListContinuation` and `musicShelfContinuation`.
3. Charts country follows the caller IP, not `gl`; codes exist only in `frameworkUpdates` mutations.
4. `moreContentButton` can be a "Play all" watch endpoint, which is ignored.
5. Explore tiles and mood buttons are `musicNavigationButtonRenderer` with full `browseId` + `params`, modelled as `NavigationLink`.
6. "No results" search could not be reproduced live; synthetic fixture.

## Deviations from the approved plan

0. Process: fixtures were generated into the working tree before `FixturePrivacyTests` existed (the guard was written and passing before anything is committed). `ItemParser` was written before its tests (not strict TDD). The convention skills were invoked after implementation and the code checked against them. Fixture sizes are 4 to 62 KB, above the ~30 KB target, because files are pretty-printed with sorted keys. Test helper `Fixture.directory` force-unwraps `Bundle.module.resourceURL` (test-only).

1. `Fixture.json` helper lives in `Support/Fixture.swift` as planned; `Step.fixture` is a throwing static, so scripts are written `[try .fixture("home")]`.
2. The scrub script has two flags not in the plan: `--mask NAME` (replace a private individual's name) and `--charts` (trim the country menu consistently with the mutations).
3. The `menu` key is deleted everywhere except inside the Charts country selector (the plan said delete `menu` outright, but that would remove the country options).
4. Search card sub-items (`musicCardShelfRenderer.contents`, the artist's top songs) are not parsed: `topResult` and `items` only, as in the plan's contract.
5. `didYouMeanRenderer` is accepted only when it carries both `correctedQueryEndpoint` and `originalQueryEndpoint`; it was not observed live.
6. The history-suggestion shape was verified against the upstream `ytmusicapi` source over HTTP rather than through Context7.

## Verified against the live service (matches the plan's section 2)

Home root and chips, the old-style continuation, the visitor requirement for guest continuations, flat unfiltered search, `showingResultsForRenderer`, Charts `formData`, entity-mutation country codes, suggestions in two sections. No new mismatch with the plan's section 9 was found.

## Open items for later phases

- `liveHomeAndSearch` must run alone: `INNERTUBE_LIVE=1 swift test --filter DiscoveryClientTests`. In a full run it would put a real visitor into `GuestVisitor.shared` while `ClientTransportTests` asserts on the visitor header.
- Synthetic fixtures (`home-signed-in.json`, `search-empty.json`, `suggestions-history.json`) are marked in the fixtures README and should be replaced by the user's real, scrubbed signed-in captures. The privacy guard already covers any added file.
- A `More` target that is a `VL…` playlist returns the playlist page shape (backlog 2.3). `browse()` on it will throw `unexpectedResponse`; the UI must route `VL…` to the playlist screen. Documented on `browse`.
- Search podcasts, episodes and profiles are skipped and logged until issue #7.
- Request `hl` / `gl` follow `Locale.current`. Parsing never depends on the localized "Song" / "Album" labels, but `subtitle` strings are localized display text.

## Security fix pass

Fixes for High H1 in 04-security.md. No false positives.

- `Fixtures/search.json` (:1162, :1186, :1217, :1236, :1241, :1342, :1367, :1385, :1415, :1434, :1439): the two private individuals' channel IDs, playlist ID, show ID and covers are placeholders. Grep for the six old identifiers finds nothing.
- `SearchParserTests.swift:46`: expected title is now "Placeholder Podcast".
- `Scripts/scrub-fixture.py`: new `mask_name_links` pass (a "Placeholder Name" run's `browseId` becomes `UCplaceholder0000000000000`) and a repeatable `--mask-id`.
- `FixturePrivacyTests.swift`: new rule "masked name with a live channel link", and the leaked sample extended.
- `Fixtures/README.md`: search.json row and step 2 updated.
- `swift test` in Packages/InnerTube: 153 tests passed.
- Low 1-3 not touched (out of scope).
