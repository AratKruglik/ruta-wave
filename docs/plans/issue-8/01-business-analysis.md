# Business Analysis: InnerTube client version discovery, continuation paging and error handling (backlog 2.1, issue #8)

## Sources

| Tag | Source | Notes |
|---|---|---|
| [ISSUE] | GitHub issue #8 | **Could not be fetched.** WebFetch returned 404 (the repository is private) and no `gh` CLI was available in this phase. The issue text is therefore **not** verified. The requirements below come from the backlog row that links to the issue and from the project docs. |
| [BL] | `docs/06-backlog.md` row 2.1 (line 41) | "`INNERTUBE_CLIENT_VERSION` from the page + cache, `Page<T>`/`continuation`, errors (401 → sign-in, retry, unknown blocks skipped); works for guests too". Depends on 1.2 and 1.4 (both merged). |
| [RM] | `docs/03-roadmap.md` stage 2 | Line 50: fetch the version and cache it. Line 53: `Page<T>` paging. Lines 61–62: 401 → sign-in, network retry, unknown blocks skipped and logged. |
| [ARCH] | `docs/02-architecture.md` | §5.1 (lines 157–158): `clientVersion` comes from `ytcfg` `INNERTUBE_CLIENT_VERSION`. §5.3: the client follows `continuation`, and `Page<T>` is in Models. §5.3 (lines 193–196): parsers skip unknown blocks. §6 (lines 204–205): "the automatic return to sign-in arrives in 2.1". |
| [RISK] | `docs/05-risks-and-scope.md` | Risk 2: format changes, so parsers tolerate unknown blocks. Risk 8: "on a 401 re-read cookies from the web view store; if that does not help, show the sign-in window". |
| [PRD] | `docs/00-prd.md` | 7.1: cold start ≤ 2 s *with a cached client version*. 7.2: unknown blocks skipped and logged, and a screen never fails completely. 7.3: cookies never in logs. |
| [UI] | `docs/08-ui-spec.md` | Line 202: a shelf that fails to parse is skipped ("2.1 rule"). Line 458: "401 → session expired flow of 2.1". Line 459: offline banner (assigned to 4.7). Line 122: next page loads 600 pt before the end (UI, 4.x). |
| [CODE] | Current codebase | See "Codebase impact". |

There is no `CLAUDE.md` or `README.md` at the repo root. Conventions are inferred from existing code and from earlier plan folders.
**Documentation gap:** `docs/01-reverse-engineering.md` says nothing about `continuation` or `ytcfg`. The continuation wire format is not documented anywhere in the project.

## Executive summary

Backlog 2.1 hardens the InnerTube client, which every later Stage 2 and Stage 4 row builds on. It has three parts:
1. Replace the hard-coded `clientVersion` with one discovered from the `music.youtube.com` page and cached across launches.
2. Add a generic paged-result type and a way to request the next page by continuation token.
3. Add an error model with bounded retries for transient failures, an automatic "session expired → sign in" flow for signed-in users, and a reusable rule that skips and logs unknown response blocks.

All of it must work the same for guest (unauthenticated) requests.

## Functional requirements

1. **FR-1 Client version discovery** [BL][RM:50][ARCH §5.1]. The app reads `INNERTUBE_CLIENT_VERSION` from the `music.youtube.com` page's `ytcfg` and uses it as `context.client.clientVersion` for all InnerTube requests, both signed-in and guest. This replaces the fixed constant in `InnerTubeRequest` (the code marks it `shortcut: … replaced by page discovery in 2.1`).
2. **FR-2 Version cache and fallback** [BL][RM:50][PRD 7.1].
   - The discovered version persists across launches. The fallback order is: discovered (this launch), then cached (previous launch), then built-in.
   - Discovery never blocks or delays the first InnerTube request. A cold start with a cached version must not wait on the page fetch.
   - A discovery failure (network, redirect, parse, invalid format) is silent and keeps the previous value.
3. **FR-3 Continuation paging** [BL][RM:53][ARCH §5.3].
   - A generic page result carries the items plus an optional continuation token. When the token is absent, there are no more pages.
   - The client can request the next page with a token, for guest and signed-in sessions alike.
   - A shared helper extracts the token from the known response shapes, so 2.2 and 2.3 parsers reuse it instead of each re-implementing it.
