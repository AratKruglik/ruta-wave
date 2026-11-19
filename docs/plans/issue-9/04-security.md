# Security Review: InnerTube models and parsers for home, explore, search and suggestions (backlog 2.2, issue #9)

## Summary
- Critical: 0
- High: 1 (handed to the fix pass)
- Medium: 0
- Out of scope: Low 3, Info 6

No credential path changed:
- `fetch` (`InnerTubeClient.swift:155-158`) is the only router between guest and signed requests. A `nil` `Credentials` always takes `postGuest`, which sends no cookies, no `Authorization` and no `X-Goog-AuthUser`.
- A signed response can never become the guest identity, because only `postGuest` calls `GuestVisitor.accept`.
- The new `[String: any Sendable]` body is checked with `isValidJSONObject` before serialization. A non-JSON value therefore throws `.unexpectedResponse` and cannot raise an Objective-C exception.
- The parsers have no force unwraps and no trapping initializers on server data.
- The fixtures hold no `visitorData`, no real tokens, no cookies and no emails.

The one finding that must be fixed is in the committed test data. `search.json` masks the **names** of two private individuals: a community-playlist author and a podcast host. It still holds their **channel IDs**, plus the playlist and show IDs and cover URLs that point to them. Opening one URL undoes the masking. Nothing is committed yet, so the fix is a few hand edits now. After the docs phase commits and pushes, it would need a history rewrite.

## Checked and clean

| Check | Result |
|---|---|
| Guest path never carries credentials (`InnerTubeClient.swift:155-158`, `:146-153`; `InnerTubeRequest.swift:22-34`, `:72-82`) | `fetch` sends `nil` credentials to `postGuest`, which calls `makeGuest`, which builds on `unauthenticated()`. The only headers are `Origin`, `X-Origin`, `User-Agent` and a `GuestVisitor.validated` visitor ID. `httpShouldHandleCookies = false`, and the session has `httpCookieStorage = nil` and `httpShouldSetCookies = false` (`InnerTubeClient.swift:52-55`). Covered by `DiscoveryClientTests.swift:15-26`, which asserts there is no `Authorization` and no `Cookie`. |
| Signed responses never feed the guest identity (`InnerTubeClient.swift:129-144` vs `:151`) | `post` never calls `GuestVisitor.accept`. Only `postGuest` does, under the generation check (`GuestVisitor.swift:22-27`). The account-linked `visitorData` of a signed response therefore cannot become the guest visitor. |
| Signed requests target the chosen account (`InnerTubeRequest.swift:53-70`) | `X-Goog-AuthUser` comes from `Credentials.authUserIndex`. Cookies are filtered to music domains and to unexpired cookies (`:62`). Covered by `DiscoveryClientTests.swift:34-41` (`SAPISIDHASH` and index `2`) and `:43-46` (401 surfaces as `.unauthorized`). |
| Body construction (`InnerTubeRequest.swift:84-102`) | `context` is assigned after the body is merged (`:86`), so a body key cannot override the client context. The `isValidJSONObject` guard (`:95`) turns NaN or a non-JSON type into `.unexpectedResponse`. Tested at `InnerTubeRequestTests.swift:112-119` (`Double.nan`, `URL`). Every public entry point passes only `String` values or nested `String` arrays. |
| No injection into a URL or header (`InnerTubeClient.swift:81`, `:95`, `:100`, `:107`, `:113`, `:118`, `:122`) | The query, input, continuation tokens, `params`, `browseId` and country appear only as JSON string values. Endpoint names are literals, and the force-unwrapped `URL(string:)` calls (`InnerTubeRequest.swift:16`, `:28`) only ever see those literals. |
| Server-controlled navigation targets (`InnerTubeClient.swift:92-96`) | A `BrowseTarget` taken from a response (a More target, chip or tile) only reaches the `browse` body. It cannot choose another endpoint, host or HTTP method. |
| Parser crash safety (`JSONValue.swift:44-47`; `ChartsParser.swift:7-11`; `ItemParser.swift:194-196`, `:208`) | Array subscripts are bounds-checked. Charts uses `Dictionary(_:uniquingKeysWith:)`, so duplicate mutation IDs cannot trap. `Int.init` on rank text returns `nil` on overflow. The duration regex `\d+(:\d{2})+` is linear. No parser recurses over the response tree. |
| Thumbnail hosts (`AccountInfo.swift:30-38`; `ItemParser.swift:130`) | Every item thumbnail goes through `lastThumbnailURL`, which requires `https` and an allowlisted host. `music.youtube.com/image/mixart` and the `www.youtube.com` tastebuilder images are rejected. |
| Logging (`Blocks.swift:9`; `SearchParser.swift:25`; `ItemParser.swift:38`) | Only static text and the first key name of a skipped block (capped at 64 characters) are logged. Values, titles, queries, tokens and credentials are never logged. There are no `print`, `NSLog` or `dump` calls in `Sources/` or `Tests/`. See Info 2. |
| Fixtures: tokens, visitor and cookies (all 16 `*.json`) | Grep of all 16 files: no `visitorData`, `VISITOR_DATA`, `responseContext`, `trackingParams`, `clickTrackingParams`, `datasyncId`, `channelHandle`, `VISITOR_INFO1_LIVE`, `SIDCC`, `@`-handles or emails. Every `continuation`, `token` and `feedbackToken` is `PLACEHOLDER_*`. The only visitor value in the tests is the synthetic `CgtTWU5USEVUSUMxMjM%3D` (`GuestRequestTests.swift:5`, `ClientTransportTests.swift:7`). |
| Synthetic signed-in fixtures (`home-signed-in.json`, `suggestions-history.json`, `search-empty.json`) | They contain only placeholder IDs, names, queries and tokens. |
| Profile rows (`search.json:1259-1325`) | `blank_profile` blanks the text, `browseId` and avatar URL. |
| Charts country subset (`charts.json:1665-1705`) | Only `ZZ`, `AR`, `DE` and the selected `US` remain. The mutation `id`s decode to a menu key, not user data. The other `USER_CHANNEL` links in Charts are public creators (YouTube Charts, podcast shows). |
| Fixtures not shipped in the app (`Package.swift:11`) | `resources: [.copy("Fixtures")]` is on the test target only. |
| Scrub script (`Scripts/scrub-fixture.py`) | It uses the standard library only. It has no `subprocess` and no `eval`, and it reads and writes only the paths given on the command line. Its gaps are covered in High 1 and Low 1. |
| Configuration and dependencies | `App/`, `project.yml`, `Info.plist` and entitlements are unchanged. There is no `Package.resolved` and no new package; the only dependency is local `../Auth` (`Package.swift:8`). |
| Docs (`docs/01-reverse-engineering.md:248-269`) | No IDs, tokens or visitor values. Section 4.9 matches the code. |
| Live test (`DiscoveryClientTests.swift:114-123`) | It is opt-in through `INNERTUBE_LIVE=1`. The real visitor it receives stays in process memory and is never logged or written. |

