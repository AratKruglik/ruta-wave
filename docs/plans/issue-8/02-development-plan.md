# Development plan: InnerTube client version discovery, continuation paging and error handling (backlog 2.1, issue #8)

Pass: PLAN. No source code has been changed. Sources:
- `_brief.md`
- `01-business-analysis.md`
- GitHub issue #8, read with `gh issue view 8 --json`. It has no comments.
- The user decisions passed to this phase. They override the spec and the issue.
- The current code in `Packages/InnerTube`, `Packages/Auth` and `App/`.

## 0. Issue vs spec

`gh` worked. The issue text differs from the BA spec, which was written without the issue, in these points:

| # | Issue says | Spec / decision | Plan follows |
|---|---|---|---|
| I1 | On a 401, re-read cookies from the web view store and retry once. Sign-in comes only if the retry is still 401. | User decision 1: go straight to the expired state and the sign-in prompt. No re-read, no retry. | Decision 1 |
| I2 | Unit test for "the 401 retry path". | The retry no longer exists. | The test becomes "401 → `.unauthorized` (not retried) → session expired", split across the InnerTube and Auth tests |
| I3 | "This replaces the Retry / Sign out error screen introduced in 1.2." | Spec: 401 → sign-in. | Only a 401 goes to sign-in. Network failures and other non-401 errors keep the existing `.failed` Retry / Sign out screen, because it is still the right screen for them. |
| I4 | "provide the helper **and the logging category**" | Spec mentions the logger but no category. | One `os.Logger`, subsystem `dev.kruhlyk.redwave`, category `parser` |
| I5 | Typed errors: "unauthorized, network (with a retry policy), malformed response" | Spec: unauthorized / transient / permanent. | `.unauthorized`, `.network(URLError.Code)`, `.unexpectedResponse` (malformed), and the existing `.httpStatus(Int)` for every other status |
| I6 | Done when: `swift test` in `Packages/InnerTube` passes | Spec also changes Auth. | `swift test` in both `Packages/InnerTube` and `Packages/Auth`, plus the app build |
| I7 | "Guest path: `visitorData` handling keeps working through paging and retries" | Implied by the spec | An explicit test (§6) |
| I8 | Branch `feature/innertube-paging-errors` | The pipeline branch is `feature/issue-8` | Noted only. The branch is not renamed. |
| I9 | Done when: "a cold start with a cached version sends no extra page request **before** the first API call" | User decision 3: discovery runs in the background on every launch. | The first API call never waits for discovery. The background `GET /` can race with it on the wire, but it never sits on the first call's critical path. The criterion is read as "not blocking". See R5. |

User decisions 2 (only HTTP 401 means "session expired") and 3 (no TTL, background refresh on every launch) do not contradict the issue.

## 1. Project shape

| Aspect | Value |
|---|---|
| Project system | XcodeGen (`project.yml`, `sources: [App]`). `Redwave.xcodeproj` is generated. `Tunewave.xcodeproj` is a stale leftover; ignore it and always pass `-project Redwave.xcodeproj`. |
| Target and platform | One macOS app target `Redwave`, macOS 14.0. No extensions. |
| Swift | App `SWIFT_VERSION 6.0`. Packages use tools 6.0, so Swift 6 language mode with strict concurrency. No default actor isolation. |
| UI and state | SwiftUI app lifecycle, Observation (`@MainActor @Observable`) |
| Persistence | Keychain (`KeychainStore` / `KeychainItem`) for the session, `UserDefaults` for `authUserIndex` |
| Navigation | A `switch session.state` in `RedwaveApp`, plus sheets |
| Modules | Local SPM packages under `Packages/`. `InnerTube` depends on `Auth`, not the other way round. |
| Localization | No String Catalog. English literals, as in 1.2–1.4. |
| Design system | None. Uses system styles. |
| Tests | Swift Testing, in the packages only. The app has no test target. |

New files go into the packages only, and SPM picks them up automatically. There are no new files under `App/`, so there is no `xcodegen generate` and no `project.pbxproj` edit.

## 2. Files

### Create

