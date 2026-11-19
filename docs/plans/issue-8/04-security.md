# Security Review: InnerTube client version discovery, continuation paging and error handling (backlog 2.1, issue #8)

## Summary
- Critical: 0 (nothing for the fix pass)
- High: 0 (nothing for the fix pass)
- Medium: 1. It is a recommendation, but **it should go into the fix pass**. This change introduced it, and the fix is five lines in one branch.
- Out of scope: Low 3, Info 10

No credential leaves its intended path:
- The discovery `GET /` is cookie-free at three layers: the request flag, the session configuration, and the header set.
- The discovered version is validated to digits and dots and is used only as a JSON body value. It never goes into a header or a URL.
- The continuation token is used only in the body.
- Redirects are still rejected, so signed retries cannot follow a 3xx to another host.
- A 401 can come only from `music.youtube.com` over TLS with default ATS. A network attacker cannot force the new session wipe without a trusted CA.

The main finding, M1, is an availability regression in multi-account sessions. A 401 on `account_menu` for a **secondary** index wipes the session of **every** account, including a primary that still works. Before this change, the 1.3 fix (`.failed(accounts:)` with rows) let the user switch back.

## Checked and clean

| Check | Result |
|---|---|
| Discovery request carries no credentials (`InnerTubeRequest.swift:47-51`, `:72-82`; `InnerTubeClient.swift:41-45`) | `makePage()` is built on `unauthenticated()`: `httpShouldHandleCookies = false`, and only `Origin`, `X-Origin` and `User-Agent` are set. It has no `Cookie`, `Authorization`, `X-Goog-AuthUser` or `X-Goog-Visitor-Id`. The session is `.ephemeral`, with `httpCookieStorage = nil`, `httpShouldSetCookies = false` and `urlCache = nil`, so the response's `Set-Cookie` is dropped too. Covered by `ClientVersionTests.pageRequestIsAnonymousGet` (`:50-58`). |
| Untrusted page value cannot reach later requests (`ClientVersion.swift:28-36`, `InnerTubeRequest.swift:89`) | `extract` captures at most 64 non-quote characters, then `validated` requires a whole match of `[0-9]+\.[0-9]{8}\.[0-9]{2}\.[0-9]{2}` and at most 32 characters. `[0-9]` is the ASCII range, not `\d`, so other Unicode digits are rejected (`"Ж"`, quote, space and newline cases are tested at `ClientVersionTests.swift:21-24`). The only consumer is the `clientVersion` value in the JSON body, written by `JSONSerialization`. Even a value that got past validation would be JSON-escaped, and it never goes into a header or URL. |
| Version cache tampering (`ClientVersion.swift:13-16`, `:22-26`) | The cached value is re-validated at `init`. A same-user process that writes `innerTubeClientVersion` can only set another well-formed version, and an invalid one falls back to `builtIn`. The value is not a secret, so `UserDefaults` is the right store. |
| Discovery trigger (`RedwaveApp.swift:12`) | Called once per process from a detached utility task. It is non-throwing and never awaited on the request path. `ClientVersion.shared.current` is read under an `OSAllocatedUnfairLock`. |
| Guest paths never carry signed headers (`InnerTubeRequest.swift:22-34`, `InnerTubeClient.swift:97-104`) | `makeGuest` uses `unauthenticated()` plus a `GuestVisitor.validated` visitor ID only. `postGuest` has no cookie parameter. Covered by `ClientTransportTests.guestPagingKeepsVisitorAndSendsToken` (`:120-127`). |
| Retries do not leak or duplicate credentials (`InnerTubeClient.swift:110-121`, `:21-30`) | Every attempt sends the same `URLRequest`. Nothing is re-signed and no new header is added. The target is the same host, and `RejectRedirects` returns `nil`, so a signed request never follows a 3xx. At most 3 attempts are made. |
| 401 never retried, cancellation not swallowed (`InnerTubeClient.swift:11-19`, `:123-135`) | 401 maps to `.unauthorized`, for which `isTransient == false`. `URLError(.cancelled)` is excluded from the mapping at `:128` and rethrown. `Task.sleep` throws `CancellationError` during the backoff. Tests: `ClientTransportTests.swift:75-79`, `:87-100`. |
| Guest visitor across retries and paging (`InnerTubeClient.swift:98-102`, `GuestVisitor.swift:22-27`) | One snapshot is taken per call, and the response is accepted only for the same generation, with `validated` applied. A sign-in or sign-out mid-flight cannot plant an old identity. |
| Continuation token (`Page.swift:15-19`) | It is opaque and goes only into the body as a JSON string (`ClientTransportTests.swift:117-122`, `:131-139`). It is not placed in a URL or query string, so there is no URL or header injection and no SSRF. It is never logged. |
| Who can trigger expiry (`AccountModel.swift:27-30`, `:40-43`; `AuthSession.swift:112`) | Only the two signed `AccountModel` calls route `.unauthorized` to `expireSession`. `GuestModel.connect` collapses every error to `.failed` (`GuestModel.swift:13`). The `case .signedIn` guard means guest and `.keychainUnavailable` sessions can never expire. |
| Expiry wipe (`AuthSession.swift:92-108`, `:111-115`) | It reuses `signOut`, which wipes `WKWebsiteDataStore.default()` (every data type), then `URLCache.shared`, then the Keychain item. It also resets `authUserIndex` and clears `isAddingAccount`. `SignInView` uses the default `WKWebViewConfiguration`, so this is the same store (`SignInView.swift:47-49`). |
| No sign-in loop with dead cookies (`SignInRules.swift:38-41`, `AuthSession.swift:119`) | The wipe removes the revoked `SAPISID`, so the auto-presented sheet cannot auto-complete with dead cookies. `completeSignIn` is guarded by `isSigningOut`, so nothing can complete during the wipe. |
| Concurrent 401s (`AuthSession.swift:93`, `:114`) | The second call returns early inside `signOut` while the state is still `.signedIn`, so only the first call sets the flag. Tested at `AuthSessionTests.swift:145-146`. |
| Flag timing (`AuthSession.swift:107`, `:114`) | Both properties are main-actor isolated, and `signOut` returns without a hop, so there is no suspension between `state = .signedOut` and `isSessionExpired = true`. `GuestView.onAppear` (`GuestView.swift:19`) sees the flag on first render. |
| Keychain failure during expiry (`AuthSession.swift:100-105`) | The state stays `.signedIn`, the flag is not set, and `signOutError` drives "Couldn't clear the saved session". Tested at `AuthSessionTests.swift:166-173`. The UI side effect is in L1. |
| Stale 401 from a replaced session (`AccountModel.swift:26`, `:39`) | Sign-out removes `AccountView`, and an account switch or Add-account changes the `.task(id:)` key. Both cancel the old load before its 401 is acted on, with no suspension between the `Task.isCancelled` check and the `expireSession` guard. The cookie-equality guard is a second line of defense (L3). |
| Logging (`Blocks.swift:3-19`) | Only the renderer key name is logged. No values, cookies, tokens, `visitorData` or versions are logged. Retries and 401s are not logged. Details are in Info 5. |
| Transport and ATS | There is no `NSAppTransportSecurity` key (`GENERATE_INFOPLIST_FILE`), no server-trust delegate and no pinning, which is consistent with 1.2 Info 2. Hardened runtime is on, and `project.yml` and entitlements are unchanged. |
| Dependencies | There is no `Package.resolved` and no new package. |
| UI (`GuestView.swift:47-49`) | The new text is a static literal with no user data. The sheet reuses the existing Cancel path, which wipes WebKit. |
| Docs (`docs/02-architecture.md:157-160`, `:206-208`; `docs/05-risks-and-scope.md:14`) | Accurate for the code as written. |