## Critical findings (for the fix pass)

None.

## High findings (for the fix pass)

### 1. Masked private individuals can be re-identified from IDs left in `search.json` — `Packages/InnerTube/Tests/InnerTubeTests/Fixtures/search.json:1162`, `:1367` (and related lines)

**Issue.**
- The developer judged two people in the `radiohead` guest search to be private individuals and masked their names with `--mask`: a community-playlist author and a podcast host. The fixtures README says so (`Fixtures/README.md:21`: "Names of private individuals and profile data are masked").
- The same rows still carry identifiers that resolve straight back to those people:

| Row | Line | Value |
|---|---|---|
| Community playlist "Radiohead" by "Placeholder Name" | `:1162` | author channel `UC<redacted-1>` |
| | `:1186` / `:1217` | playlist `VLPL<redacted-4>` / `PL<redacted-4>` |
| | `:1236` / `:1241` | cover `yt3.googleusercontent.com/<redacted-5>…` |
| Podcast "<redacted podcast title>" by "Placeholder Name" | `:1342` | show title `<redacted podcast title>` |
| | `:1367` | host channel `UC<redacted-2>` |
| | `:1385` | show `MPSPPL<redacted-3>` |
| | `:1415` | playlist `PL<redacted-3>` |
| | `:1434` / `:1439` | cover `i.ytimg.com/pl_c/PL<redacted-3>…` |