| File | Tag | Purpose |
|---|---|---|
| `Packages/InnerTube/Sources/InnerTube/ClientVersion.swift` | service | Process-wide current `clientVersion`, persisted in `UserDefaults`. Mirrors `GuestVisitor` (D1). |
| `Packages/InnerTube/Sources/InnerTube/Page.swift` | model | `public struct Page<Item: Sendable>: Sendable`, plus the continuation-token helper on `JSONValue` (D4) |
| `Packages/InnerTube/Sources/InnerTube/Blocks.swift` | service | Skip-and-log helper for renderer lists and the `parser` logger (D5) |
| `Packages/InnerTube/Tests/InnerTubeTests/ClientVersionTests.swift` | test | Extraction from a fixture page, validation, cache and fallback order, page request headers |
| `Packages/InnerTube/Tests/InnerTubeTests/ClientTransportTests.swift` | test | Error mapping, retry bound, no retry for permanent errors and 401, cancellation, paging over two fixture pages (guest), signed continuation request |
| `Packages/InnerTube/Tests/InnerTubeTests/PageTests.swift` | test | Continuation token in both shapes and with none; the skip-unknown rule and its log key |

### Modify

| File | What changes and why |
|---|---|
| `Packages/InnerTube/Sources/InnerTube/InnerTubeRequest.swift` | `clientVersion` constant → `ClientVersion.builtIn`, and the `shortcut` comment is removed. `attachPayload` reads `ClientVersion.shared.current`. New `static func makePage() -> URLRequest`: `unauthenticated(URL(string: origin + "/")!)` with `httpMethod = "GET"`. No `Cookie`, `Authorization`, `X-Goog-AuthUser` or `X-Goog-Visitor-Id`, by construction. |
| `Packages/InnerTube/Sources/InnerTube/InnerTubeClient.swift` | Extend `InnerTubeError` (D3). Add an internal transport seam and retry (D2). `send` is split into `data(for:)` (status mapping and retry) and `send` (JSON). `post` becomes `internal`. New internal `postGuest` (D4). `connectAsGuest` is rewritten on top of `postGuest`. New `public func refreshClientVersion() async` (D1). |
| `Packages/Auth/Sources/Auth/AuthSession.swift` | `public private(set) var isSessionExpired = false`. New `public func expireSession(cookies: [HTTPCookie]) async` (D6). `completeSignIn` clears `isSessionExpired`. |
| `App/AccountModel.swift` | Stop swallowing errors with `try?`. On `InnerTubeError.unauthorized` from either call, call `await session.expireSession(cookies:)` and return (D7). |
| `App/GuestView.swift` | When `session.isSessionExpired` is set, show "Your session expired. Sign in again." and present the sign-in sheet once on appear. `GuestContent` gets an `isSessionExpired: Bool` parameter, and a new `#Preview("Expired")` is added (D7). |
| `App/RedwaveApp.swift` | In `init`, add `Task.detached(priority: .utility) { await InnerTubeClient().refreshClientVersion() }` next to the existing `LegacyStores` task (D1). |
| `Packages/Auth/Tests/AuthTests/AuthSessionTests.swift` | Tests for the expiry (§6). |
| `docs/02-architecture.md` | §5.1: one sentence on the version cache, fallback and background refresh. §6 item 1: replace "the automatic return to sign-in arrives in 2.1" with the 2.1 behaviour (401 → wipe → guest screen with "session expired" and the sign-in sheet). |
| `docs/05-risks-and-scope.md` | Risk 8 mitigation: "on a 401 the session is dropped and sign-in is shown (no cookie re-read; decided in 2.1)". |

### Do not change

