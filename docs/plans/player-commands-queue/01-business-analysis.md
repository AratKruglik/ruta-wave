# Business Analysis: PlayerEngine commands, queue access, failure recovery and debug test window

Issue #14 · backlog row 3.2 · branch `feature/player-commands-queue` → `develop` · blocked by #13 (merged, PR #61) · blocks #16, #21, #22

## Executive summary

3.1 (#13) proved that the hidden `WKWebView` plays and that the page streams `ready`, `songChanged`, `playbackChanged` and `timeChanged` to Swift. The only command it has is `load`. 3.2 completes the two-way contract. Swift drives every player control. Swift reads and edits the page-owned queue. The rest of the state is published as events: volume, like, repeat, shuffle, queue, ads and errors. The player recovers on its own from load failures, stalls and WebContent crashes. A DEBUG-only test window exercises all of it by hand.

Sources: brief (#14), 00 §5 F-PLY-2/4/7, 00 §7.2, 02 §4.1–4.4, 03 Stage 3, 08 §9/§10.2, prior work in `docs/plans/player-bridge/*`.

Step 0 (grill-me) was skipped. `mattpocock-skills:grill-me` is not installed, and a subagent cannot interview the user, so the questions are under "Open questions".

## Functional requirements

| # | Requirement | Source | Codebase status |
|---|---|---|---|
| FR-1 | `PlayerCommand` enum and a single entry point for: `play`, `pause`, `togglePlay`, `next`, `previous`, `seek(to:)`, `seek(by:)`, `setVolume`, `toggleMute`, `toggleShuffle`, `cycleRepeat`, `setLike`, `playQueueItem(index:)`, `load(videoId:playlistId:)` | brief, 02 §4.3, 03 Stage 3 | Missing. Only `PlayerEngine.load(videoId:playlistId:)` exists. `bridge.js` has a `__bridge.cmd` whitelist with no Swift caller. |
| FR-2 | New events: `volumeChanged(volume:isMuted:)`, `likeChanged(LikeStatus)`, `repeatChanged(RepeatMode)`, `shuffleChanged(Bool)`, `queueChanged([QueueItem])`, `error(PlayerError)`. Observable state mirrors them for the UI. | brief, 02 §4.3, 08 §9 "Data" | Missing. `PlayerEvent` has 4 cases. `seeked` is in 02 §4.3 but **not in the brief** (conflict C2). |
| FR-3 | Queue through the bridge: read `[QueueItem]`; play next, add to queue, remove, move, jump. The page stays the single source of truth, and Swift keeps no authoritative copy. | brief, 02 §4.4, 08 §10.2, F-PLY-4 | Missing in both JS and Swift. 02 §4.3 has only `playQueueItem(index:)`, so the contract must grow (conflict C1). |
| FR-4 | Ad state is exposed. While an ad plays, the bar shows "Ad" and disables seek and next. | brief, 08 §9 States, 05 risk 12 | Missing. 02 §4.3 has no ad event or field, so this is a new contract item. Ads are not blocked or skipped (05 risk 12). |
| FR-5 | Failure handling: the page fails to load; the player does not appear within N s; the track is unavailable or region-blocked; the WebContent process crashes. On a crash or stall, reload and restore the same track and position within 10 s. | brief, 03 Stage 3, F-PLY-7, 00 §7.2, 08 §9 States | Partial. `contentProcessTerminated()` and `navigationCommitted()` only clear `isReady`. There is no `didFail…` handler. `bridge.js` gives up silently after a hard-coded 30 s. No error event exists. |
| FR-6 | `setLike` and other account-only commands are gated on `AuthSession.State.isSignedIn`. A guest gets a refusal or error, never a page call. | brief, 08 §9 Guest | `isSignedIn` exists (`AuthSession.swift:137`). The engine knows guest vs. signed-in only via the private `isEphemeral`. `setLike` has two possible routes (conflict C3). |
| FR-7 | DEBUG-only test window: a `videoId` (and optional `playlistId`) field, one button per command, a live event log. | brief, 03 Stage 3 "Done when" | Missing. A DEBUG launch-argument hook (`debugVideoId`/`debugPlaylistId`) exists in `RedwaveApp.startPlayer()`. |
| FR-8 | Integration test: load → `songChanged` → pause → seek, against the live page. | brief, 02 §11, 03 Stage 3 | Missing. All current tests are offline unit tests with `PlayerEngine { _ in true }`. |

## Non-functional requirements

- **Performance:** crash or stall recovery to the same track and position within 10 s (00 §7.2). The hidden-window CPU budget of ≤ 3 % (00 §7.1) still applies, so queue polling, if used, must not raise it. The 4 Hz `timeChanged` must not invalidate observers of `song` or the queue (02 §4.3).
- **Security:**
  - Swift→JS only through `callAsyncJavaScript` with arguments (no string building), in `.page` world, guarded by the `music.youtube.com` host check before every call (02 §4.1).
  - Every new JS→Swift message (queue, like, repeat, shuffle, volume, ad, error) is untrusted input. It gets the same treatment as `song`: the 256 KiB cap, `PlayerRules.isValidID` on ids, string length caps and finite non-negative numbers (pattern from 04-security M1, `SongInfo.parse`).
  - No URL from a message is ever opened.
  - Carry-over 04-security Info 1: the `__bridge` pre-emption guard (`bridge.js:2` is still `if (window.__bridge) return;`).
- **Privacy and logging:** follow the existing `Logger` pattern. Ids are logged hashed and titles/artists `.private`. Queue contents are not logged in clear. Debug-window logging is DEBUG-only.
- **Compliance:** none beyond the PRD rule that the app talks only to Google. The navigation lock (`PlayerRules.isAllowedMainFrameNavigation`) must not be widened by recovery reloads.
- **Concurrency:** `PlayerEngine` stays `@MainActor @Observable` (Swift 6 strict concurrency, `swift-tools-version: 6.0`).

## User stories (Gherkin)

### Story 1: Control playback from Swift
**As a** downstream module (player bar #16, media keys, plugins)
**I want** to send any `PlayerCommand` and receive the matching state event
**So that** I never touch the page directly

**Acceptance criteria:**
- Given a track is playing, When `pause` is sent, Then `playbackChanged(isPaused: true, …)` arrives and `engine.isPaused == true`.
- Given a track is playing at t, When `seek(to: 30)` is sent, Then a time event arrives with elapsed ≈ 30 (±1 s).
- Given position p, When `seek(by: -10)` is sent, Then elapsed ≈ max(0, p − 10).
- Given volume v, When `setVolume(0.4)` is sent, Then `volumeChanged(volume: 0.4, isMuted: false)` arrives. The value range is open question Q4.
- Given repeat is off, When `cycleRepeat` is sent three times, Then `repeatChanged` reports all → one → off (08 §9).
- Given the player is not started or not ready, When any command is sent, Then it is ignored, logged and does not crash. Whether it also emits `error` is open question Q5.

### Story 2: Queue that cannot drift
**As a** listener using the Up next view (#21)
**I want** queue edits in the app and on the page to show up on both sides
**So that** the app never plays something other than what it shows

**Acceptance criteria:**
- Given a playlist is loaded, When the page queue changes for any reason, Then `queueChanged([QueueItem])` arrives with the page's order and the current item marked.
- Given a queue, When Swift sends "play next" for a track, Then the page queue has it right after the current item and a `queueChanged` reflects it.
- Given a queue, When Swift removes item i (i ≠ current), Then the page queue no longer has it. Removing the current item is refused (08 §10.2).
- Given a queue, When Swift moves item i to j, Then the page order matches.
- Given a queue, When `playQueueItem(index: i)` is sent, Then `songChanged` reports item i.
- Given the engine holds no queue copy, When `queueChanged` is the only source, Then no Swift-side mutation state outlives the next event.

### Story 3: Self-recovery
**As a** listener
**I want** playback to come back by itself after a crash or stall
**So that** I don't have to restart the app (F-PLY-7)

**Acceptance criteria:**
- Given a track plays at position p, When the WebContent process is killed (Activity Monitor or `kill` on the `com.apple.WebKit.WebContent` pid), Then within 10 s the same `videoId` plays from p ± 3 s. The tolerance is a proposal (Q-tolerance).
- Given recovery happens, Then `error(…crashed…)` is emitted first and the restore is reported, so consumers are not left "loading". A same-track restore must be observable even though `handle(.song)` dedupes by `videoId` (`PlayerEngine.swift:118`).
- Given a signed-in session, When recovery reloads, Then it goes through `PlayerRules.loadURL`, i.e. `/signin?…authuser=…`, never a bare `/watch`.
- Given the player element never appears within N s after a load, Then `error(playerTimeout)` is emitted and the bounded retry policy (Q2) runs. It must not reload forever.
- Given a main-frame navigation fails or is cancelled (consent wall, offline), Then `error` is emitted.

### Story 4: Unavailable tracks and ads
**As a** listener
**I want** an unavailable or region-blocked track to be reported, and ads to be visible as ads
**So that** the bar behaves like the site (08 §9 States)

**Acceptance criteria:**
- Given a track is unavailable or region-blocked, When it loads, Then `error(unavailable…)` is emitted with the `videoId`. Who skips to the next track after 3 s is open question Q2.
- Given a guest or non-Premium session, When an ad starts, Then the ad state turns on, and turns off when the ad ends.
- Given an ad is playing, When `next` or `seek` is sent, Then it is refused or ignored. Whether the engine enforces this or only the UI disables it is open question Q5.
- Given an ad is playing, Then no `songChanged` is emitted for the ad itself.

### Story 5: Account-only commands and the debug window
**As a** developer verifying 3.2 by hand
**I want** a DEBUG window with a `videoId` field, a button per command and a live event log
**So that** I can sign off on "Done when" without the real UI

**Acceptance criteria:**
- Given a guest session, When `setLike` is sent, Then nothing reaches the page or the network, and a sign-in-required outcome is reported.
- Given a signed-in session, When `setLike(.like)` is sent, Then `likeChanged(.like)` arrives and the site shows the track as liked.
- Given a DEBUG build, When the window is opened, Then every `PlayerCommand` has a control and each event appears in the log in order. Given a Release build, Then the window and its menu item do not exist.
- The debug window never hosts or re-parents the web view. It stays in `PlayerHost` (02 §4.1).

## Data model sketch

All models are new types in `PlayerEngine`, `Sendable` and `Equatable` like `SongInfo`.

- **PlayerCommand:** the cases in FR-1. To be decided in the plan: either it is extended with queue cases (`addToQueue`/`playNext`, `removeFromQueue`, `moveInQueue`), or queue edits get their own entry point. The original had `get-queue`, `add-to-queue`, `remove-from-queue`, `move-in-queue`, `set-queue-index` and `clear-queue` (01 §4.4).
- **PlayerEvent:** the existing 4 cases plus `volumeChanged`, `likeChanged`, `repeatChanged`, `shuffleChanged`, `queueChanged`, `error`. `seeked` is optional (C2). An ad-state case or field is new (C4).
- **QueueItem:** `videoId` (validated), `title`, `artist`, optional `album`, `artworkURL` (allowed hosts only, `PlayerRules.isAllowedArtworkHost`), `duration` (finite ≥ 0), `isCurrent`. A page-side identity for move and remove is needed if the same `videoId` appears twice. Whether to show the "Autoplay" section (08 §10.2) is open.
- **LikeStatus:** like / dislike / indifferent. It duplicates InnerTube's `Rating` (`Mutations.swift`) (C3).
- **RepeatMode:** off / all / one.
- **PlayerError:** pageLoadFailed, playerTimeout, unavailable(videoId), contentProcessCrashed, signInRequired, and possibly commandFailed. No raw page text or URLs inside.
- **Recovery snapshot:** the last `videoId`, `playlistId` and position. It is in memory only and lives in the engine, which already keeps `song` and `elapsed`. It is not persisted.
- **Observable state on `PlayerEngine`:** add volume, isMuted, like, repeat, shuffle, queue (a display mirror only, replaced wholesale on each `queueChanged`) and isAd.

## API contract sketch

There is no HTTP API. The contract has two layers.

**Swift public surface (`PlayerEngine`)**
- `send(_ command: PlayerCommand)` or one method per command. The style is left to the plan, and `load` keeps its current behaviour.
- `events() -> AsyncStream<PlayerEvent>` is unchanged: fan-out with a 64-event buffer.
- The observable properties above.
- The engine needs to know whether the session is signed in to gate FR-6. It already has the private `isEphemeral` from `start(_:)`.

**Bridge protocol (`bridge.js` ↔ Swift)**
- JS→Swift message types (new): `volume {volume, muted}`, `like {status}`, `repeat {mode}`, `shuffle {on}`, `queue {items[]}`, `ad {on}`, `error {kind}`. Optionally `seeked {time}`. Each one is a JSON string ≤ 256 KiB (`BridgeMessage.maxBytes`) and decoded strictly; anything unknown is dropped.
- Swift→JS: commands go only to whitelisted names. The existing whitelist (`bridge.js:8-11`) is `playVideo`, `pauseVideo`, `stopVideo`, `seekTo`, `setVolume`, `mute`, `unMute`, `nextVideo`, `previousVideo`, `loadVideoById`, `setShuffle`, `setLoop`. Queue, like, repeat-cycle and ad detection are **not** `#movie_player` methods verified by MC-5. They need page internals that must first be verified on the live page (risk R1).

## Edge cases & error scenarios

- **Queue larger than 256 KiB** (long playlist or radio): the message is silently dropped by `BridgeMessage.decode`. The plan needs a cap, trimming or paging.
- **Duplicate `videoId`s in a queue:** an index or page id is needed for remove and move.
- **Index races:** an edit is sent with index i while the page queue has already changed (autoplay appended, track advanced). Stale indices must not remove or move the wrong row.
- **Removing the current item** is refused (08 §10.2).
- **Repeat-one or a same-track recovery:** the `song` dedupe (`PlayerEngine.swift:118`) suppresses `songChanged`, so the restore must still be observable.
- **Crash during an ad:** the restore lands on the track, and an ad may play again before it.
- **Crash right after `load`** before `songChanged`: the recovery target is the requested id, not the stale `song`.
- **Recovery loop:** the page crashes repeatedly, or the track keeps failing. The retry count must be bounded and end in an `error`.
- **Sign-out or a guest↔signed-in switch during recovery:** `start(_:)` recreates the view, and recovery must not reload into a stale or torn-down view (the `webView === view` checks in `start`).
- **Account switch while playing:** the new `authUserIndex` applies only to the next `load`, a known 3.1 limit. Recovery reloads with the *current* index.
- **Consent wall or foreign-host redirect on a fresh guest store:** the navigation is cancelled by the lock, which must surface as `error`, not as a silent stall.
- **Commands before `ready`** or while `webView == nil`: ignored and logged, no crash.
- **Debug window open under Cmd-N or multiple windows:** `WindowGroup` already lets two `PlayerHost`s compete for one view (a 3.1 known issue). The debug window must not add a third host.
- **App launched with no network:** the page-load error appears and recovery does not spin.
- **Guest `setLike`:** no page click and no InnerTube call.
- **Volume out of range or NaN from Swift or the page:** clamp or reject.

## Risks & dependencies

- **R1 (high): most of the scope rests on unverified page internals.** MC-5 verified only `#movie_player` methods. Reading the queue, editing it (add, remove, move), like state, repeat mode (off/all/one vs. `setLoop`), shuffle state, ad state and the unavailable or region-blocked signal all need page structures nobody has checked. `togglePlay` and `seek(by:)` must be composed from verified calls. A live-page verification step (like MC-5) with a record in 02 §4.2 must come before or inside the dev phase. The original's `pear-desktop` source is the documented fallback (03 Stage 3).
- **R2: MC-1 (background audio go/no-go for #14).** 02 §4.1 still lists it as a manual check. Confirm it passed before building on it.
- **R3: setLike route (C3).** InnerTube already has `rate(videoId:_:credentials:)`. A bridge-side like duplicates it. An InnerTube route means `PlayerEngine` takes on an InnerTube dependency (`Package.swift` depends only on Auth) or the logic moves into App.
- **R4: the integration test is live.** It needs network, a stable public `videoId` and probably a window or run loop for WKWebView. It must be opt-in (for example via an environment variable or a separate test plan) so a plain `swift test` stays offline and deterministic. There is no CI.
- **R5:** the hard-coded 30 s give-up in `bridge.js` vs. "N seconds" and the 10 s recovery budget.
- **Carry-overs that 3.1 deferred to 3.2** (`docs/plans/player-bridge/04-security.md`, `02-development-plan.md`). Each must be marked in or out of scope:
  - Info 1: the `__bridge` freeze/guard. **In** (command path).
  - Info 3: `error` from cancelled or failed navigation, the 30 s give-up and process termination, plus a counter for dropped messages. **In** (FR-5).
  - Info 2: HEAD-check session reuse and redirect rejection. Proposed out, cheap.
  - Info 4: the alpha-0 host hit-testing. Depends on MC-1.
  - Info 5: two extra reject rows in `PlayerRulesTests`. Cheap.
  - The optional `AuthSession.willWipeSignedInData` hook. Proposed out.
  - Competing `PlayerHost`s under Cmd-N. Proposed out (UI, #16).
- **Dependencies:** #13 is merged (PR #61). This work blocks #16 (player bar), #21 (queue UI) and #22.

## Codebase impact (context package for dev)

| File | Impact |
|---|---|
| `Packages/PlayerEngine/Sources/PlayerEngine/PlayerEngine.swift` | Command entry point via `callAsyncJavaScript`; new observable state; recovery (crash, stall, failed navigation); auth gating; new `didFail…` delegate methods on `WebDelegate`; error emission. |
| `Packages/PlayerEngine/Sources/PlayerEngine/PlayerEvent.swift` | New cases. Mind exhaustive `switch`es in `emit(_:)` (log policy per case). |
| `Packages/PlayerEngine/Sources/PlayerEngine/BridgeMessage.swift` | New message types, strict validation, the size cap. |
| `Packages/PlayerEngine/Sources/PlayerEngine/Resources/bridge.js` | Event listeners (`volumechange`, like, repeat, shuffle, queue, ad, error), queue reading and editing, hardened `__bridge`, a configurable or shorter wait. |
| `Packages/PlayerEngine/Sources/PlayerEngine/PlayerRules.swift` | Pure rules to reuse or add: id validation, artwork host check, clamping, `loadURL` for recovery. |
| New: `PlayerCommand`, `QueueItem`, `LikeStatus`, `RepeatMode`, `PlayerError` (PlayerEngine module) | Follow the `SongInfo` style: `Sendable`, `Equatable`, parse-with-validation. |
| `Packages/PlayerEngine/Tests/PlayerEngineTests/*` | Unit tests through `handle(_:)` and `BridgeMessage.decode` with fixtures (`Fixtures/` resource exists), plus the opt-in live integration test. Swift Testing (`@Test`, `#expect`), `@MainActor` suites. |
| `App/RedwaveApp.swift` | DEBUG window scene or menu item. Decide whether to keep or replace the `debugVideoId` launch hook. |
| New DEBUG view in `App/` | Test window. `project.yml` sources are `[App]`, so a new file is picked up automatically. DEBUG-only via `#if DEBUG`. |
| `docs/02-architecture.md` §4.2–4.4 | Record the verified page internals, the extended contract and the recovery policy. |

**Patterns to follow:**
- `handle(_:)` returns the emitted event for testability.
- Pure logic lives in `PlayerRules` (an enum with static functions).
- The engine is created in tests with `PlayerEngine { _ in true }`.
- Logging uses `Logger(subsystem: "dev.kruhlyk.redwave", category: "player")` with `.private` for personal data.

## Verifiable acceptance criteria

**Automated (offline unit tests)**
- AC-1: each new bridge message decodes to the right `BridgeMessage`. Malformed, oversize, non-finite or bad-id payloads decode to `nil`.
- AC-2: `handle(_:)` updates observable state and emits exactly one matching event for volume, like, repeat, shuffle, queue, ad and error.
- AC-3: a guest engine refuses `setLike` (and the other account-only commands) without any JS call or network request, and reports sign-in required.
- AC-4: the recovery target after a crash is the last known `videoId`, `playlistId` and position. The reload URL goes through `PlayerRules.loadURL` (the `/signin` path when signed in).
- AC-5: commands while not started or not ready are ignored with no crash.
- AC-6: `cycleRepeat` maps off → all → one → off. Volume input is clamped.

**Automated (opt-in live integration test)**
- AC-7: load a known public `videoId` → `songChanged` with that id within T s → `pause` → `playbackChanged(isPaused: true)` → `seek(to: x)` → elapsed ≈ x.

**Manual (MC checks, ⛔ in the brief)**
- MC-A: in the debug window, every command button produces the expected page effect and event, and the log is in order and correct.
- MC-B: killing the WebContent process restores the same track at ±3 s within 10 s, for a guest and for a signed-in session.
- MC-C: a queue edit from Swift (play next, add, remove, move, jump) appears in the page queue, and a page edit appears in `queueChanged`.
- MC-D: a guest session shows the ad state during an ad, and `next` and `seek` are disabled or refused.
- MC-E: an unavailable or region-blocked id emits `error(unavailable)` and does not stall.
- MC-F: a Release build has no debug window.

## Open questions for stakeholders

1. **Q1, setLike route and the account-only list.** Does like go through the page (02 §4.3) or InnerTube `rate(videoId:)` (08 §9, already implemented)? Which commands besides `setLike` are "account-only"? Possibly the queue ops on a signed-in-only "Save queue", but that is #21.
2. **Q2, failure policy.** What is N for "player did not appear"? How many retries before giving up? Who owns "toast + skip to next after 3 s" for unavailable tracks (08 §9): the engine, or the UI in #16?
3. **Q3, sequencing.** Should the live-page verification of the queue, like, repeat, shuffle, ad and unavailable internals and the `PlayerCommand` queue extension come first as a spike (an MC-5-style record in 02 §4.2), or run inside this issue?
4. Q4: is the `setVolume` scale 0…1 (Swift) or 0…100 (the `#movie_player` scale)?
5. Q5: does the engine itself refuse `next` and `seek` during ads and before `ready`, or does only the UI disable them? Should a refused command emit `error`?
6. Q6: is `seeked` (02 §4.3) in scope? The brief omits it.
7. Q7: should the queue include the page's "Autoplay" section, and is there a size cap for very long queues?
8. Q-tolerance: what position tolerance does "same position" allow (proposed ±3 s)?

## Estimated complexity

**large.** It covers 14 commands, 6+ events, a new queue protocol over unverified page internals, a recovery state machine, auth gating, a DEBUG window and a live integration test, across Swift, JS and the App target.