**Root cause in the script.**
- `--mask` (`scrub-fixture.py:57-58`) replaces only the name string.
- `mask_profile_items` (`:62-69`) blanks only rows whose **own** endpoint is `MUSIC_PAGE_TYPE_USER_CHANNEL`. A channel link inside a subtitle run of a playlist or podcast row is left alone.
- `FixturePrivacyTests` has no rule that ties a masked name to its link.

**Exploit.** Anyone who reads the public repository opens `youtube.com/channel/UC<redacted-1>` or `…/UC<redacted-2>` and gets the name the scrub was meant to hide.

**Why High rather than Medium.**
- Nothing is committed yet. The docs phase commits after this fix pass, so a Medium (not fixed this run) would land in git history and on the public remote. Removing it then means a history rewrite.
- The developer's own masking records that these people were judged private.
- The orchestrator listed channel identifiers as review priority 1.
- It is not Critical: both channels are publicly listed on YouTube, and no credential or account of the user is exposed.

**Prescribed fix.**

1. **Hand-edit `search.json`.** The raw captures lived only in the session scratchpad, so do not plan to regenerate. Keep the `VL`/`PL` pairing and allowlisted thumbnail hosts, so that the parser output (kind `playlist`, non-nil `thumbnailURL`) does not shift:

| Line(s) | Change to |
|---|---|
| `:1162` | `"UCplaceholder0000000000000"` |
| `:1186` | `"VLPLplaceholder0000000000000000001"` |
| `:1217` | `"PLplaceholder0000000000000000001"` |
| `:1236` | `"https://yt3.googleusercontent.com/placeholder-playlist=s192"` |
| `:1241` | `"https://yt3.googleusercontent.com/placeholder-playlist=s1200"` |
| `:1342` | `"Placeholder Podcast"` |
| `:1367` | `"UCplaceholder0000000000000"` |
| `:1385` | `"MPSPPLplaceholder0000000000000000002"` |
| `:1415` | `"PLplaceholder0000000000000000002"` |
| `:1434` and `:1439` | `"https://i.ytimg.com/pl_c/PLplaceholder0000000000000000002/studio_square_thumbnail.jpg"` |

   Then grep the whole `Fixtures/` directory for the six old identifiers and expect no hits: `UC<redacted-1>`, `UC<redacted-2>`, `PL<redacted-4>`, `PL<redacted-3>`, `<redacted-5>`, `<redacted podcast title>`. A package-wide grep showed they occur only in `search.json` and, for `<redacted podcast title>`, in one test.

2. **Update the coupled test.** At `Tests/InnerTubeTests/SearchParserTests.swift:46`, change `$0 != "<redacted podcast title>"` to `$0 != "Placeholder Podcast"`. No other test references these values. `SearchParserTests.swift:18` checks the Radiohead **artist** card, which is unaffected.

3. **Fix the script root cause (`Scripts/scrub-fixture.py`).**
   - Add a pass after `mask_profile_items` in `main` (`:193`). For every dict whose `text == "Placeholder Name"` and that has `navigationEndpoint.browseEndpoint.browseId`, set that `browseId` to `"UCplaceholder0000000000000"`. A masked name then always masks its link.
   - Add a repeatable `--mask-id ID` flag (`action="append"`, next to `--mask` at `:188`). In the string branch of `clean` (`:56-59`), apply `node = node.replace(id, "placeholder0000000000000000")` for each value. Document that IDs are passed without their `VL`/`MPSP` page prefix, so prefixes and URL paths stay well-formed.
   - Do not pass IDs to `--mask`: it would write `"Placeholder Name"` into a `browseId`.

4. **Add a targeted guard rule.** Do **not** add a blanket "no real `USER_CHANNEL` ID" rule: it would fail on legitimate public channels (`charts.json:229`, `:346`, `:1308`, `:1431`, `:1554`; `search.json:1039`).
   - In `FixturePrivacyTests.swift:5-11`, add:
     ```swift
     ("masked name with a live channel link", #""browseId":\s*"(?!UCplaceholder)[^"]*"\s*\}\s*\},\s*"text":\s*"Placeholder Name""#),
     ```
     The fixtures are written with sorted keys, so in a run `browseId` is the last key of `browseEndpoint`, and `text` follows `navigationEndpoint`.
   - Extend the `leaked` sample at `:29` with `,"r":{"navigationEndpoint":{"browseEndpoint":{"browseId":"UCreal"}},"text":"Placeholder Name"}`. The assertion at `:31` requires every pattern to fire on that sample.
   - `home-signed-in.json:127` (a strapline with no link) does not match.

