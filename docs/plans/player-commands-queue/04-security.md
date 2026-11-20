# Security Review: PlayerEngine commands, queue access, failure recovery and debug window (3.2, issue #14)

## Summary
- Critical: 0
- High: 0
- Medium: 1 (cheap, recommended for the fix pass)
- Out of scope: Low 4, Info 4

The Swift → JS command path holds:
- `callAsyncJavaScript` passes data only through its `arguments` dictionary. There is no string building.
- Each call runs only after a ready check and a `music.youtube.com` host check.
- The JS side is a frozen, null-prototype table of named operations, never an arbitrary method name.
- No cookie or token reaches JavaScript.
- The like write goes through the existing InnerTube `mutate` path (guest gate, no retry), and only a Swift caller can trigger it.
- Every new inbound message is size-capped, typed, and range- or enum-checked.
- The queue parser caps names in UTF-8 bytes and runs no regex on them.
- Recovery reloads rebuild the URL from validated IDs and still go through the navigation lock.
- The debug window and its scene are compiled only in DEBUG.

The one Medium is in logging. Three new `.error` lines log a whole `Error` as `.public`. For a navigation failure, WebKit's `NSError` holds the failing URL, which is the watch or `/signin` URL with the video ID, the playlist ID and `authuser`. `.error` lines are persisted to disk. This undoes the 3.1 L1 hashing on exactly the failure paths. An offline launch is enough to trigger it. The fix is three one-liners.

**Method.** I have no shell, so I could not run `git diff develop`. I worked out the changed regions from `02-development.md`, `02-development-plan.md` and the git-status snapshot. I read every new file in full. Of the modified files, I read `PlayerEngine.swift`, `BridgeMessage.swift`, `PlayerRules.swift`, `PlayerEvent.swift`, `bridge.js`, `RedwaveApp.swift` and all PlayerEngine tests in full, and `docs/02-architecture.md` §4. I traced the dependencies: `SongInfo.swift`, `InnerTubeClient.swift` (`InnerTubeError`, `rate`, `mutate`, `attemptOnce`), `AccountModel.swift` (the 401 handling pattern) and `AuthSession.swift` (`isSigningOut`, `authUserIndex`). I could not confirm the claim that the Release binary has no `PlayerDebugView` symbol (it needs a shell). The source gating supports it.

## Checked and clean

