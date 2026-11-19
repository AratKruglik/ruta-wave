# Security Review: InnerTube parsers for album, artist, playlist, library, history and up next (backlog 2.3, issue #10)

## Summary
- Critical: 0
- High: 0
- Medium: 0
- Out of scope: Low 4, Info 4

Nothing in this change exposes a credential or a private person. Nothing needs to go to the fix pass.

- **Request routing.** All 11 new `InnerTubeClient` methods go through the existing `fetch` router. A `nil` `Credentials` always takes `postGuest`, which carries no cookies and no `Authorization`. Server-controlled values (`WatchTarget`, lyrics and related IDs, sort and chip targets, continuation tokens) only ever become JSON string values in the body. They cannot change the endpoint, the host or the method.
- **Fixtures.** I checked all 30 new files (18 real guest captures, 12 synthetic).
  - None holds a visitor ID, cookie, email, account key or real token.
  - Every channel ID in the real captures belongs to an artist. The one `USER_CHANNEL` link is Radiohead's official channel.
  - Every playlist belongs to YouTube Music or to an artist.
  - The lyric text is placeholders.
  - I decoded one opaque base64 value of each kind. They hold only public IDs, a timestamp and the country code (`UA`).
- **Prior High.** Issue-9 H1 is closed: `search.json` now holds placeholders, and the script and the guard have the masked-name-link pass.

The four Low findings are gaps in the scrubber and the privacy guard. They would show up the first time someone replaces the 12 synthetic fixtures with real signed-in captures, as the README (`Fixtures/README.md:47`) and R1 of the development report plan to do. The fourth Low is issue-9 L3 again, now with four more entry points.

## Checked and clean