- `GuestModel.swift`. It gets the discovered version and the retry through `connectAsGuest`. Its error collapse to `.failed` is correct for guests, because a guest 401 must not trigger sign-in.
- `AccountView.swift`. The `.failed` branch stays for non-401 failures. On expiry the state becomes `.signedOut`, so `AccountView` disappears.
- `SignInView.swift`, `SignInRules.swift`, `KeychainItem.swift`, `JSONValue.swift`.
- Every `Package.swift`, `project.yml`, `Info.plist`, entitlements and the privacy manifest. There are no new dependencies, capabilities or keys. `UserDefaults` is already used by `AuthSession`, and the privacy-manifest reason for it is unchanged in scope (the app's own defaults).

## 3. Implementation order

1. `InnerTubeError` cases and `isTransient` (D3).
2. `ClientVersion.swift`, then the `InnerTubeRequest` changes (`attachPayload`, `makePage`).
3. The `InnerTubeClient` seam, `data(for:)` with retry, `postGuest`, `connectAsGuest`, `refreshClientVersion`.
4. `Page.swift` and `Blocks.swift`.
5. InnerTube tests. Run `swift test` in `Packages/InnerTube`.
6. `AuthSession.expireSession` and the Auth tests. Run `swift test` in `Packages/Auth`.
7. App: `AccountModel`, `GuestView`, `RedwaveApp`. Build: `xcodebuild -project Redwave.xcodeproj -scheme Redwave -destination 'platform=macOS' -quiet build`.
8. Docs (architecture §5.1/§6, risk 8).

## 4. Design decisions

### D1. Client version: a `GuestVisitor`-style process-wide store with background refresh

```swift
final class ClientVersion: Sendable {
    static let builtIn = "1.20261115.14.00"
    static let shared = ClientVersion(defaults: .standard)
    private static let key = "innerTubeClientVersion"
    private let defaults: UserDefaults          // UserDefaults is Sendable on macOS 14 SDK; if not, nonisolated(unsafe) + note
    private let lock: OSAllocatedUnfairLock<String>
    init(defaults: UserDefaults)                 // lock initial = validated(defaults.string(forKey:)) ?? builtIn
    var current: String                          // lock.withLock { $0 }
    func accept(_ raw: String?)                  // validated → set in memory + defaults; invalid → ignored
    static func validated(_ raw: String?) -> String?   // ^[0-9]+\.[0-9]{8}\.[0-9]{2}\.[0-9]{2}$ (whole match, ≤ 32 chars)
    static func extract(fromPage html: String) -> String?  // first match of "INNERTUBE_CLIENT_VERSION":"([^"]{1,64})", then validated
}
```

- **Why process-wide (K1).** `AccountModel` and `GuestModel` each own an `InnerTubeClient`, so the version cannot live on the actor.
- **No TTL (decision 3).** There is no timestamp.
- **Fallback order.** The fallback is discovered (this launch), then cached, then built-in. `init` reads the cache and `accept` overwrites both the memory and the cache, so the order holds automatically.
- **Cold start.** `attachPayload` reads `current` synchronously from the lock and never awaits discovery.
- **Discovery trigger.** `InnerTubeClient.refreshClientVersion()` is public, non-throwing, and swallows every error:
  ```swift
  guard let data = try? await data(for: InnerTubeRequest.makePage()) else { return }
  ClientVersion.shared.accept(ClientVersion.extract(fromPage: String(decoding: data, as: UTF8.self)))
  ```
- **Called once per process** from `RedwaveApp.init` in a detached utility task, next to `LegacyStores.remove()`. Because there is one trigger, there is no in-flight dedupe. `.task` on `WindowGroup` was rejected because it would run once per window.
- **Consent redirect.** A redirect to the consent page arrives as a 302, because `RejectRedirects` returns `nil`. It becomes `httpStatus(302)` and is ignored silently (K2).
- **Malformed values.** The strict format rejects quotes, spaces, control characters and over-long values, and the previous value is kept.
- **Strictness tradeoff.** The regex matches today's format exactly. If Google changes the shape, discovery degrades to the cached or built-in value, which is the safe direction (R4).

### D2. Transport seam and bounded retry for reads

```swift
typealias Transport = @Sendable (URLRequest) async throws -> (Data, URLResponse)
public init()                                         // unchanged session config; transport = { try await session.data(for: $0) }, retryDelay = .milliseconds(500)
init(transport: @escaping Transport, retryDelay: Duration)   // internal; tests pass .zero
static let maxAttempts = 3
```

`data(for:)` behaves as follows:
- **Attempts.** It runs up to 3 attempts and sleeps `retryDelay * attempt` between them, so 0.5 s and then 1 s. `Task.sleep` throws `CancellationError`, so a cancel during the backoff stops at once.
- **Same request.** Every attempt sends the same `URLRequest`. The guest visitor header and snapshot generation, and the signed headers, stay fixed across retries (I7).
- **Status mapping.**
  - `401` → `.unauthorized`
  - other non-2xx → `.httpStatus(n)`
  - non-HTTP response → `.unexpectedResponse`
  - `URLError` with `code != .cancelled` → `.network(code)`
  - `URLError(.cancelled)` and `CancellationError` → rethrown unchanged, so they are never retried
- **Retried:** only `.network` and `.httpStatus(500...599)`.
- **Not retried:**
  - `.unauthorized`, so the expired flow fires at once.
  - Other 4xx, including 403 (decision 2) and 429. A 429 is a rate-limit signal, and hammering it from a bounded loop does not help. This is stated, not hidden; see R6.
  - `.unexpectedResponse`, which `send` raises after `data(for:)` returns.
- **Reads only.** Every current caller is a read (`browse`, `account_menu`, the switcher, the page), so the retry applies to all of them. 2.4 must send mutations through a non-retrying path. That handoff is noted in R3; no flag is added now (YAGNI).
- **Why a closure.** The closure seam is preferred over a `URLProtocol` stub, whose static mutable state conflicts with Swift 6 strict concurrency and parallel Swift Testing.

### D3. Error model

```swift
public enum InnerTubeError: Error, Sendable, Equatable {
    case missingSAPISID
    case unauthorized              // HTTP 401 only (decision 2)
    case network(URLError.Code)    // transport failure: offline, timeout, DNS, TLS…
    case httpStatus(Int)           // any other non-2xx, incl. 403, 429, 5xx after retries
    case unexpectedResponse        // malformed / unparseable
}
extension InnerTubeError { var isTransient: Bool }   // internal: .network, .httpStatus(500...599)
```

- Existing cases and their `Equatable` use in tests are kept.
- Callers match `.unauthorized` for sign-in, `.network` / 5xx for "try again", and everything else as permanent.

### D4. Paging and continuation

```swift
public struct Page<Item: Sendable>: Sendable {
    public let items: [Item]
    public let continuation: String?           // nil = no more pages
    public init(items: [Item], continuation: String?)
}
extension Page: Equatable where Item: Equatable {}

extension JSONValue {
    // older: continuations[0].nextContinuationData.continuation
    // newer: trailing contents[].continuationItemRenderer.continuationEndpoint.continuationCommand.token
    var nextContinuation: String? { get }
}
```

- **Where the helper looks.** `nextContinuation` is called on a list container (a shelf renderer object, or the `contents` array itself). It checks `self["continuations"]?[0]?["nextContinuationData"]?["continuation"]`, then the last element of `self["contents"]?.array ?? self.array` for the `continuationItemRenderer` token. It returns `nil` for an empty string.
- **Token handling.** The token is opaque and untrusted. It is never logged, and it is sent back only as a JSON string value, so there is no header or URL injection.
- **Next-page request.** It is the same endpoint call with the token in the body: `post(endpoint, body: ["continuation": token], cookies:, authUserIndex:)` when signed in, or `postGuest(endpoint, body: ["continuation": token])` for a guest. `[String: String]` is enough, so K7 needs no change.
  - Placing the token in the body is **unverified** against live WEB_REMIX traffic (G1). If the capture in 2.2 shows the query form (`ctoken=&continuation=&type=next`), only these two call sites change. See R1.
- **`postGuest` (internal).** It takes a `GuestVisitor.shared.snapshot()`, builds `makeGuest(..., visitorData: snapshot.value)`, sends it with retry, and then calls `GuestVisitor.shared.accept(json["responseContext"]?["visitorData"]?.string, generation: snapshot.generation)`. `accept` already validates the value and drops a nil one.
  - `connectAsGuest` becomes `postGuest("browse", body: ["browseId": "FEmusic_home"])` plus its existing "visitorData must be present" check.
  - This keeps the guest visitor working through paging (I7).
- **Visibility.** `post` / `postGuest` stay internal, because `JSONValue` is internal and the 2.2/2.3 parsers live in this package. They wrap these calls into public `Page<T>`-returning methods. No public next-page method is added now, because nothing outside the package could consume raw JSON.

### D5. Skip-and-log rule for parser blocks

```swift
import os
let parserLog = Logger(subsystem: "dev.kruhlyk.redwave", category: "parser")

func parseBlocks<T>(_ blocks: [JSONValue], _ transform: (JSONValue) -> T?) -> [T]
// keeps order; a nil transform drops the block and logs `Skipped block <key>`
func blockKey(_ block: JSONValue) -> String
// the renderer key only: the first key (sorted) of an object, truncated to 64 chars; "non-object" otherwise
```

- **What is logged.** Only `blockKey(block)` is logged, with `privacy: .public`. It is a schema name such as `musicCarouselShelfRenderer` and never a value. That is why "no values, cookies, tokens or `visitorData` in logs" holds by construction.
- **Testing.** `os.Logger` output cannot be captured in tests, so the test asserts on `blockKey`.
- **Continuation blocks.** A trailing `continuationItemRenderer` is not logged as unknown, because it is paging data and not an unknown block.
- **Other logging.** Retries and 401s are not logged. Nothing asked for it, and it is the safest choice for PRD 7.3.

### D6. Session expiry in Auth: a flag, then the existing sign-out

```swift
public private(set) var isSessionExpired = false

public func expireSession(cookies: [HTTPCookie]) async {
    guard case .signedIn(let current) = state, current == cookies else { return }   // stale 401 → ignored
    await signOut()
    if case .signedOut = state { isSessionExpired = true }
}
```

- **Not a new `State` case.** Adding one would break the exhaustive `switch` in `RedwaveApp` and the meaning of `State.isSignedIn` ("`.signedOut` means guest").
- **Why reuse `signOut()`.** It already does what an expired session needs, in a crash-safe order:
  - It wipes `WKWebsiteDataStore` first, then deletes the Keychain entry, so the stale entry is never used again.
  - It resets `authUserIndex`, clears `isAddingAccount`, and handles a Keychain failure.
- **Why the WebKit wipe is required, not just reused.** `SignInRules.isSignInComplete` accepts any `SAPISID` once the main frame is on `music.youtube.com`. Without the wipe, the server-revoked cookies still in WebKit could auto-complete the new sign-in sheet with dead cookies and loop. Decision 1 forbids *re-reading* those cookies; wiping them is different.
- **Stale-401 guard (K8, BA story 4).** The caller passes the exact cookie array it sent, captured from `session.state` at the start of the load.
  - `expire` acts only if the session still holds that same array. `HTTPCookie` uses `isEqual`, and the instances are the same.
  - After a sign-out, a sign-in or an Add-account sign-in, the array differs, so the 401 is dropped.
  - An account switch only changes `authUserIndex`. It is covered by the model's `Task.isCancelled` check, because `.task(id:)` changes and cancels the old load.
- **Concurrent 401s.** They are idempotent.
  - The first call is suspended inside `signOut()` with `isSigningOut == true`.
  - A second call passes the guard, but `signOut()` returns early, and `state` is still `.signedIn`, so the flag is not set by it.
  - The first call then completes normally.
- **Keychain delete failure.** `signOut` sets `signOutError` and returns with the state still `.signedIn`. The flag is not set, and `AccountView` shows its existing "Couldn't clear the saved session" message.
- **Timing of the flag.** `isSessionExpired = true` runs in the same main-actor job as `state = .signedOut`, with no suspension in between. `GuestView` therefore sees the flag on its first appearance.
- **Clearing the flag.** `completeSignIn` sets `isSessionExpired = false`. Cancelling the sheet keeps the flag, so the guest screen keeps its explanation for this launch. The flag is not persisted.
- **Who can trigger it.** Guests cannot (`state` is not `.signedIn`), and neither can `.keychainUnavailable` → "Continue without signing in" (`.signedOut`). `GuestModel` never calls it.

### D7. App wiring

- **`AccountModel.load`.**
  - Capture `cookies` and `index` as today.
  - Run both calls as `async let` producing `Result<…, any Error>` through a 3-line private helper `result(_:)` that wraps `do/catch`.
  - After each `await`, check `!Task.isCancelled`.
  - If either result is `.failure(InnerTubeError.unauthorized)`, call `await session.expireSession(cookies: cookies)` and return. A 401 on the list is acted on immediately; the `menu` child is cancelled implicitly at scope exit.
  - Otherwise behave exactly as today: an empty list counts as a list failure, the fallback index applies, and a `.failed` / `.loaded` state is set.
- **`GuestView`.**
  - `.onAppear { if session.isSessionExpired { isSigningIn = true } }`.
  - `GuestContent(isSessionExpired:)` shows `Text("Your session expired. Sign in again.")` above the status line. A plain `Text` is readable by VoiceOver, scales with Dynamic Type, and uses the default style, so Dark Mode is unaffected.
  - The existing sheet, Cancel (WebKit wipe) and Sign in button are reused unchanged.
- **`RedwaveApp`.**
  - Only the discovery task in `init` is added.
  - The existing `.onChange(of: session.state.isSignedIn) { resetGuestVisitor() }` already fires on expiry, so the guest visitor starts fresh.

## 5. Convention skills to invoke during implementation

- `apple-plugin:swiftui-conventions`
- `apple-plugin:swiftui-state`
- `apple-plugin:macos-app`
- `swift-foundation:swift-conventions`
- `swift-foundation:swift-tooling`
- `swift-foundation:swift-testing`
- `apple-plugin:apple-testing`

`swiftui-navigation` is not needed: the change adds no destination, scene or window.

## 6. Tests (Swift Testing, no network)

**ClientVersionTests.** These use `ClientVersion(defaults: UserDefaults(suiteName: UUID().uuidString)!)` and never touch `.shared`.
- `extract` finds the version in a synthetic `ytcfg` HTML fixture.
- `extract` returns nil when the key is missing, and for consent-page HTML.
- Parameterized rejects: `""`, `1.2.3`, `1.20261115.14.00"`, a value with a space, a value with `\n`, an over-long value, `Ж`.
- `init` with no cache gives `builtIn`. With a valid cache it gives the cached value. With an invalid cache it gives `builtIn`.
- `accept(valid)` updates `current` and the defaults. `accept(invalid)` and `accept(nil)` keep the previous value.
- `InnerTubeRequest.makePage()` is a GET to `https://music.youtube.com/` with no `Cookie`, `Authorization`, `X-Goog-AuthUser` or `X-Goog-Visitor-Id`, and `httpShouldHandleCookies == false`.
- A guest request body's `clientVersion` equals `ClientVersion.shared.current`. This is read-only on `.shared`.

**ClientTransportTests.** These use a stub transport: a small `actor` or lock-protected recorder of requests that returns scripted responses, with `retryDelay: .zero`.
- A network error, then 200 → success after 2 attempts.
- 503 three times → `.httpStatus(503)` after exactly 3 attempts.
- 400, 403 and 429 → 1 attempt each.
- 200 with a non-JSON body → `.unexpectedResponse`, 1 attempt.
- 401 → `.unauthorized`, 1 attempt. This is the issue's "401 path" (I2).
- `URLError(.notConnectedToInternet)` three times → `.network(.notConnectedToInternet)`.
- Cancellation: the transport always fails, the delay is long, and the task is cancelled after the first attempt. The test expects 1 attempt and a cancellation error.
- **Paging over two fixture pages (guest).**
  - Page 1 has a renderer list (known blocks, one unknown block, and a trailing `continuationItemRenderer` token) plus `responseContext.visitorData`. Page 2 has items and no token.
  - The test drives `postGuest` → `parseBlocks` → `Page`. It expects:
    - the unknown block dropped and order kept;
    - `continuation` set on the first page and nil on the second;
    - the second request body has `continuation == token` and a non-empty `clientVersion`;
    - the second request carries `X-Goog-Visitor-Id` from page 1 and no `Cookie` / `Authorization` / `X-Goog-AuthUser`.
  - This suite touches `GuestVisitor.shared`, so it is marked `.serialized` and calls `GuestVisitor.shared.reset()` first.
- **Signed continuation request.** `InnerTubeRequest.make(endpoint: "browse", body: ["continuation": "t"], cookies:…)` carries `Authorization: SAPISIDHASH …`, `X-Goog-AuthUser`, and the token in the body.

**PageTests.**
- `nextContinuation` reads the older shape, the newer shape (both on the object's `contents` and on a bare array), no continuation, and an empty token (→ nil).
- `parseBlocks` keeps order and drops nil results.
- `blockKey` returns only the key: a fixture block holding a fake cookie and token value yields exactly the renderer key. It also returns "non-object" for a scalar and truncates long keys.

**AuthSessionTests (additions).**
- Signed-in `expireSession(cookies: same)` → `.signedOut`, `isSessionExpired`, Keychain `deleteCount == 1`, `authUserIndex == 0`. This runs the real WebKit wipe through `signOut`, as `cancelSignIn` tests already do.
- A second call → no-op, with `deleteCount` still 1.
- Different cookies (a stale session) → ignored, still signed in.
- `.signedOut` → ignored.
- `completeSignIn` clears `isSessionExpired`.
- A Keychain delete failure → still `.signedIn`, flag false. This needs a `deleteError` field on the `KeychainSpy` test double.

**Not unit-tested (no app test target).** These are verified by build and manual run:
- `AccountModel` routing a 401 to `expireSession`.
- `GuestView` auto-presenting the sheet.
- `RedwaveApp` triggering discovery.

## 7. Verification

- `swift test` in `Packages/InnerTube` and in `Packages/Auth`.
- `xcodebuild -project Redwave.xcodeproj -scheme Redwave -destination 'platform=macOS' -quiet build`, with no new warnings.
- Manual, if a session is available:
  - The first launch logs no page fetch on the critical path.
  - Kill the network: the guest "Retry" appears after ≤ ~2 s of retries.
  - A revoked session: the app lands on the guest screen with "Your session expired" and the sign-in sheet.

## 8. Risks and edge cases

- **R1. The continuation wire format is unverified (G1).** The token is sent as body `continuation`. The response shapes are handled tolerantly, both of them.
  - If live traffic needs the `ctoken` query form, only `post`/`postGuest` call sites in 2.2 change.
  - The note in `docs/01-reverse-engineering.md` is deferred until a capture confirms the format.
- **R2. The real expired-session signal is unverified (C4).** Only 401 is treated as expiry (decision 2). If Google answers 403 or 200 with a signed-out `account_menu`, the user sees the existing `.failed` Retry / Sign out screen instead of sign-in. That is not a regression, but the "Done when" clear re-sign-in would not be met for that signal.
- **R3. Mutations must not retry.** No mutations exist yet. 2.4 must add a non-retrying send path for `playlist/create` and `browse/edit_playlist`. Hand this off in the PR notes.
- **R4. A strict version regex.** A format change by Google makes discovery fall back silently to the cached or built-in value. Requests still go out with an older version, which usually works. A server rejection of a stale version (G2) is treated as permanent `httpStatus(400)`, and there is no rediscovery.
- **R5. "No extra page request before the first API call" (I9).** Discovery runs on every launch in the background (decision 3) and may hit the wire before the first API request. It never delays that request. If the stricter reading is required, discovery would move after the first response; that needs a user decision.
- **R6. 429 is not retried.** It is reported as `httpStatus(429)`. This is a deliberate choice, because a bounded retry cannot outwait a rate limit.
- **R7. K8: a stale `authUserIndex` with a failed list.** If the switcher list fails (non-401), the fallback cannot correct an invalid index. If the server then answers that `account_menu` with 401, a valid session would be expired. This is not observed; it depends on R2's live check.
- **R8. Request timeout.** It is left at the URLSession default. An offline failure is immediate, but a black-holed network can take up to the default request timeout per attempt. Lowering the timeout was not requested.
- **R9. Guest 401/403.** These are surfaced as ordinary errors, and the guest visitor is not reset. The BA suggestion to reset it is skipped because no source requires it.
- **R10. Shared singletons in tests.** Only the serialized paging suite mutates `GuestVisitor.shared`, and no test mutates `ClientVersion.shared`.
- **Covered edge cases.** These are handled by the decisions above:
  - The page fetch gets a consent redirect, a captcha, or no `ytcfg`.
  - A malformed or over-long version.
  - Discovery finishing while requests are in flight: they keep their version.
  - Concurrent 401s.
  - A 401 after a sign-out, sign-in or account switch.
  - A 401 while Add account is open: `signOut` clears `isAddingAccount`.
  - A guest or `.keychainUnavailable` session never expires.
  - Cancellation during the backoff.
  - An empty page with a token, or items without one.
  - A repeated token is a consumer guard in 2.2/4.x and is noted in the PR.

## Contract for frontend

No frontend contract. There is no backend. For the app layer, the Swift surface added in this change is:
- `InnerTubeError.unauthorized`
- `InnerTubeError.network(URLError.Code)`
- `Page<Item>`
- `InnerTubeClient.refreshClientVersion()`
- `AuthSession.isSessionExpired`
- `AuthSession.expireSession(cookies:)`