5. **Update the README.** In `Fixtures/README.md:21`, extend the `search.json` row: "Names of private individuals, their channel IDs, and the IDs and covers of their playlist and podcast are placeholders." Mention `--mask-id` in step 2 of "Adding a real signed-in capture" (`:40`).

## Medium recommendations (not fixed this run)

None.

## Out of scope

### Low

1. **The scrub turns an email into `local@placeholder`, and the guard can no longer see it** (`Scripts/scrub-fixture.py:59`; `FixturePrivacyTests.swift:8`).
   - Scenario: a signed-in capture, following the README workflow at `:37-47`, contains `john.doe@gmail.com` in any string. `HANDLE.sub` rewrites it to `john.doe@placeholder`.
   - The guard's email regex needs a dotted TLD, so it passes, and the identifying local part is committed.
   - **Fix:** in `clean`, before `HANDLE.sub` at `:59`, add `node = EMAIL.sub("placeholder-email", node)` with `EMAIL = re.compile(r"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}")`.
   - Add the guard pattern `("masked email remnant", #"[A-Za-z0-9._%+-]+@placeholder"#)`. A handle such as `by @placeholder` has a space before `@` and does not match.
   - Add `"m2":"x@placeholder"` to the `leaked` sample at `:29`.
   - No current fixture contains `@`, so there are no false positives.

2. **The guard misses several identifiers and non-JSON files** (`FixturePrivacyTests.swift:5-11`; `Support/Fixture.swift:15-18`).
   - Cookie names that are not checked: `VISITOR_INFO1_LIVE` (the guest visitor cookie that `visitorData` wraps), `SIDCC`, `YSC` and `PREF`.
   - Keys the script drops but the guard does not enforce: `trackingParams`, `clickTrackingParams`, `serviceTrackingParams`, `loggingContext`.
   - Signed-in keys that are not checked: `datasyncId`, `channelHandle`.
   - `Fixture.all` scans only top-level `*.json`, while `.copy("Fixtures")` bundles every file.
   - Scenario: a hand-trimmed signed-in capture that skipped the script, or a raw `.txt` capture dropped into `Fixtures/`, passes the guard.
   - **Fix:**
     - Add `VISITOR_INFO1_LIVE|SIDCC|YSC|PREF` to the cookie-assignment alternation at `:6`.
     - Add a rule `("tracking or account key", #""(trackingParams|clickTrackingParams|serviceTrackingParams|loggingContext|datasyncId|channelHandle)""#)`.
     - Run `fixtureHoldsNoPersonalData` over every regular file in `Fixture.directory` except `README.md`, through a new `Fixture.allFiles`. `fixtureIsDocumented` keeps using `Fixture.all`.
     - Extend the `leaked` sample at `:29` so the count assertion still holds.
   - Grep confirms none of these occur in the current fixtures.

3. **Continuation tokens are not bound to the identity that fetched them** (`InnerTubeClient.swift:98-101`, `:116-119`; `Page.swift:1-9`). This is latent: there is no production caller yet.
   - `browseContinuation` and `searchContinuation` accept any token with any `Credentials?`.
   - Scenario for the 2.x UI: the user scrolls the signed-in Home, then signs out or switches account while the list stays on screen, then scrolls further.
   - The signed-in token then goes out as a guest request with the guest `X-Goog-Visitor-Id`, or a guest token goes out signed. Google gets a direct join between the guest visitor and the account. The `GuestVisitor` generation check (`GuestVisitor.swift:21-27`) exists to prevent exactly this link.
   - **Fix:** widen the doc comment at `:98` and add one at `:116`: "A token is valid only for the identity that fetched it. Discard paging state on sign-in, sign-out, an account switch or `resetGuestVisitor()`."
   - In the 2.x view models, key paging state by identity (auth state plus `authUserIndex`), as `AccountView`'s `.task(id:)` reload key does.

### Info

1. **Country-level IP data in the fixtures** (`home.json:264`, `:526`, `:647`, `:873`, `:878`; `home-continuation.json:928-1183`; `search.json:662`, `:696`). It shows Ukrainian shelves and a `UA` tastebuilder image. This is country only: there is no IP address, city or coordinate, and grep for IPv4 patterns, `ipcc` and `geo` found nothing. It is documented at `Fixtures/README.md:9`. Accept.