| Check | Result |
|---|---|
| Guest vs signed routing for the 11 new methods (`InnerTubeClient.swift:107-168`, `fetchBrowse` `:222-226`, `fetch` `:228-231`) | Every method calls `fetch` or `fetchBrowse`. Neither path has its own credential handling. `sidebarPlaylists` (`:139-145`) passes the same `credentials` to both `guide` and the `library` fallback. `EntityClientTests.swift:59-67` checks `SAPISIDHASH` and `X-Goog-AuthUser: 1` on a signed library request. Guest `postGuest` behaviour is unchanged since issue-9. |
| Endpoint and URL construction (`InnerTubeClient.swift:140`, `:158`, `:162`; `InnerTubeRequest.swift:16`, `:28`) | `"guide"` and `"next"` are literals. The force-unwrapped `URL(string:)` calls still only see literals. |
| Request bodies (`InnerTubeClient.swift:96-97`, `:154-157`, `:167`, `:223-224`) | All values are `String`. `body["x"] = optional` removes the key when the value is `nil`. Body keys cannot override `context`, and the `isValidJSONObject` guard from issue-9 still applies. `EntityClientTests.swift:103-115` checks that `next` sends only the given keys. |
| Server-controlled navigation (`ItemParser.swift:72-77`, `:91-94`; `WatchNextParser.swift:9-15`; `LibraryParser.swift:26-31`) | `WatchTarget`, `lyricsBrowseId`, `relatedBrowseId`, sort options and chips only go back as body values on fixed endpoints. |
| Thumbnail hosts (`PageHeaderParser.swift:29-36`; `ArtistParser.swift:11`; `LibraryParser.swift:56`; `ItemParser.swift:87`) | All go through `lastThumbnailURL` (`AccountInfo.swift:32-38`), which requires `https` and an allowlisted host. |
| Parser crash safety (`LibraryParser.swift:61-70`; `AlbumParser.swift:11`, `:15`) | The force unwraps `object[key]!` use keys from the same dictionary, so they cannot fail. The guide walk recurses, but no deeper than `JSONDecoder` already went when it built the `JSONValue`. `Int.init` on index text returns `nil` on overflow. `/\d{4}/` is linear. Array subscripts are bounds-checked (`JSONValue.swift:44-47`). |
| Logging (`HistoryParser.swift:7`; `Blocks.swift:9`; `ItemParser.swift:44`) | Only renderer key names (capped at 64 characters) and static text are logged. Titles, tokens (including `feedbackToken`), IDs and lyrics are never logged. There is no `print`, `NSLog` or `dump` in `Sources/` or `Tests/`. |
| Fixtures: secrets (all 46 `*.json`) | Grep finds no `visitorData`, `responseContext`, `trackingParams`, `loggingContext`, `datasyncId`, `channelHandle`, `VISITOR_INFO1_LIVE`, `SIDCC` or `Cgt…` visitor value. The only `@` strings are `@placeholder` (microformat handles, e.g. `artist.json:2564-2570`). The token keys are `continuation`, `token` and `feedbackToken`, all `PLACEHOLDER_*`, plus `charts.json` `opaqueToken`, which holds country codes. |
| Fixtures: people (18 real captures) | Every `UC…` link is `MUSIC_PAGE_TYPE_ARTIST`, for example `album.json:620` Yo La Tengo, `next-continuation.json:45` Tame Impala and `related.json:324` Jeff Buckley. The only `USER_CHANNEL` is `artist.json:1050-1056`, Radiohead's official channel. Playlists are `RDCLAK…` (YouTube Music), `OLAK…` (artist) and `PLukmsa…` (`artist.json:1711`, `:1834`, owned by the band channel at `:1730`, `:1853`). The facepile at `playlist.json:734-741` reads "YouTube Music" with an empty `rendererContext`. No fixture contains `commandContext` or `innertubeCommand`. |
| Fixtures: opaque base64 values | `queueContextParams` (`next-*.json`) holds a playlist ID, video ID, `playlistSetVideoId`, flags and a microsecond timestamp. `multiSelectParams` holds public playlist IDs. `commandEntityKey` holds a sort-option key plus a `VLOLAK…` ID. `serializedShareEntity` (`artist.json:2316`) holds the artist's `UC…` ID. Chip `params` hold the radio ID, a chip name and `en`. The artist Show-all `params` (`artist.json:1429`, `:1453`, `:1961`, `:1985`) hold `en`, `US` and the IP country `UA`; see the carry-over for issue-9 Info 1. |
| Copyright | `lyrics.json:10` is placeholder lines, and `lyrics-none.json` holds only the "not available" message. The Wikipedia text in `album.json:1136`, `artist.json:2139`, `:2230` and `related.json:742` keeps its CC BY-SA attribution and links (`related.json:748-766`). |
| `related.json` | It holds only artist and album cards and About. The cards of private individuals were removed, as the development report and `README.md:43` say. |
| Synthetic fixtures (12 files) | They use placeholder names (`Placeholder Owner`, `Placeholder playlist 1`, `Placeholder artist 1`) or public catalogue items, with `VLPLplaceholder…` IDs and `yt3.googleusercontent.com/placeholder` URLs. History tokens are `PLACEHOLDER_FEEDBACK_1/2` (`history.json:111`, `:293`). |
| Scrubber (`Scripts/scrub-fixture.py`) | It uses only the standard library: no `subprocess`, no `eval`, and it reads and writes only the paths on the command line. `removal_menu` (`:70-75`) keeps only the `REMOVE_FROM_HISTORY` item, and `clean` then turns its token into a placeholder (tested at `test_scrub_fixture.py:28-38`). Emails are replaced before handles (`:67`, tested at `:40-41`). |
| Scrub self-test (`Scripts/test_scrub_fixture.py`) | It loads the script by absolute path and sets `sys.dont_write_bytecode`. It lives outside `Fixtures/`, so the app bundle never includes it. `Fixtures/` holds only `*.json` and `README.md`, and there is no `__pycache__`. |
| Live and test credentials (`EntityClientTests.swift:5-7`, `:125-135`) | The cookie is the synthetic `test-sapisid`. The live test is opt-in through `INNERTUBE_LIVE=1`, runs as a guest and writes nothing. |
| Configuration | No `Package.swift`, `project.yml`, entitlement or `App/` change. `.gitignore` now ignores `/docs/plans`, so these reports are never committed. |
| Docs (`docs/01-reverse-engineering.md:278-290`) | It describes shapes only, with no IDs, tokens or visitor values. |

