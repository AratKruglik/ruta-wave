# Brief

Source: https://github.com/AratKruglik/yt-music-mac/issues/10

## [2.3] InnerTube: parsers for album, artist, playlist, library, history and up next

Backlog row **2.3** of [06](https://github.com/AratKruglik/yt-music-mac/blob/develop/docs/06-backlog.md). Requirements: F-BRW-3, F-LIB-1, F-LIB-2, F-LIB-4, F-PLY-4, F-PLY-5 ([00 §5](https://github.com/AratKruglik/yt-music-mac/blob/develop/docs/00-prd.md)).

## Goal

The read side of entity pages, the library and the player page.

## Scope
- [ ] Album (`browse MPREb…`): header, type and year, numbered tracks, footer (release date, track count, label), "Other versions", "More from <artist>"
- [ ] Artist (`browse UC…`): header with subscriber count and subscribe state, top songs, every shelf, "Show all" `params`, About
- [ ] Playlist (`browse VL<id>`): header, tracks with `continuation`, the Suggestions shelf of own playlists, the "not available" case
- [ ] Library: `FEmusic_liked_playlists`, `FEmusic_liked_videos`, `FEmusic_liked_albums`, `FEmusic_library_corpus_track_artists`, `FEmusic_library_corpus_artists`; offered sections and sort options; Liked music (`VLLM`)
- [ ] Sidebar playlist list: the `guide` endpoint, fallback `FEmusic_liked_playlists`
- [ ] History: `FEmusic_history` grouped by day, with the per-row feedback token for removal
- [ ] `next`: Up next queue, radio chips, the "Playing from" source, lyrics `browseId`, related `browseId`, the audio / video counterpart id
- [ ] Lyrics and Related pages (`browse` with the ids from `next`)
- [ ] Fixtures without personal data and unit tests for every parser

## Done when
- [ ] Parser tests pass
- [ ] From a temporary screen or a test you can fetch a playlist longer than one page, with paging
- [ ] A private or deleted playlist yields a typed "not available" result, not a parse error

## Notes
- Podcasts library section (`FEmusic_library_non_music_audio_list`) only if #7 says yes.

## Dependencies

Blocked by: #9

Blocks: #16, #19, #22

## References

[02 §5.2](https://github.com/AratKruglik/yt-music-mac/blob/develop/docs/02-architecture.md) · [08 §4.3, §7, §8, §10](https://github.com/AratKruglik/yt-music-mac/blob/develop/docs/08-ui-spec.md)

## Delivery

Branch `feature/innertube-entities`, PR into `develop`. One SDLC pipeline run:

```
/sdlc:start "InnerTube parsers for album, artist, playlist, library, history and up-next queue" --type=feature
```
