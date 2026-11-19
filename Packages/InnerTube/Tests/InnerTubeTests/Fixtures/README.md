# InnerTube fixtures

Every `*.json` file here is test input for the parsers. `FixturePrivacyTests` runs over all of them and fails on cookies, emails, `visitorData`, account keys and any continuation or feedback token that is not a `PLACEHOLDER_*` value. It also fails on a file that has no row in the tables below.

Real captures were taken as a **guest** (no cookies) on 2026-11-19 with `hl=en`, `gl=US` and client version `1.20261115.14.00`, `POST https://music.youtube.com/youtubei/v1/<endpoint>?prettyPrint=false`, client `WEB_REMIX`. Follow-up calls (continuations, subpages) reused the `X-Goog-Visitor-Id` returned by the first Home response. Raw captures were never committed. They were scrubbed and trimmed with `../../../Scripts/scrub-fixture.py`.

## Real guest captures

Guest Home, Explore, New releases and mood content follows the capturer's IP address regardless of `gl` (the captures show Ukrainian content and a `UA` tastebuilder image). Parsers must not depend on it.

| File | Request body (besides `context`) | Trim |
|---|---|---|
| `home.json` | `endpoint browse`: `{"browseId":"FEmusic_home"}` | 3 shelves, 3 items each |
| `home-continuation.json` | `browse`: `{"continuation": <token from home>}` plus the visitor header | 3 shelves, 3 items each |
| `explore.json` | `browse`: `{"browseId":"FEmusic_explore"}` | 5 sections, 3 items each |
| `new-releases.json` | `browse`: `{"browseId":"FEmusic_new_releases"}` | 3 sections, 3 items each |
| `moods-and-genres.json` | `browse`: `{"browseId":"FEmusic_moods_and_genres"}` | 3 items per grid |
| `mood-category.json` | `browse`: `{"browseId":"FEmusic_moods_and_genres_category","params":<tile params from explore>}` | 2 shelves, 3 items each |
| `more-albums.json` | `browse`: `{"browseId":"FEmusic_new_releases_albums"}` (the "More" target of a shelf) | 3 grid items |
| `charts.json` | `browse`: `{"browseId":"FEmusic_charts","formData":{"selectedValues":["US"]}}`. The country must be explicit: without `formData` it follows the caller IP, not `gl`. | 5 sections, 3 items plus one item per trend, 4 countries (`ZZ`, `AR`, `DE` and the selected `US`) |
| `search.json` | `search`: `{"query":"radiohead"}` | top card plus one item of each kind (album, episode, song, artist, video, playlist, profile, podcast). Names of private individuals, their channel IDs, and the IDs and covers of their playlist and podcast are placeholders. Profile data is masked. |
| `search-songs.json` | `search`: `{"query":"radiohead","params":<Songs chip params>}` | 3 items |
| `search-songs-continuation.json` | `search`: `{"continuation": <token from search-songs>}` plus the visitor header | 3 items |
| `search-correction.json` | `search`: `{"query":"radiohed"}` | correction line, card, 2 items |
| `suggestions.json` | `music/get_search_suggestions`: `{"input":"radi"}` | none |
| `album.json` | `browse`: `{"browseId":"MPREb_yXhSI4FCUo6"}` (OK Computer) | 3 tracks, both carousels |
| `artist.json` | `browse`: `{"browseId":"UCr_iyUANcn9OX_yy9piYoLw"}` (Radiohead) | 20 sections, 2 items each, so About survives |
| `artist-albums.json` | `browse`: the "Albums" More target (`MPADUCr_…` plus params) | 3 grid items |
| `playlist.json` | `browse`: `{"browseId":"VLRDCLAK5uy_nZiG9ehz_MQoWQxY5yElsLHCcG0tv9PRg"}` (a YouTube Music playlist of 118 tracks) | 3 tracks, the trailing track continuation and the section-list continuation kept |
| `playlist-continuation.json` | `browse`: `{"continuation": <track token>}` plus the visitor header of the first call | last page (no token), 3 tracks |
| `playlist-top-songs.json` | `browse`: the artist "Top songs" target (`VLOLAK5uy_…` plus params), a single-column playlist | 3 tracks plus the trailing continuation |
| `playlist-missing.json` | `browse`: `{"browseId":"VLPLdoesnotexist0000000000000000000"}`. HTTP 200 and no `contents` key. | as returned |
| `liked-music-guest.json` | `browse`: `{"browseId":"VLLM"}` as a guest. Only a sign-in message. | as returned |
| `library-guest.json` | `browse`: `{"browseId":"FEmusic_liked_playlists"}` as a guest. Only a sign-in message. | as returned |
| `guide-guest.json` | `guide`: `{}` as a guest. Home, Explore and Library entries, no playlists. | as returned |
| `history-guest.json` | `browse`: `{"browseId":"FEmusic_history"}` as a guest. Only a sign-in message. | as returned |
| `next-radio.json` | `next`: `{"videoId":"jNY_wLukVW0","playlistId":"RDAMVMjNY_wLukVW0"}` | 3 queue items (current first), chips and the radio continuation |
| `next-album.json` | `next`: `{"videoId":"jNY_wLukVW0","playlistId":"OLAK5uy_nc6afxSnmK8OFML8dF9q_0D1MBMXsGnL4"}` | 2 queue items plus the automix preview |
| `next-no-lyrics.json` | `next`: `{"videoId":"L7p47zYKJoM"}`. The Lyrics tab keeps its endpoint and is `unselectable`. | 2 queue items |
| `next-continuation.json` | `next`: `{"continuation": <radio token>}` | 2 items |
| `lyrics.json` | `browse`: `{"browseId":"MPLYt_yXhSI4FCUo6-1"}`. **The lyric text is replaced** by placeholder lines (copyright): the `\r\n` line breaks, the blank line and the "Source: LyricFind" footer are kept. | one description |
| `lyrics-none.json` | `browse`: `{"browseId":"MPLYt_ob5cslgCNc0-5"}`. "Lyrics not available" message. | as returned |
| `related.json` | `browse`: `{"browseId":"MPTRt_yXhSI4FCUo6-1"}` | 6 sections, 2 items each. Every card of a private individual (a user playlist, a user upload) was removed. |

