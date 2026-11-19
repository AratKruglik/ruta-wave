# Brief

https://github.com/AratKruglik/yt-music-mac/issues/9

Source of requirements: GitHub issue #9 in AratKruglik/yt-music-mac — "[2.2] InnerTube: models and parsers for home, explore, search and suggestions" (read it with `gh issue view 9 --repo AratKruglik/yt-music-mac --comments`). It references docs/06-backlog.md row 2.2, docs/00-prd.md §5, docs/02-architecture.md §5, docs/08-ui-spec.md §3/§5/§6 and docs/03-roadmap.md Stage 2. Builds on the InnerTube core from issue #8.

## Issue #9 body (verbatim, fetched by orchestrator)

Backlog row **2.2** of [06](https://github.com/AratKruglik/yt-music-mac/blob/develop/docs/06-backlog.md). Requirements: F-BRW-1, F-BRW-2, F-BRW-4, F-SRC-1, F-SRC-2 ([00 §5](https://github.com/AratKruglik/yt-music-mac/blob/develop/docs/00-prd.md)).

## Goal

The read side of discovery: typed models and tolerant parsers for everything the Home, Explore and Search screens show.

## Scope
- [ ] Models (`Sendable`): `Song`, `Album`, `Artist`, `Playlist`, `Shelf`, `SearchResults`
- [ ] `JSONValue` helpers for walking renderer structures (runs, thumbnails, navigation endpoints, menus)
- [ ] Home: `browse FEmusic_home` — mood chips (label + `params`), shelves of every observed kind, `continuation`
- [ ] Explore: `browse FEmusic_explore` — tiles and shelves
- [ ] Explore subpages: `FEmusic_new_releases`, `FEmusic_charts` (country in `formData`, trend arrows), `FEmusic_moods_and_genres`, `FEmusic_moods_and_genres_category` + `params`
- [ ] "More" list of a shelf: `browse` with the shelf's `browseId` + `params`
- [ ] Search: `search` with `query` and filter `params`; filter chips taken from the response; top result card; per-type sections; `continuation`; the "Did you mean / Showing results for" line
- [ ] Suggestions: `music/get_search_suggestions` — text suggestions, entity suggestions, and history entries with their `feedbackToken` (empty input, signed in)
- [ ] One parser file per page type; unknown shelves are skipped and logged (rule from #8)
- [ ] Fixtures: real guest and signed-in responses with personal data stripped (no cookies, account names, emails, `visitorData`)
- [ ] Unit tests for every parser on the fixtures

## Done when
- [ ] Parser tests pass on guest and signed-in fixtures
- [ ] From a temporary screen or a test you can fetch Home and the results of a search query
- [ ] A fixture with an unknown shelf injected still parses the rest of the page
- [ ] Fixtures contain no personal data

## Notes
- Podcast / episode filters depend on #7.
- Everything in 02 §5 and 08 is labelled **[known]** — verify on the live responses while saving the fixtures.

## Dependencies

Blocked by: #8

Blocks: #10, #17, #18

## References

[02 §5](https://github.com/AratKruglik/yt-music-mac/blob/develop/docs/02-architecture.md) · [08 §3, §5, §6](https://github.com/AratKruglik/yt-music-mac/blob/develop/docs/08-ui-spec.md) · [03 Stage 2](https://github.com/AratKruglik/yt-music-mac/blob/develop/docs/03-roadmap.md)

## Delivery

Branch `feature/innertube-browse-search`, PR into `develop`. One SDLC pipeline run:

```
/sdlc:start "InnerTube models and parsers for home, explore, search and suggestions with fixture tests" --type=feature
```

## Orchestrator decisions on BA open questions (confirmed with the user 2026-11-19)

- Q1 Explore subpages: IN scope — the issue body lists FEmusic_new_releases, FEmusic_charts (country in formData, trend arrows), FEmusic_moods_and_genres and FEmusic_moods_and_genres_category + params explicitly.
- Q2 Fixtures (user decision): real, scrubbed guest captures fetched live by the dev agent; minimal, clearly marked synthetic JSON for signed-in-only shapes (e.g. Listen again, search history with feedbackToken). Real signed-in captures will be added by the user later; the privacy guard test must cover them.
- Q3 Search filters: IN scope (issue: filter params, chips from response, continuation). Podcast/episode filters depend on #7 — skip and log those result types.