2. **The parser log is now live** (`Blocks.swift:9`, `SearchParser.swift:25`), through all seven public discovery methods.
   - It logs renderer key names at `.notice` with `privacy: .public`, and never values. A signed-in user's log shows which renderer kinds the Home held, which is not personal data.
   - Optional hardening (unchanged from issue-8 Info 5): log the key only if it matches `^[A-Za-z0-9]{1,64}$`, otherwise `"unnamed"`.
   - Correctness note: `keys.min()` can log a sibling key such as `clickTrackingParams`.

3. **`Credentials` has no redacting description** (`InnerTubeClient.swift:22-30`).
   - It is the first public value type that bundles the session cookies. Default `String(describing:)` or reflection prints the `HTTPCookie` objects. Whether that output includes cookie values was not checked here.
   - Nothing interpolates it today.
   - Optional: `extension Credentials: CustomStringConvertible, CustomDebugStringConvertible` that returns `"Credentials(authUserIndex: \(authUserIndex), cookies: <\(cookies.count) redacted>)"`.

4. **Schema drift produces neutral values instead of errors** (silent-failure checklist).
   - `SuggestionsParser.swift:2-24` never throws, so an error or reshaped body gives empty suggestions.
   - `ChartsParser.swift:5-23` gives `countries: []` and `selectedCountry: nil` if the mutations move.
   - Both consequences are cosmetic: an empty dropdown or a missing country picker. Dropped items are already logged by `parseBlocks`.
   - Optional: `parserLog.notice` when `json["contents"]` is absent in suggestions.

5. **Test helpers** (`Support/Fixture.swift:5`, `:16`). The force-unwrapped `resourceURL` is test-only. The `try?` listing could make the parameterized guard pass vacuously, but `fixtureDirectoryIsNotEmpty` (`FixturePrivacyTests.swift:13-15`) catches that. Fine.

6. **2.x handoff: removing a history entry is a mutation.** `SearchHistoryEntry.feedbackToken` (`SearchResults.swift:29-37`) will be sent to a feedback endpoint later. Per issue-8 Info 4, it must not use the retrying `post`. It also must never be logged.

### Carry-over tracking

- **Closed:**
  - issue-8 M1: a secondary-account 401 now sets `authUserIndex = 0` instead of wiping the session (`App/AccountModel.swift:40-46`).
  - issue-8 L1: `expire` sets `.failed(accounts:)` when the session survives (`App/AccountModel.swift:52-56`).
- **Changed:**
  - issue-8 Info 5 (parser log): now has production callers. See Info 2.
  - issue-8 Info 6 (unbounded or repeated continuation token): there are now public entry points (`browseContinuation`, `searchContinuation`) but still no auto-paging caller. The 2.x UI must stop when it gets the same token twice.
  - issue-8 Info 9 (JSON nesting depth): the decode surface grows to seven public methods. Input still comes only from TLS-authenticated `music.youtube.com`. The recommendation is unchanged.
- **Still open, unchanged:**
  - issue-8 L2: discovery `try?` at `InnerTubeClient.swift:66`.
  - issue-8 L3: stale-guard test.
  - issue-8 Info 1: redirect runtime check. The scripted transport still bypasses `RejectRedirects`.
  - issue-8 Info 2, 3, 8 and 10.
  - rename-redwave Info 7.

## Severity summary

| Severity | Count | Next step |
|---|---|---|
| Critical | 0 | — |
| High | 1 | H1: placeholder the private individuals' channel, playlist and show IDs and covers in `search.json` (`:1162`, `:1186`, `:1217`, `:1236`, `:1241`, `:1342`, `:1367`, `:1385`, `:1415`, `:1434`, `:1439`). Update `SearchParserTests.swift:46`. Add the masked-name pass and `--mask-id` to the script, the masked-name-link guard rule, and the README wording. **Fix pass, before the docs phase commits** |
| Medium | 0 | — |
| Low | 3 | L1: whole-email scrub before the handle substitution, plus a guard rule. L2: extend the guard's cookie and key list and scan non-JSON files. L3: document that a token belongs to one identity, and key 2.x paging state by identity |
| Info | 6 | Out of scope. Info 3 is optional hardening; Info 6 goes to the 2.x PR notes |