## Critical findings (for the fix pass)

None.

## High findings (for the fix pass)

None.

## Medium recommendations (recommended for the fix pass)

### 1. A 401 on `account_menu` for a secondary account wipes every account's session — `App/AccountModel.swift:40-43`

**Issue (introduced by this change).** The list request always uses `X-Goog-AuthUser: 0` (`AccountModel.swift:23`). If the whole session is dead, the list returns 401 first, and that branch (`:27-30`) correctly expires. A 401 on `account_menu` alone, with `index != 0`, means something narrower: Google rejects that one account in the multi-login session, while the primary still answers (or failed for a non-401 reason). The code treats both cases the same and calls `expireSession`. That wipes the WebKit store and the Keychain item for **all** accounts.

**Failure scenario.** This is the 1.3 account-switching M1 scenario:
1. The user is on account 1.
2. Account 1 needs re-authentication at Google, for example after a password change or a Workspace policy.
3. The list still contains `authuser=1`, so `fallbackIndex` keeps the index.
4. `account_menu(1)` returns 401, and the whole session is wiped.

In 1.3 the same case ended in `.failed(accounts:)` with the rows still visible, and one click returned the user to the working primary (status "Fixed in fix pass"). Now the user must sign in to every account again. It also covers plan R7: if the list fails for a non-401 reason with a stale index and the menu returns 401, a valid session is wiped. The semantics of a per-`authuser` 401 are unverified (plan R2).