| Check | Result |
|---|---|
| Swift → JS injection (A03, WKWebView) | `PlayerEngine.swift:163-165`: `callAsyncJavaScript("return window.__bridge.run(action, args)", arguments: [...], in: nil, contentWorld: .page)`. The values travel as arguments, and the body is a constant. `in: nil` targets the main frame. A grep for `evaluateJavaScript` in `App/` and `Packages/*/Sources` finds nothing. The bridge stays in `.page` world on purpose: an isolated world cannot see `#movie_player`, as issue-12 recorded. |
| Command gating | `PlayerEngine.swift:149`: the call needs a `webView`, `isReady` and `webView.url` host == `music.youtube.com`. `load` and `setLike` are routed out first (`:139-148`). The ad gate is at `:153-156`. |
| Command argument validation | `PlayerRules.swift:81-113`. `seek(to:)` must be finite and ≥ 0, and `skip(by:)` must be finite. Volume must be finite and is clamped to 0…1 ×100. A queue `index` and `to` must be in `queue.indices`, and removing the current row is refused. The `enqueue` video ID goes through `isValidID`. `setLike` and `load` are never page calls. Tests: `BridgeCallTests.swift:12-77`. |
| JS operation table | `bridge.js:59-88`: `Object.freeze(Object.assign(Object.create(null), …))`, so `__proto__`, `constructor` and similar names resolve to `undefined`. `run` (`:90-98`) requires a string `action` and an array `args`, and returns only `=== true`. `__bridge` is defined `writable: false, configurable: false` (`:100`). The exception is the leftover guard (L2). Every row operation checks the row identity (`:34-37`, `:83-86`). |
| Inbound messages (bodies untrusted) | `BridgeMessage.swift:33-68`. The cap is 256 KiB, decoding uses a typed `Envelope`, and `time` must be finite and ≥ 0 for every type (`:37`). `volume` must be finite and in 0…100 (`:49-51`). `like` and `repeat` take only strict page enums (`PlayerState.swift:6-26`). The `unavailable` video ID goes through `isValidID` (`:63`). Unknown types are dropped. The frame and origin gate is unchanged (`PlayerEngine.swift:342-348`, `PlayerRules.swift:17-19`). Tests: `BridgeMessageTests.swift:42-111`. |
| Queue parse | `QueueItem.swift:36-64`. The list is capped at 500 rows. Each `videoId` goes through `isValidID`, and `setId` is limited to 128 characters. Title and artist are cut to 1024 UTF-8 bytes, with no `cleanupName` regex, so the 3.1 M1 hazard does not come back. Artwork must pass the https Google image host allowlist. One bad row rejects the whole message. `parseDuration` (`PlayerRules.swift:54-64`) accepts ASCII digits only, each part < 100 000, at most 3 parts, so it cannot overflow. |
| Recovery reload URL (SSRF / navigation) | `PlayerEngine.swift:204-216`, `:128`. The URL is always `PlayerRules.loadURL` built from `target`. `target` comes from `load` (validated) or a committed `SongInfo`: the video ID through `watchURL` (`SongInfo.swift:71`) and the playlist ID through `isValidID` (`SongInfo.swift:92-96`). `authUserIndex` is `nil` for a guest. Each reload is a `webView.load`, which goes through `decidePolicyFor` and the navigation lock (`:350-355`). No URL from a message is ever loaded. |
| Like write (A01, credentials) | `PlayerEngine.swift:173-188`. A guest, a missing `rate` or a missing `song` gives `error(.signInRequired)`, and `rate` is not called (test at `PlayerEngineTests.swift:82-92`). The result is applied only if the song has not changed (`:181`). `RedwaveApp.swift:45-54` reads cookies from `session.state` and passes them to `InnerTubeClient.rate`. That goes to `mutate`, which retries nothing and turns `nil` credentials into `signInRequired` (`InnerTubeClient.swift:196-199`, `:286-292`). The cookies never touch the web view or JS. The only `send(.setLike)` caller is the DEBUG window (`App/PlayerDebugView.swift:91-93`). |
| DEBUG-only surfaces | `App/PlayerDebugView.swift:1` / `:166` wrap the whole file in `#if DEBUG`. The `Window` scene is at `RedwaveApp.swift:39-41`, the `debugVideoId` hook at `:62-66`, and `isInspectable` at `PlayerEngine.swift:313-315`. The debug window only reads `player` and calls `send`, and it never hosts the web view. |
| Teardown | `stop()` (`PlayerEngine.swift:96-121`) removes the script message handlers. It cancels `songTask` and the watchdog, and clears `target`, `resumeAt`, `attempts`, `position` and all the new observable state. The Keychain restore loop checks the generation before each cookie (`:87-90`). |
| Logging (A09) | `emit` (`PlayerEngine.swift:281-297`): `songChanged` logs the ID as `.private(mask: .hash)` and the title and artist as `.private`. `queueChanged` logs only a count, and `unavailable` logs a hashed ID. The default-case events (`ready`, `playbackChanged`, `likeChanged`, `repeatChanged`, `shuffleChanged`, `adChanged` and the other errors) carry no IDs or names. `page refused <action>` logs only a fixed action name. The exception is M1. |
| Test data | `Fixtures/queue.json` uses illustrative IDs (`aaaaaaaaaaa`…) and a placeholder `lh3.googleusercontent.com/example-one`. `LivePlaybackTests.swift` is opt-in (`REDWAVE_LIVE_TESTS=1`), runs as a guest (`.signedOut` → `nonPersistent()`) and plays a public video. A grep for cookie, `SAPISID` and `__Secure` in `Tests/` finds no credentials. |
| Dependencies, config (A05/A06) | Git status shows no change to `project.yml`, any `Package.swift`, `Package.resolved`, Info.plist or entitlements. There is no ATS exception. `.gitignore` adds only `.claude/.sdlc-*.json` and `/docs/plans`, with no `!` negation. |

## Critical findings (for the fix pass)

None.

## High findings (for the fix pass)

None.

## Medium recommendations (cheap, recommended for the fix pass)

### M1. Errors are logged `.public` at `.error` level. A navigation failure's `NSError` holds the load URL (`v=`, `list=`, `authuser=`) — `PlayerEngine.swift:372`, `:168`, `:185`