## Critical findings (for the fix pass)

None.

## High findings (for the fix pass)

None.

## Medium recommendations (not fixed this run)

None.

## Out of scope

### Low

#### 1. The scrubber and guard do not mask a private playlist owner in the new `facepile` shape — `Scripts/scrub-fixture.py:86-96`; `FixturePrivacyTests.swift:11`

**Issue.**
- This issue adds a parser for the playlist owner at `facepile.avatarStackViewModel` (`PageHeaderParser.swift:25-28`). In that shape the name is `text.content`, the link is `rendererContext.commandContext.onTap.innertubeCommand.browseEndpoint.browseId`, and the avatar images are under `avatars`.
- `mask_name_links` only rewrites a `browseId` that sits next to `"text": "Placeholder Name"` and a `navigationEndpoint`. The guard rule at `:11` has the same blind spot.
- `--mask NAME` therefore replaces the owner's name but keeps the owner's channel ID and avatar URL.

**Scenario.** Someone replaces `playlist-own.json` or `liked-music.json` with a real capture, as R1 plans. The capture is made with their own account, or of another user's public playlist, and is scrubbed with `--mask`. The fixture then still contains that account's `UC…` ID and avatar, and the guard passes.

**Fix.**
- In `mask_name_links`, before the recursion, add:
  ```python
  avatar = node.get("avatarStackViewModel")
  if isinstance(avatar, dict) and avatar.get("text", {}).get("content") == "Placeholder Name":
      avatar.pop("avatars", None)
      browse = (avatar.get("rendererContext", {}).get("commandContext", {}).get("onTap", {})
                .get("innertubeCommand", {}).get("browseEndpoint"))
      if isinstance(browse, dict) and "browseId" in browse:
          browse["browseId"] = "UCplaceholder0000000000000"
  ```
  No parser reads `avatars`.
- A regex cannot match this shape reliably, because of nesting and sibling keys. Add a structural test to `FixturePrivacyTests` instead. It parses each `Fixture.all` file with `JSONValue(response:)` and recursively fails on any `avatarStackViewModel` whose `text.content` is `"Placeholder Name"` and whose `rendererContext…browseEndpoint.browseId` does not start with `UCplaceholder`.
- Add a case to `test_scrub_fixture.py` with a facepile that has a real-looking `UC…` ID and an `avatars` array, scrubbed with `mask=["Jane Doe"]`.

#### 2. `--mask-id` misses base64 copies of the masked ID — `Scripts/scrub-fixture.py:16-20`, `:65-66`

**Issue.** `--mask-id` replaces plain text only. I decoded the real captures and found that `multiSelectParams`, `commandEntityKey`, `serializedShareEntity`, `queueContextParams` and `multiSelectItem` contain the playlist, channel or video ID in base64. Reading the diff by eye, as README step 6 asks, cannot catch an ID hidden that way.

**Scenario.** A real own-playlist or liked-music capture is scrubbed with `--mask-id PLxxxx`. The plain `PLxxxx` is replaced, but every row's `multiSelectParams` and the sort `commandEntityKey` still decode to it.

**Fix.**
- Add `"serializedShareEntity", "multiSelectParams", "multiSelectItem", "queueContextParams", "commandEntityKey"` to `DROP_KEYS`. A grep of `Sources/` shows that no parser reads them; only `formItemEntityKey`, used by the charts parser, must stay.
- In `README.md:70`, step 2, add: "`--mask-id` matches plain text only. For a signed-in capture, base64-decode the remaining `params` values and check them by eye."

#### 3. Token scrubbing and the guard match three exact key names only — `Scripts/scrub-fixture.py:21`, `:55`; `FixturePrivacyTests.swift:10`

