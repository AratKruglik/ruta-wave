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

## Synthetic files

These shapes only occur when signed in or could not be reproduced as a guest. They are hand-written, use placeholder data and are expected to be replaced by real, scrubbed captures later.

| File | What it stands for |
|---|---|
| `home-signed-in.json` | Home with a chip row, a "Listen again" shelf with a strapline and a "Mixed for you" shelf with a radio card |
| `search-empty.json` | A search that has chips and no results (Google returns fuzzy results for every guest query, so this could not be captured) |
| `suggestions-history.json` | History suggestions with `feedbackToken`. Shape checked against the `parse_search_suggestions` function of the public `ytmusicapi` project (`historySuggestionRenderer`, `serviceEndpoint.feedbackEndpoint.feedbackToken`, `navigationEndpoint.searchEndpoint.query`). |

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