4. **FR-4 Error model and transient retry** [BL][RM:61–62].
   - Errors are classified at least as: unauthorized (session invalid), transient (network failure, timeout, 5xx, possibly 429), and permanent (other 4xx, unparseable response).
   - Transient failures on read requests (`browse`, `search`, `next`, suggestions, `account_menu`, continuation) are retried a small, bounded number of times with a delay.
   - Permanent errors are not retried.
   - The retry policy does not apply to non-idempotent mutations by default. Those arrive in 2.4: `playlist/create`, `browse/edit_playlist` and others.
5. **FR-5 Session-expired flow (401 → sign-in)** [BL][RM:61][ARCH §6][UI:458].
   - When a signed-in request is rejected as unauthorized, the app leaves the signed-in state and presents sign-in with a "session expired" explanation, without the user pressing Sign out.
   - Guest requests never trigger this flow.
   - Whether cookies are first re-read from the WebKit store is an **open question**. See Conflict C1.
6. **FR-6 Skip and log unknown blocks** [BL][RM:62][ARCH §5.3][PRD 7.2][UI:202].
   - A reusable rule for parsers: an unrecognized or unparseable block in a list of renderers is dropped, the rest of the page is kept, and a log entry records it.
   - The log entry names the renderer key only, never values, tokens, cookies or personal data [PRD 7.3].
7. **FR-7 Existing callers adopt the new behaviour** [CODE].
   - `AccountModel`, which loads the account screen, surfaces the unauthorized case so FR-5 fires, instead of swallowing every error with `try?`.
   - `GuestModel` and `connectAsGuest` use the discovered version and the retry policy.

## Non-functional requirements

- **Performance:**
  - Cold start to the first InnerTube response must not include the page fetch when a cached version exists [PRD 7.1].
  - Retries are bounded, so a dead network fails within a few seconds rather than hanging a screen.
- **Security:**
  - The version-discovery page fetch is unauthenticated: no `Cookie`, `Authorization` or `X-Goog-AuthUser` headers, the same rule as guest requests [ARCH §5.1]. This also makes it work for guests.
  - The discovered version is validated against a strict format before it is cached or put in a request body, the same way `GuestVisitor.validated` guards `visitorData`.
  - The existing redirect rejection (`RejectRedirects`) stays in place.
- **Privacy / Compliance:**
  - Logs (skipped blocks, retries, 401s) never contain cookies, SAPISID hashes, visitorData, continuation tokens, account names or response bodies [PRD 7.3].
  - The cached client version is not a secret. `UserDefaults` is an acceptable store, unlike cookies.
- **Reliability:** one unknown shelf never fails a whole page [PRD 7.2].
- **Testability:** retry, 401 and discovery behaviour must be verifiable with Swift Testing without network access. See constraint K5.

## User stories (Gherkin)

### Story 1: Requests use the live client version
**As a** listener (signed in or guest)
**I want** the app to identify itself with the client version YouTube Music currently serves
**So that** requests keep working when Google rolls the web client forward

**Acceptance criteria:**
- Given the `music.youtube.com` page contains `"INNERTUBE_CLIENT_VERSION":"<v>"` and `<v>` passes format validation, When discovery runs, Then later InnerTube requests (guest and signed-in) send `context.client.clientVersion = <v>`, and `<v>` is persisted.
- Given a version was cached on a previous launch, When the app cold-starts, Then the first request uses the cached version without waiting for discovery.
- Given no cached version and discovery fails (offline, redirect to a consent page, missing key, invalid format), When a request is sent, Then it uses the built-in version and no error is shown to the user.
- Given the page contains a malformed version (e.g. containing quotes, spaces or control characters, or too long), When discovery runs, Then the value is rejected and the previous version is kept.
- Given discovery runs, When the page request is built, Then it carries no `Cookie`, `Authorization` or `X-Goog-AuthUser` header.

### Story 2: Long lists load page by page
**As a** developer of the 2.2/2.3 parsers and 4.x screens
**I want** a page result with an optional continuation token and a "next page" request
**So that** long playlists, library lists, search results and home shelves can be paged without each parser reinventing it

**Acceptance criteria:**
- Given a response fixture whose list ends with a continuation token in one of the supported shapes, When the shared helper reads it, Then it returns that token.
- Given a response with no continuation, When the helper reads it, Then it returns no token, and the page reports that there are no more pages.
- Given a token, When the client requests the next page as a guest, Then the request is a guest request (no credentials) that carries the token and the current client version.
- Given a token, When the client requests the next page while signed in, Then the request is signed (SAPISIDHASH, `X-Goog-AuthUser`) and carries the token.

### Story 3: Transient failures are retried, permanent ones are not
**As a** listener on a flaky network
**I want** brief network glitches to be retried automatically
**So that** a screen does not fail on a single dropped packet