## Synthetic files

These shapes only occur when signed in or could not be reproduced as a guest. They are hand-written, use placeholder data and are expected to be replaced by real, scrubbed captures later.

| File | What it stands for |
|---|---|
| `home-signed-in.json` | Home with a chip row, a "Listen again" shelf with a strapline and a "Mixed for you" shelf with a radio card |
| `search-empty.json` | A search that has chips and no results (Google returns fuzzy results for every guest query, so this could not be captured) |
| `suggestions-history.json` | History suggestions with `feedbackToken`. Shape checked against the `parse_search_suggestions` function of the public `ytmusicapi` project (`historySuggestionRenderer`, `serviceEndpoint.feedbackEndpoint.feedbackToken`, `navigationEndpoint.searchEndpoint.query`). |
| `playlist-own.json` | An own playlist: the header wrapped in `musicEditablePlaylistDetailHeaderRenderer`, 2 tracks and a section-list continuation. Shape after `ytmusicapi` (`get_playlist`). |
| `playlist-suggestions.json` | The section-list continuation of an own playlist: `sectionListContinuation` holding a "Suggestions" `musicShelfRenderer`. Shape after `ytmusicapi`. |
| `liked-music.json` | `VLLM` signed in: two-column "Liked music" header without an owner link, 2 tracks and a trailing continuation |
| `library-playlists.json` | `FEmusic_liked_playlists`: section chips, a sort dropdown (`itemSectionTabbedHeaderRenderer`), a grid with the "New playlist" card, Liked music (`VLLM`), a playlist and a continuation. Shape after `ytmusicapi` (`get_library_playlists`, `prepare_order_params`), plus a Podcasts and an Uploads chip (dropped, #7). |
| `library-songs.json` | `FEmusic_liked_videos`: a `musicShelfRenderer` directly in the section list with a song, a video and a continuation |
| `library-albums.json` | `FEmusic_liked_albums`: a grid of 2 albums and a podcast show (skipped) |
| `library-artists.json` | `FEmusic_library_corpus_track_artists`: a shelf of 2 artist rows in an `itemSectionRenderer` |
| `library-subscriptions.json` | `FEmusic_library_corpus_artists`: a shelf of 2 artist rows |
| `library-continuation.json` | A library continuation: `gridContinuation` with one playlist and no token |
| `guide.json` | `guide` signed in: Home, Explore and Library, then Liked music (`VLLM`) and 2 placeholder playlists. Shape after `youtubei.js` (`GuideSection`, `GuideEntry`). It has no owner field. |
| `history.json` | `FEmusic_history`: "Today" with 2 rows that carry a `REMOVE_FROM_HISTORY` menu item with a `PLACEHOLDER_FEEDBACK_*` token, "Yesterday" with a row that has no token. Shape after `ytmusicapi` (`get_history`). |
| `next-counterpart.json` | A radio queue with one `playlistPanelVideoWrapperRenderer` (a song with its video counterpart) and a plain row. A guest never received this shape. Shape after `ytmusicapi` (`parse_watch_playlist`). |

## Adding a real signed-in capture

1. Capture the response with your own account. Keep the raw file outside the repository.
2. Run `python3 Scripts/scrub-fixture.py RAW.json Tests/InnerTubeTests/Fixtures/NAME.json` from the package directory. It deletes `responseContext`, every `visitorData` / `VISITOR_DATA` and the tracking keys, and replaces continuation and feedback tokens. Pass `--mask NAME` for each private individual's name and `--mask-id ID` (without the `VL`/`MPSP` prefix) for each of their playlist or show IDs.
3. Replace each history `query` and its `suggestion.runs` text with generic queries (`placeholder query 1`).
4. Personalised shelves (Listen again, Recently played, Mixed for you, "Because you listened to ..."):
   - keep at most 2 items;
   - replace them with public catalogue items taken from the guest fixtures (title, IDs, thumbnails);
   - replace a strapline that names you, and the header avatar thumbnail, with placeholders.
5. Remove anything that holds the account name, handle, own channel ID (`UC...` of the account), avatar URL or email.
6. Add a row to the tables above, run `swift test --filter FixturePrivacyTests`, then read the diff by eye before committing.

## Entity pages (issue 2.3)

Private individuals appear in real captures as playlist owners, uploaders and `facepile` entries. Only YouTube Music-owned (`RDCLAK…`) and artist-owned (`OLAK…`) playlists were captured. For the history capture steps, keep each `REMOVE_FROM_HISTORY` item (its token stays a `PLACEHOLDER_FEEDBACK_*` value, the other menu items are dropped) and replace titles and IDs with public catalogue items. Check `python3 -I Scripts/test_scrub_fixture.py` after every change to the scrubber.