**Issue.**
- `navigationFailed` logs `Self.log.error("navigation failed: \(error, privacy: .public)")` (`:372`). Its `error` comes straight from WebKit's `didFailProvisionalNavigation` / `didFail` (`:396-402`). It is an `NSError`, which renders as `Error Domain=… Code=… "…" UserInfo={…}`. Its `userInfo` holds `NSErrorFailingURLKey` and `NSErrorFailingURLStringKey`, which are the exact URL being loaded:
  - for a guest, `https://music.youtube.com/watch?v=<videoId>&list=<playlistId>`;
  - signed in, `https://music.youtube.com/signin?action_handle_signin=true&authuser=<n>&next=/watch%3Fv%3D<videoId>%26list%3D<playlistId>`.
- `page call <action> failed: \(error, privacy: .public)` (`:168`) logs the `WKError` from `callAsyncJavaScript`. For a JS exception, its `userInfo` holds `WKJavaScriptExceptionSourceURL` (the page URL, `v=` included) and the exception message.
- `rate failed: \(error, privacy: .public)` (`:185`) is lower risk, because most errors are `InnerTubeError` cases with no personal data. Still, a cancelled `URLError` passes through `attemptOnce` unwrapped (`InnerTubeClient.swift:334`) and carries its request URL.
- Whichever `OSLogInterpolation` overload matched, the output is the error's description. I could not run `log stream` to see it rendered, so the QA check below confirms it.

**Scenario.** The user launches offline, or the network drops during a load. `didFailProvisionalNavigation` returns -1009 or -1001, which is not ignorable (`PlayerRules.swift:74-77`). The watchdog then reloads up to twice, and each failure writes one more line. Every line holds the track and playlist the user was playing and, when signed in, their `authuser` slot. These are `.error` messages, which the unified log persists to disk; `.info` stays in memory, which is why 3.1 L1 was only Low. They are kept for days. Any admin user can read them with `log show`, and they are included in a sysdiagnose that a user attaches to a bug report. An unlisted playlist ID in that log is enough to open the playlist. This reverses the 3.1 L1 decision to hash the video ID, and it breaks the caller's Apple check "no `privacy: .public` on sensitive values".

**Why Medium.** The data is listening history plus playlist IDs, persisted, and the trigger (an offline launch) is ordinary. Reading the log needs local access or a shared sysdiagnose, and nothing can be exploited remotely.

**Recommended fix** (all in `PlayerEngine.swift`):
1. `:372`: replace the line with `let failure = error as NSError` and `Self.log.error("navigation failed: \(failure.domain, privacy: .public) \(failure.code, privacy: .public)")`.
2. `:168`: the same pattern, `let failure = error as NSError` and `Self.log.error("page call \(call.action, privacy: .public) failed: \(failure.domain, privacy: .public) \(failure.code, privacy: .public)")`.
3. `:185`: the same pattern, `Self.log.error("rate failed: \(failure.domain, privacy: .public) \(failure.code, privacy: .public)")`. An `InnerTubeError` bridges to a stable domain and code. If the case name is wanted, `\(String(describing: error as? InnerTubeError), privacy: .public)` is safe, because no `InnerTubeError` case carries a URL or ID.
4. Leave `:327` (`bridge.js unreadable`) as is. A bundle file-read error holds no personal data.
5. QA check: with `debugVideoId` set, launch with the network off and run `log stream --level debug --predicate 'subsystem == "dev.kruhlyk.redwave"'`. No line may contain `v=`, `list=` or `authuser=`.

## Out of scope

### Low

#### L1. The `rate` closure reports success when the session is not signed in — `App/RedwaveApp.swift:46`

**Issue.** `guard case .signedIn(let cookies) = session.state else { return }` returns normally. `PlayerEngine.setLike` (`PlayerEngine.swift:178-184`) treats a normal return as success: it sets `like = status` and emits `likeChanged(status)` for a write that never happened. This is the silent-failure pattern: a failure is turned into a neutral value.

**When.** The engine's view is still the signed-in one (`isEphemeral == false`, `song` set) while `session.state` is already `.signedOut` or `.keychainUnavailable`. This is the 3.1 L3 window, between the end of sign-out or expiry and the SwiftUI re-render that calls `stop()`. The UI then shows a like that is not on the account.

**Fix.** `guard case .signedIn(let cookies) = session.state else { throw InnerTubeError.signInRequired }`. The enum is public (`InnerTubeClient.swift:3`, `:12`), and the engine's `catch` (`PlayerEngine.swift:184-186`) logs it and emits nothing.