**Acceptance criteria:**
- Given a read request whose first attempt fails with a network error or a 5xx and whose next attempt succeeds, When it is sent, Then the caller receives the successful response.
- Given a read request that keeps failing transiently, When the retry limit is reached, Then the caller receives a transient error, and the total number of attempts equals the configured bound.
- Given a 400/404 or an unparseable body, When a request is sent, Then it is not retried.
- Given the task is cancelled mid-retry, When cancellation happens, Then no further attempts are made.

### Story 4: Expired session returns me to sign-in
**As a** signed-in listener whose Google session expired or was revoked
**I want** the app to tell me and offer sign-in
**So that** I am not left on a broken screen with only Retry / Sign out

**Acceptance criteria:**
- Given the user is signed in, When an authenticated request returns the unauthorized status, Then the session leaves `.signedIn`, the user sees a "session expired" message and sign-in, and the stale Keychain entry is no longer used.
- Given several concurrent requests all return unauthorized, When they complete, Then the flow runs once.
- Given a request was sent before a sign-out, sign-in or account switch, When its unauthorized response arrives afterwards, Then it is ignored and the new session is not affected.
- Given the user is a guest, When a guest request returns 401/403, Then the sign-in flow is not triggered and the caller sees an ordinary error.
- *(Only if C1 is resolved as "re-read first")* Given the WebKit store holds fresher valid cookies, When a 401 occurs, Then the cookies are refreshed into the Keychain, the request is retried once, and sign-in is shown only if that retry also fails.

### Story 5: Unknown blocks do not break a page
**As a** listener
**I want** a page to show everything it can understand when Google adds a new kind of block
**So that** one unknown shelf does not blank the whole screen

**Acceptance criteria:**
- Given a list of renderer blocks where one block has an unknown renderer key, When it is parsed with the shared rule, Then the known blocks are returned in order and the unknown one is dropped.
- Given a block is dropped, When the log entry is written, Then it contains the renderer key and no values from the block.

## Data model sketch

- **ClientVersion** (value). Holds the version string. Has a validity rule (strict format, bounded length) and a source (discovered / cached / built-in). There is one process-wide current value, shared by every `InnerTubeClient` instance. A persisted copy survives launches. A timestamp is needed only if a refresh TTL is adopted (open question 3).
- **Page of T** (generic). Items of T plus an optional continuation token. 2.2/2.3 parsers produce it, and the 4.x lists consume it.
- **ContinuationToken** (opaque string). Treated as untrusted response data: never logged, and sent back to the server only as-is.
- **InnerTubeError** (existing enum, extended). Today it has `missingSAPISID`, `httpStatus(Int)` and `unexpectedResponse`. It must also distinguish unauthorized, transient (network, timeout, 5xx) and permanent cases, so callers and the retry policy can tell them apart. Note that `httpStatus(Int)` already exists and is `Equatable`, so existing tests reference it.
- **AuthSession.State** (existing, in the Auth package). Today it has `signedOut`, `signedIn` and `keychainUnavailable`. It needs a way to express "session expired": either a new state, or a transition to `signedOut` plus a flag the UI uses to present sign-in with a message. That choice is for the dev phase. It needs an identity / generation marker so stale 401s can be told apart (see `GuestVisitor` generation for the existing pattern).

## API contract sketch

**HTTP (outbound, to Google):**
- `GET https://music.youtube.com/`. Unauthenticated, with the same `User-Agent` / `Origin` as guest requests, no cookies, no redirects followed. The response is HTML, and the value is extracted from the `ytcfg` key `INNERTUBE_CLIENT_VERSION`. **Edge:** EU users may get a 302 to `consent.youtube.com`. Redirects are rejected, so discovery fails and the fallback is used.
- `POST https://music.youtube.com/youtubei/v1/browse?prettyPrint=false` (also `search`, and `next` where applicable), as a continuation request. The body has the usual `context.client`, and the token goes either as query parameters (`ctoken=<t>&continuation=<t>&type=next`) or as a body field `continuation: <t>`. **[unverified]** Which form WEB_REMIX accepts per endpoint today must be confirmed with a live capture in the dev phase. The response shape is also **[unverified]**: the next token can appear as `continuations[].nextContinuationData.continuation` (older list shape) or as `continuationItemRenderer.continuationEndpoint.continuationCommand.token` (newer shape). Fixtures for both must have personal data removed.