**Prescribed fix (symbol level).** In `AccountModel.load`, replace the menu-401 branch:

```swift
if case .failure(InnerTubeError.unauthorized) = menuResult {
    // The list at index 0 did not return 401, so only this account is rejected; fall back instead of wiping every account.
    if index != 0 {
        session.authUserIndex = 0
    } else {
        await session.expireSession(cookies: cookies)
    }
    return
}
```

- Changing `authUserIndex` re-fires `.task(id: ReloadKey(...))` in `AccountView`. This is the same pattern as the existing `resolved != index` path at `:34-37`.
- If the session is in fact dead, the reload at index 0 returns 401 on the list or the menu, and that path expires normally. So no expiry is lost and nothing loops.
- The list-401 branch (`:27-30`) stays as it is.
- There is no app test target. Verification: review, plus the manual "revoked secondary account" check if one can be reproduced.

**Why Medium, not High.** Nothing is exposed: the code fails closed and destroys local credentials. The trigger also needs a multi-account session and a per-account 401 from Google. But this change introduced it, it undoes the 1.3 M1 fix for the 401 signal, and the fix is a few lines.

## Out of scope

### Low

1. **The spinner never stops when expiry does not complete** (`App/AccountModel.swift:28-29`, `:41-42`). This is on the silent-failure checklist. Both 401 branches `return` without setting `state`, so `model.state` stays `.loading`.
   - When `expireSession` is a no-op because the Keychain delete failed (`errSecInteractionNotAllowed`, a locked keychain), the WebKit store is already wiped and the user sees a spinner with no Retry.
   - "Couldn't clear the saved session" and Sign out are still shown, which is why this is Low.
   - **Fix:** after each `await session.expireSession(cookies: cookies)`, set `state = .failed(accounts: nil)` in the list branch and `state = .failed(accounts: accounts)` in the menu branch.
   - If the session did expire, `AccountView` is already gone and the assignment is harmless.
   - These are the same lines as M1, so bundling it is cheap.

2. **Discovery fails silently** (`Packages/InnerTube/Sources/InnerTube/InnerTubeClient.swift:54-57`). This is on the silent-failure checklist. `try?` discards every error, and a page without a version is also ignored without a trace.
   - For EU users, `GET /` returns a consent 302, which is rejected, so discovery fails on every launch.
   - The built-in version then ages until the server rejects it with 400 (plan R4/G2). The guest and account screens then fail, and nothing in the log says why.
   - **Fix:** replace the `try?` with a `do/catch` and log through the existing subsystem, for example `Logger(subsystem: "dev.kruhlyk.redwave", category: "discovery")`.
   - Log the error with `privacy: .public` only when it is an `InnerTubeError`. Those cases hold only a status or a `URLError.Code`.
   - Log a second `notice` when `extract` returns `nil`.
   - Never log the page body.

3. **The stale-401 guard's test does not cover the realistic case** (`Packages/Auth/Sources/Auth/AuthSession.swift:112`, `Packages/Auth/Tests/AuthTests/AuthSessionTests.swift:149-156`).
   - The test passes `[makeCookie("SID")]`, which differs from the session's array by count and names.
   - A replaced session would usually have the same names, domains and paths with new values. Whether `HTTPCookie` equality includes `value` decides that case, and it was not verified here.
   - **Fix (QA):** add a test that signs in, builds the same cookies with changed values, calls `expireSession` with them, and expects the session still `.signedIn` with `deleteCount == 0`.
   - If that test fails, change the guard to identity, which is what the plan intends ("the instances are the same"): `current.elementsEqual(cookies, by: ===)`.
   - This is Low because the `Task.isCancelled` checks cover sign-out, Add-account and switching first.

### Info

1. **Carried over (1.2 Info 1, 1.3 Info 7, 1.4 Info 5): redirect rejection is still not verified at runtime** (`InnerTubeClient.swift:21-30`).
   - The new transport seam replaces the whole `URLSession`, so `RejectRedirects` is never exercised by the new tests.
   - Discovery now depends on it for the consent 302 (plan K2).
   - Still open. Add a manual check (an EU VPN or a consent-cookie-free launch should log `httpStatus(302)` once L2 lands), or a `URLProtocol` test in a serialized suite.