**Issue.**
- `TOKEN_KEYS` is `{"continuation", "token", "feedbackToken"}`. `removal_menu` copies the kept history menu item exactly as received.
- Any other per-account token in that item, such as an `undoToken` under `feedbackEndpoint.actions`, would survive the scrub. YouTube web carries one there; for YouTube Music this is unverified.
- The guard regex at `:10` needs exactly one of those three key names, so it would also miss such a token.
- Today no fixture holds any `*Token` key other than these three and the charts `opaqueToken`.

**Scenario.** A real signed-in `history.json` is captured, as R1 plans. The kept `REMOVE_FROM_HISTORY` item carries an account-bound undo token. Both the script and the guard pass it through.

**Fix.**
- In `clean` (`:55`), use `if (key in TOKEN_KEYS or (key.endswith("Token") and key != "opaqueToken")) and isinstance(value, str):`.
- In `placeholder` (`:40`), use `kind = "CONTINUATION" if key in ("continuation", "token") else "FEEDBACK"`.
- Change the guard pattern at `:10` to `#""(continuation|token|(?!opaqueToken")[A-Za-z]*Token)"\s*:\s*"(?!PLACEHOLDER_)"#`.
- Add `"u":{"undoToken":"real"}` to the `leaked` sample at `:30`. It matches the same rule, so the count assertion at `:32` still holds. Confirm that `"opaqueToken": "US"` (`charts.json:1672`) does not match.

#### 4. Continuation tokens are still not bound to an identity, and four new entry points use them (issue-9 L3, widened) — `InnerTubeClient.swift:124-126`, `:133-135`, `:161-163`; `EntityPages.swift:116-117`

**Issue.**
- `playlistContinuation`, `libraryContinuation`, `watchNextContinuation` and `PlaylistPage.sectionsContinuation` (sent through `browseContinuation`) accept any token with any `Credentials?`.
- Library and liked-music tokens are signed-in data. Sending one as a guest, with the guest `X-Goog-Visitor-Id`, links the guest visitor to the account. The `GuestVisitor` generation check exists to prevent that link.
- `playlistContinuation`'s comment (`:122-123`) records that a token sent with the wrong visitor silently returns page 1. A 2.x pager that appends pages would then show duplicate rows, or loop forever if it pages automatically (issue-8 Info 6).

**Fix.**
- Add to `libraryContinuation` and `watchNextContinuation` the same doc comment as on `browseContinuation`: "A token is valid only for the identity that fetched it. Discard paging state on sign-in, sign-out, an account switch or `resetGuestVisitor()`."
- In the 2.x view models, key paging state by identity (auth state plus `authUserIndex`).
- Stop paging when a token repeats or a page brings back only `videoId`s that are already shown.

### Info

1. **Silent failure: a signed-in request that comes back as the guest page reads as an empty account.**
   - Where: `LibraryParser.swift:17-33`, `HistoryParser.swift:3-15`, `LibraryParser.swift:51-58`, `InnerTubeClient.swift:139-145`.
   - This assumes the server can answer a lapsed signed-in session with HTTP 200 and the sign-in `messageRenderer` (with `signInEndpoint`) instead of a 401. In that case library and history become empty pages, the sidebar becomes `[]`, and the UI cannot tell this from a truly empty library.
   - Similarly, a 200 response of `{}` becomes `.notAvailable`, not a retryable error (`AlbumParser.swift:3`, `ArtistParser.swift:3`, `PlaylistParser.swift:4`).
   - Nothing is lost, because these are reads and there is no UI yet.
   - Optional fix: when `credentials != nil` and the section list holds a `messageRenderer` with `button.buttonRenderer.navigationEndpoint.signInEndpoint`, throw `.unauthorized` from `library`, `history` and `sidebarPlaylists`. That reuses the existing 401 handling in `App/AccountModel.swift`.

2. **README wording** (`Fixtures/README.md:81`). "Only YouTube Music-owned (`RDCLAK…`) and artist-owned (`OLAK…`) playlists were captured" is not quite true: `artist.json` also holds two `PLukmsa…` playlists owned by the Radiohead channel. Suggested text: "…and artist-owned (`OLAK…`, and `PL…` playlists of the artist's own channel)".