**Swift public surface of the InnerTube package (prose only, no signatures):**
- A process-wide way to trigger version discovery, for example once at launch in the background. Requests read the current version implicitly.
- A next-page call that takes a token and the same auth context (guest, or cookies + index) as the first-page call.
- Errors that callers can match on for "unauthorized" versus "try again" versus "permanent".
- A parsing helper for "map these renderer blocks, skipping and logging unknown ones", for 2.2+ parsers.

**Auth package surface:**
- A way for the app to report "this signed-in request was unauthorized" that is idempotent for concurrent reports and ignores reports from an older session generation. It ends in the session-expired state that the UI turns into a sign-in prompt.

## Codebase impact

| File | Impact |
|---|---|
| `Packages/InnerTube/Sources/InnerTube/InnerTubeRequest.swift` | The `clientVersion` constant (line 7, marked `shortcut`) becomes the built-in fallback. `attachPayload` reads the current shared version. A continuation variant of `make`/`makeGuest`, or a token parameter, is needed. The `body: [String: String]` type may need to allow the token placement. |
| `Packages/InnerTube/Sources/InnerTube/InnerTubeClient.swift` | Extend `InnerTubeError`. `send` maps statuses and `URLError`s to the new classes and applies retry for reads. Add discovery and next-page entry points. `connectAsGuest` / `accountMenu` / `accountSwitcher` get retry. |
| New: shared version store (InnerTube) | Process-wide plus persisted. Follows the `GuestVisitor.shared` pattern, a lock-protected singleton. |
| New: `Page` model and continuation helper, skip-unknown parsing helper, logger (InnerTube) | No `Logger` exists in the codebase yet. |
| `Packages/Auth/Sources/Auth/AuthSession.swift` | Session-expired transition with a generation guard. Possibly a cookie re-read from `WKWebsiteDataStore.default().httpCookieStore` (only if C1 says so). |
| `App/AccountModel.swift`, `App/AccountView.swift` | Stop swallowing unauthorized errors with `try?`, and show "session expired" plus sign-in. Today `.failed` only offers Retry / Sign out (ARCH §6, lines 204–205). |
| `App/RedwaveApp.swift` | Trigger version discovery at launch, off the critical path. Route the expired state to the sign-in UI. It already resets `GuestVisitor` on sign-in changes. |
| `App/GuestModel.swift` | Benefits from retry. No 401 → sign-in behaviour. |
| `Packages/InnerTube/Tests/InnerTubeTests/*` | New tests: version extraction and validation, fallback order, continuation token extraction (both shapes, synthetic fixtures), error classification, retry bound, skip-unknown. Existing `InnerTubeRequestTests` / `GuestRequestTests` assert the body shape and must keep passing. |
| `Packages/Auth/Tests/AuthTests/AuthSessionTests.swift` | Expired transition, idempotency, stale-generation drop. |

### Codebase constraints
- **K1. Many client instances.** `AccountModel` and `GuestModel` each create `InnerTubeClient()`, so version state cannot live on the actor instance. It must be process-wide, as `GuestVisitor.shared` is.
- **K2. Redirects are rejected** by `RejectRedirects`. That is fine for security, but it means consent-page redirects make discovery fail, so the fallback is mandatory.
- **K3. Errors are swallowed today.** `AccountModel` uses `try?` on both calls, and `GuestModel` collapses errors to `.failed`. The 401 flow is impossible without changing these callers.
- **K4. The 401 flow crosses modules.** InnerTube depends on Auth (`import Auth` in `InnerTubeRequest`), not the other way round. The app layer (or a callback) must connect "InnerTube saw unauthorized" with "AuthSession expires". InnerTube must not own session state.
- **K5. No test seam.** `InnerTubeClient.init()` builds its own ephemeral `URLSession`, and nothing can be injected. Current tests cover only request builders. Retry, 401 and discovery acceptance criteria need some way to stub the transport. The mechanism is left to dev.
- **K6. No logging infrastructure.** `GuestVisitor` imports `os` only for the lock. FR-6 introduces the first logger, which must respect PRD 7.3.
- **K7. Body typing.** `attachPayload` accepts `[String: String]` only. That is enough for a string token, but it limits other continuation payloads.
- **K8. The account-switch fallback** (`AccountListItem.fallbackIndex`) already changes `authUserIndex` mid-load. A 401 from the pre-switch index must not expire the session (stale-generation rule).

## Conflicts and gaps