2. **Every `URLError` code is retried** (`InnerTubeClient.swift:14`, `:128-129`). That includes `.serverCertificateUntrusted`, `.secureConnectionFailed` and `.appTransportSecurityRequiresSecureConnection`.
   - Trust is re-evaluated on every attempt, so security is not weakened. Only attempts are wasted.
   - Optional: treat TLS and ATS codes as permanent.

3. **Signed retries reuse the original `SAPISIDHASH` timestamp** (`InnerTubeRequest.swift:64`).
   - In the worst case, with the default 60 s request timeout × 3 plus the backoff, the hash is about 3 minutes old.
   - The target is the same host with the same credentials, so nothing new is exposed. This is functional only.

4. **2.4 handoff: mutations must not use `post`** (`InnerTubeClient.swift:80-95`, `:111-121`). `data(for:)` retries 5xx for every caller. A `playlist/create` or `browse/edit_playlist` that the server applied before a 502 would be applied twice. 2.4 needs a single-attempt path, for example a `maxAttempts` parameter on `data(for:)`. Put this in the PR notes (plan R3).

5. **Latent: the parser log writes a server-controlled key with `privacy: .public` at `.notice`** (`Blocks.swift:9`, `:16-19`).
   - InnerTube block keys are schema names, the key is capped at 64 characters, and `parseBlocks` has no production caller yet. Acceptable.
   - Optional hardening for 2.2: log the key only if it matches `^[A-Za-z0-9]{1,64}$`, otherwise `"unnamed"`.
   - Correctness note for 2.2: `keys.min()` can pick a sibling such as `clickTrackingParams` instead of the renderer key.

6. **Latent: the continuation token is unbounded, and a repeated token is not detected** (`Page.swift:15-19`). The token is echoed back in the body only, with no size cap. The 2.2 consumers that auto-page must stop when they get the same token again (plan §8). There is no production caller yet.

7. **Wider reach of guest-mode Info 3** (`GuestView.swift:19-20`, `:31-34`). Expiry now auto-presents a sign-in sheet in **every** open guest window. Cancel in one window still wipes WebKit under a sign-in in progress in another. The result is a failed sign-in, not a leak. No action now.

8. **There is no `PrivacyInfo.xcprivacy` in the repository.** Plan §2 says the privacy manifest is "unchanged", but none exists. The new key is in the app's own defaults domain. If the app is ever distributed through the App Store, the manifest needs the `NSPrivacyAccessedAPICategoryUserDefaults` reason `CA92.1`. Correct the wording in the PR notes.

9. **Carried over (1.2 L4 / 1.3 Info 6 / 1.4 Info 6): JSON nesting depth is still not bounded** (`JSONValue.swift:11-26`).
   - Discovery adds no JSON surface, because it runs a regex over HTML.
   - Paging in 2.2 will add more decode calls.
   - The fix is unchanged: a 1000-level `[` test, and a depth cap of 128 if it fails.

10. **Carried over (1.2 Info 3, Info 7): resource items.**
    - `refreshClientVersion` creates one more `InnerTubeClient` per launch, and its `URLSession` is never invalidated.
    - The discovery GET buffers the whole HTML page before running the regex.
    - Both are bounded by Google and by one call per launch. No action.

### Carry-over tracking

- **Closed:** guest-mode Info 4 / 1.3 Info 9. `docs/02` §5.1 "taken from the page" is now true (`InnerTubeRequest.swift:89`, `RedwaveApp.swift:12`).
- **Changed:** account-switching M1. For non-401 menu failures it is still closed by `.failed(accounts:)` with rows. A 401 now wipes every account instead: see M1 above.
- **Still open, unchanged:** the redirect runtime check (Info 1), JSON depth (Info 9), the `URLSession` leak (Info 10), and the 1.4 `visitorData` reset tied to window content (rename-redwave Info 7).

## Severity summary

| Severity | Count | Next step |
|---|---|---|
| Critical | 0 | — |
| High | 0 | — |
| Medium | 1 | M1: in `AccountModel.load` (`AccountModel.swift:40-43`), on a menu 401 with `index != 0`, set `authUserIndex = 0` instead of expiring. **Recommended for the fix pass** |
| Low | 3 | L1: set `.failed` after `expireSession` (same lines as M1, cheap to bundle). L2: log discovery failures, with the status or code only. L3: a QA test for the stale guard with the same names and new values, and an identity comparison if it fails |
| Info | 10 | Out of scope. Info 1 is a manual check, Info 4 goes in the PR notes for 2.4, and Info 5 and 6 apply in 2.2 |