3. **The masking code has no self-test** (`scrub-fixture.py:65-66`, `:86-96`). Issue-9 added `--mask-id` and `mask_name_links`, but `test_scrub_fixture.py` has no case for either. Add one that scrubs a run `{"navigationEndpoint":{"browseEndpoint":{"browseId":"UCreal"}},"text":"Jane Doe"}` with `mask=["Jane Doe"]` and checks for `UCplaceholder0000000000000`. Add another for `mask_id=["PLreal"]` on `"VLPLreal"`. Low 1 adds the facepile case.

4. **For the 2.4 UI: show server text as plain text.** Album and artist descriptions carry Wikipedia URLs (`related.json:748-763`), and the lyrics are server text. Show them with `Text(_: String)` or `Text(verbatim:)`. Do not use `AttributedString(markdown:)` or `LocalizedStringKey`, which would turn server-chosen markup into clickable links.

### Carry-over tracking

- **Closed:**
  - issue-9 H1. `search.json:1162`, `:1301` and `:1367` are `UCplaceholder0000000000000`, and `:1342` is `Placeholder Podcast`. The script has `mask_name_links` (`scrub-fixture.py:86-96`) and `--mask-id` (`:65-66`, `:218`). The guard rule is at `FixturePrivacyTests.swift:11`, and the README was updated (`:21`, `:70`).
  - issue-9 L1. Emails are now scrubbed before handles (`scrub-fixture.py:67`, test `test_scrub_fixture.py:40-41`). The optional guard rule for a `@placeholder` remnant was not added. The only case left is an address without a dotted TLD, which is acceptable.
- **Changed:**
  - issue-9 L3 has widened. It is now Low 4 above.
  - issue-9 Info 1 (country in fixtures): the IP country `UA` is also inside the artist Show-all `params` (`artist.json:1429`, `:1453`, `:1961`, `:1985`). It is country-level only. Accept, or add `artist.json` to the IP sentence at `README.md:9`.
  - issue-9 Info 3: `Credentials` (no redacting description) now goes into 11 more public methods. The recommendation is unchanged.
  - issue-9 Info 6: `HistoryEntry.feedbackToken` (`EntityPages.swift:139-148`) is now a real public value. The 2.4 remove-from-history mutation must not use the retrying `post`, must never log the token, and must send it only with the credentials that fetched it.
  - issue-8 Info 9 (JSON nesting depth): one parser now recurses over a response, the guide walk at `LibraryParser.swift:61-70`. It is bounded by the decoder's own depth. The recommendation is unchanged.
  - issue-8 Info 6 (repeated continuation): this is now a documented behaviour (page 1 is returned again) and is folded into Low 4.
- **Still open, unchanged:**
  - issue-9 L2: the guard's cookie and key list, and scanning non-JSON files. `Fixtures/` currently holds only `*.json` and `README.md`.
  - issue-9 Info 2, 4 and 5.
  - issue-8 L2 and L3.
  - issue-8 Info 1: the redirect runtime check. The scripted transport still bypasses `RejectRedirects`.
  - issue-8 Info 2, 3, 8 and 10.
  - rename-redwave Info 7.

## Severity summary

| Severity | Count | Next step |
|---|---|---|
| Critical | 0 | — |
| High | 0 | — |
| Medium | 0 | — |
| Low | 4 | L1: facepile owner masking plus a structural guard test. L2: drop the opaque base64 keys. L3: treat every `*Token` key (except `opaqueToken`) as a token in the script and the guard. L4: identity comment on the two new continuation methods, and 2.x paging keyed by identity with repeat detection. L1 to L3 are worth doing before the first real signed-in capture replaces a synthetic fixture. |
| Info | 4 | Out of scope. Info 1 is optional hardening. Info 4 and the carry-over of issue-9 Info 6 go to the 2.4 PR notes. |