#### L2. The truthy `window.__bridge` guard is still there, so the page can pre-empt the bridge and Swift calls an impostor `run` — `bridge.js:2`

**Issue.**
- Plan §4, bridge.js (a), said to replace `if (window.__bridge) return;`. The frozen, non-configurable define at `:100` was added, but line 2 is unchanged. `02-development.md` does not list this as a deviation.
- Any truthy `window.__bridge` that exists at document end makes the script return before it defines anything. That covers a page script running `window.__bridge = { run: … }`, or an element with `id="__bridge"` (named-property DOM clobbering).
- Since this change, Swift calls `window.__bridge.run(action, args)` (`PlayerEngine.swift:164`). Every command then goes to the page's function, which can return `true`, and the bridge never attaches, so no events arrive.

**Why Low.** Only the trusted `music.youtube.com` top frame can do this, and that frame already holds the session. The impostor receives action names, indices, validated IDs, numbers and booleans, never a token. Swift reads back only a `Bool`. The result is a stuck or spoofed player, not data exposure. This partly re-opens 3.1 Info 1.

**Fix.** Delete line 2.
- A `WKUserScript` runs once per document, so the guard has no legitimate use.
- DOM named properties live on the prototype chain, so the own-property `defineProperty` at `:100` shadows them.
- A `window.__bridge = …` assignment creates a configurable own property, which `defineProperty` redefines.
- A page `var __bridge` creates a non-configurable property, so `defineProperty` throws and aborts the script before `ready`. The Swift watchdog then reports `playerTimeout` instead of the player being silently hijacked.

#### L3. The reload cap resets on every restore, so a crash that recurs after each restore reloads forever — `PlayerEngine.swift:272`

**Issue.** `commit` sets `attempts = 0` unconditionally, including when it commits the song that a crash restore brought back (`resumeAt != nil`). A track or page state that crashes the WebContent process shortly after each restore then loops: crash, reload (attempt 1), commit (attempts 0), crash, and so on, with no end. Each loop respawns a WebContent process and reloads the page. `02-architecture.md:220-222` promises "at most twice, then gives up silently".

**Fix.** At `:272-276`, reset the counter only for a commit that is not a restore:
```swift
if let resume = resumeAt {
    resumeAt = nil
    if newSong.videoId == target?.videoId { send(.seek(to: resume)) }
} else {
    attempts = 0
}
```
A normal song change and `load()` (`:133`) still reset it. Add one case to `RecoveryTests`: set `resumeAt`, call `nextRecoveryURL()` once, commit the same song, and expect `engine.attempts == 1`.

#### L4. A track that was unavailable once is never reported as unavailable again in the same page — `bridge.js:103`, `:111-114`

**Issue.**
- `lastUnavailable` dedupes `error {kind: "unavailable"}`, but it is reset only by another unavailable ID, never by a playable song.
- So after A (unavailable), then B (plays), then A again, the second A posts nothing.
- Swift then sees no `song` and no `unavailable`. The watchdog emits `playerTimeout` after 15 s and reloads twice. The user waits about 45 s and gets the wrong error, where they should have had an immediate `unavailable` (silent-failure checklist).

**Fix.** In `postSong`, reset the dedupe when a playable song is posted. Insert `lastUnavailable = null;` just before `post({ type: 'song', … })` at `:118`. The dedupe still collapses the repeated `videodatachange`, `loadedmetadata` and ad-end calls for the same unavailable track.

### Info

1. **A pre-roll ad longer than 15 s trips the watchdog** (`PlayerEngine.swift:196-201`, `:248-250`; `bridge.js:106`).
   - `postSong` posts nothing while `adShowing`, and `.ad(true)` does not touch the watchdog.
   - For a guest with a 15–30 s pre-roll, the engine emits `playerTimeout` and reloads mid-ad (which can start a new ad), up to twice.
   - This is not a security issue. QA should look for it under MC-D.
   - Fix: in `handle(.ad)`, cancel the watchdog when `playing` is true. The `song` posted when the ad ends (`bridge.js:203`) then commits normally.