- **C1. The 401 path has two versions.**
  - [RISK #8] says: re-read cookies from the WebKit store first, and show sign-in only if that fails.
  - [BL], [RM:61] and [ARCH §6] say: 401 goes straight to sign-in.
  - `AuthSession` has no re-read API today. The WebKit store may hold rotated cookies (Google rotates `__Secure-*PSIDTS`), so re-reading could save a sign-in. It adds scope in the Auth package and a write to the Keychain.
  - **Not resolved; stakeholder decision needed.**
- **C2. The roadmap "Done when" is out of reach for 2.1.** [RM] Stage 2's "Done when" requires parser tests and fetching home, search and a playlist. Parsers are 2.2/2.3, so 2.1 cannot meet that. The acceptance criteria above are scoped to 2.1 only. Page-level verification against real content moves to 2.2.
- **C3. Some UI spec §14 items belong to other rows.** [UI:459] The offline banner with `NWPathMonitor` retry-on-reconnect is backlog 4.7. The full-page and inline error UI is 4.x. **Out of scope for 2.1.** 2.1 surfaces the expired session only through `AuthSession` and the existing account and guest screens.
- **C4. "401" may not be the real signal.** Expired WEB_REMIX sessions may answer 401, 403, or 200 with signed-out content (no account in `account_menu`). **[unverified]** The dev phase should confirm with an expired or revoked session capture, and decide whether 403 also counts as unauthorized.
- **G1. Continuation wire format is not documented.** See the API sketch. The dev phase should add a short note to `docs/01-reverse-engineering.md` once it is confirmed.
- **G2. Retry under a server rejection of an old version.** If Google rejects a stale client version (a 400 with a specific message is possible), should that trigger an immediate rediscovery? Not stated in any source. Suggested: treat it as permanent in 2.1 and revisit if observed.

## Edge cases & error scenarios

- The page fetch returns a consent redirect, a captcha or HTML without `ytcfg`, so the fallback is used and nothing reaches the user.
- The discovered version string contains injection characters or is absurdly long, so it is rejected.
- Discovery finishes while requests are in flight. Those requests keep their old version, and later ones use the new one. No request is reissued.
- Concurrent discovery triggers (several clients start at once) result in at most one page fetch in flight.
- Concurrent 401s from parallel `accountMenu` + `accountSwitcher` result in one expiry.
- A 401 arrives after the user has signed out, signed in again or switched account, and is dropped (generation guard).
- A 401 arrives while the sign-in sheet is already open (for example during Add account), and the flow is not shown twice.
- A 401 arrives while `.keychainUnavailable` + "Continue without signing in" is active. That is a guest, so no sign-in flow.
- A guest gets a 401/403 (for example a blocked visitorData). Suggested: reset the visitor and surface an ordinary error, without the sign-in flow.
- A 429 rate limit: retry with a longer delay, or treat it as permanent? Bounded either way. The policy is set in the dev phase.
- The task is cancelled during a retry backoff and stops immediately (matches the `Task.isCancelled` checks in the existing models).
- A continuation token repeats (the server returns the same token twice). The consumer must not loop forever. The guard is a note for 2.2/4.x consumers.
- An empty page with a token, or items with no token, is handled as normal.
- A continuation request after a sign-out uses a token obtained by the old identity. The token is opaque, so the request is sent under the current identity. A failure is ordinary.

## Risks & dependencies

- Depends on 1.2 (client, signing) and 1.4 (guest requests and visitor). Both are merged.
- Blocks 2.2, 2.3 and 2.4 (Page, errors, skip rule) and 4.x (expired flow, paging).
- Google can change `ytcfg` markup at any time. The fallback chain limits the impact to "an older version is sent", which usually still works.
- Retrying mutations by mistake could create duplicate playlists in 2.4. The policy must default to reads only.
- If C1 adds a cookie re-read, it touches the Keychain write path and the WebKit store (threat-model note from 1.1: the store holds Google-wide cookies).

## Open questions for stakeholders

1. **(Blocking, C1)** On a 401, should the app first re-read cookies from the WebKit store and retry once (risk #8), or go straight to the sign-in flow (backlog, architecture §6)?
2. **(C4)** Should 403, or a 200 `account_menu` with no signed-in account, also count as "session expired", or only an HTTP 401?
3. How long is a cached client version trusted? Options: refresh in the background on every launch, or refresh only when older than N hours. The sources say only "cache".

## Estimated complexity

**Medium.** Several focused changes across two packages and the app layer, plus new tests:
- InnerTube: request builder, client, error enum, new version store, Page and continuation helper, skip rule, logger.
- Auth: the expired transition.
- App: `AccountModel`, `AccountView`, `RedwaveApp`, `GuestModel`.
- A transport test seam.

If C1 adds the cookie re-read, Auth-side scope grows. It stays medium.