2. **Delegate callbacks are not tied to the current view** (`PlayerEngine.swift:357-374`, `:389-406`).
   - One `WebDelegate` serves every `WKWebView` the engine creates.
   - `didCommit`, `didFail…` and `webViewWebContentProcessDidTerminate` do not check which view called. A late callback from a torn-down view (still kept alive by an in-flight `send` task) can set `isReady = false`, or emit `contentProcessCrashed` and set `resumeAt` against the new view.
   - Fix: pass the `webView` through and guard `webView === self.webView` in `navigationCommitted`, `navigationFailed` and `contentProcessTerminated`.
3. **`run` throws away the exception** (`bridge.js:95-97`).
   - During the owner's probe, "operation threw" and "path missing / row mismatch" both appear as `page refused <action>`.
   - Fix: `catch (error) { console.error('__bridge', action, error); return false; }`. This is visible in Web Inspector, where `isInspectable` is on in DEBUG, and it does not reach the unified log.
4. **A `401` from `rate` is logged and dropped** (`PlayerEngine.swift:184-186`).
   - `AccountModel` treats an index-0 `unauthorized` as session expiry (`AccountModel.swift:27-29`, `:40-46`). The like path does not, so a revoked session shows nothing on a like until the next account load.
   - Fix: leave it to #16 or 4.x. Have the closure in `RedwaveApp` call `session.expireSession(cookies:)` on `InnerTubeError.unauthorized` when `session.authUserIndex == 0`.

### Carry-over tracking

- **Closed by this change** (from 3.1 / #13):
  - **M1.** Names are capped at 1024 UTF-8 bytes before `cleanupName`, and `duration` must be finite and ≥ 0 (`SongInfo.swift:37`, `:79-83`). Tests are at `SongInfoTests.swift:26`, `:32-34`.
  - **L1.** `songChanged` logs the ID as `.private(mask: .hash)` (`PlayerEngine.swift:285`). M1 above re-opens the same exposure on the error paths.
  - **L2.** A guest load passes `authUserIndex: nil` (`PlayerEngine.swift:128`, `:210`).
  - **L4.** A missing or unreadable `bridge.js` is logged at `.fault` (`PlayerEngine.swift:319-330`).
  - **Info 5.** The two reject rows were added (`PlayerRulesTests.swift:15`).
- **Partly closed:**
  - **3.1 Info 1** (`__bridge` pre-emption). The frozen, non-configurable define was added, but the truthy guard was left in place (L2 above).
  - **3.1 Info 3** (failures as events). Crash, timeout and load failure now emit `PlayerEvent.error`. The dropped-message counter is still open.
  - **3.1 L3** (teardown ordering). The per-cookie generation check (`PlayerEngine.swift:87-90`) and the reworded comments (`RedwaveApp.swift:70`, `02-architecture.md:69`) are done. The strict-order hook (`AuthSession.willWipeSignedInData`) is not. The window is now a little wider: an armed watchdog or a crash `reload()` can navigate the signed-in view to `/signin` between `signOut()` starting the wipe and the re-render that calls `stop()`. It stays Low, because guests are unaffected and a page load cannot write `SAPISID`/`SID`. The clean fix is still option 3 of 3.1 L3.
- **Still open, unchanged:**
  - 3.1 Info 2 (the HEAD `URLSession` per song, skipped as YAGNI in plan §8) and 3.1 Info 4 (the hit-testable host view, depends on MC-1).
  - issue-7 L1 (5.4 deep links), issue-7 Info 1, 2 and 3.
  - issue-11 L1 and L2, issue-11 Info 1, 2 and 3.
  - issue-10 L1–L4, issue-10 Info 1–4.
  - issue-9 L2, issue-9 Info 2–5.
  - issue-8 L2 and L3, issue-8 Info 1, 2, 3, 8, 9 and 10.
  - rename-redwave Info 7.

## Severity summary

| Severity | Count | Next step |
|---|---|---|
| Critical | 0 | — |
| High | 0 | — |
| Medium | 1 | M1: log only `domain` and `code` of the errors at `PlayerEngine.swift:168`, `:185` and `:372`. Three one-liners, recommended for the fix pass. |
| Low | 4 | L1: `throw InnerTubeError.signInRequired` in the `rate` closure. L2: delete `bridge.js:2`. L3: reset `attempts` only on a non-restore commit, plus one test. L4: `lastUnavailable = null` before posting a song. All are one-liners and can join the fix pass. |
| Info | 4 | Info 1 is for QA under MC-D. Info 2 and 3 are cheap now. Info 4 is for #16 / 4.x. |
