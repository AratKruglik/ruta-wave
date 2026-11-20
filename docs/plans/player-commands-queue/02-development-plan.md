# Development plan: PlayerEngine commands, queue access, failure recovery and debug test window

Issue #14 · backlog 3.2 · branch `feature/player-commands-queue` → `develop`
Inputs: `_brief.md` (with the owner decisions of 2026-11-20) and `01-business-analysis.md`.

## 1. Detected project shape

| Key | Value |
|---|---|
| Project system | XcodeGen (`project.yml`). `Redwave.xcodeproj` is gitignored and generated, and has no `PBXFileSystemSynchronizedRootGroup`. **A new file in `App/` is compiled only after `xcodegen generate`.** |
| Targets | One app target, `Redwave` (macOS 14.0, `SWIFT_VERSION` 6.0), scheme `Redwave`. Local SPM packages are under `Packages/`. PlayerEngine uses `swift-tools-version: 6.0`, `.macOS(.v14)` and depends only on `Auth`. |
| UI / state | SwiftUI app lifecycle. `@MainActor @Observable` models (`PlayerEngine`, `AccountModel`). No TCA and no `ObservableObject`. |
| Persistence | None for the player. The recovery snapshot is held in memory only. |
| Navigation | A single `WindowGroup` with no router. |
| Networking | `InnerTubeClient` (InnerTube package), used from App models with `Credentials(cookies:authUserIndex:)`. |
| Localization | No String Catalog or `.strings` files. Debug-window strings are DEBUG-only and stay unlocalized. |
| Tests | Swift Testing in `Packages/PlayerEngine/Tests/PlayerEngineTests`, with `@MainActor` structs and `PlayerEngine { _ in true }`. |
| Lint | No `.swiftlint.yml`. |
| Consumers of `PlayerEvent` outside the package | **None.** A grep of `App` and `Packages/*` found no switch to break. |

Build check: `xcodegen generate && xcodebuild -project Redwave.xcodeproj -scheme Redwave -destination 'platform=macOS' -quiet build`, plus `swift test` in `Packages/PlayerEngine`.

## 2. Spike: page internals (owner decision 2)

Sources:
- **[MC-5]**: verified live on 2026-11-19 (02 §4.2).
- **[pear]**: `pear-devs/pear-desktop` at its HEAD commit of 2026-11-16, in `src/renderer.ts`, `src/providers/song-info-front.ts` and `src/types/{queue,datahost-get-state}.ts`.
- **[general]**: common YouTube player knowledge, not found in pear.

No live probe was run during planning, because this subagent had no browser tool. **The first implementation step is a live presence probe** in Web Inspector (`isInspectable` is already on in DEBUG). It runs one `evaluate` on a guest page with a track playing and checks every "reference-only" row below. Results are recorded in 02 §4.2 as "verified presence, Safari Web Inspector, <date>". If a primary path is missing, the implementer switches that row to its fallback.

| Item | Access path (primary) | Confidence | Fallback | Manual check |
|---|---|---|---|---|
| play / pause | `#movie_player.playVideo()` / `pauseVideo()` | verified [MC-5] | none | MC-A |
| togglePlay | `getPlayerState() === 2 ? playVideo() : pauseVideo()` (pear's logic) | verified methods [MC-5] | none | MC-A |
| next / previous | click `.next-button.ytmusic-player-bar` / `.previous-button.ytmusic-player-bar` [pear]. The queue-aware buttons, not `nextVideo()`, which may bypass the YTM queue. | reference-only | `#movie_player.nextVideo()` / `previousVideo()` [MC-5] | MC-A |
| seek(to:) | `seekTo(sec)` | verified [MC-5] | none | MC-A, AC-7 |
| seek(by:) | `seekTo(max(0, getCurrentTime() + delta))` | verified methods [MC-5] | none | MC-A |
| setVolume | `ytmusic-player-bar.updateVolume(0…100)` [pear]. It keeps the page slider and stored volume in sync, so the page does not re-apply its old volume on the next track. | reference-only | `#movie_player.setVolume(0…100)` [MC-5]. Risk: the next track may revert it. | MC-A: check that the volume survives a track change |
| toggleMute | `isMuted() ? unMute() : mute()` | verified [MC-5] | `ytmusic-player-bar.onVolumeClick()` [pear] | MC-A |
| volume read | the `<video>` `volumechange` event → `{volume: getVolume(), muted: isMuted()}` | verified getters [MC-5]; event is standard DOM | none | MC-A |
| toggleShuffle | `ytmusic-player-bar.queue.shuffle()` [pear]. Not `setShuffle`, whose semantics are unverified. | reference-only | click `.shuffle.ytmusic-player-bar` | MC-A |
| shuffle read | `shuffleEnabled` from the queue store state; failing that, the `shuffle-on` attribute on `ytmusic-player-bar` [pear] | reference-only. **Semantics unknown**: YTM shuffle may be a one-shot reshuffle rather than a mode. | the attribute observer | MC-A: record whether shuffle is a mode or a reshuffle |
| cycleRepeat | `ytmusic-player-bar.onRepeatButtonClick()` [pear]. Not `setLoop`. | reference-only | click `.repeat.ytmusic-player-bar` | MC-A: off → all → one → off |
| repeat read | `queue.repeatMode` ∈ `NONE`/`ALL`/`ONE` from the queue store state [pear: `ytmusic-player-bar.getState().queue.repeatMode`] | reference-only | MutationObserver on `#right-controls .repeat[title]` [pear] | MC-A |
| like read | the `like-status` attribute on `#like-button-renderer` (`LIKE`/`DISLIKE`/`INDIFFERENT`), with a MutationObserver plus a read on each song [pear] | reference-only | none: `like` stays `.indifferent` and the row is marked unreachable | MC-A |
| like write | **InnerTube `rate(videoId:_:credentials:)`** (owner decision 1). The page is not used. | verified (existing code) | none | MC-A (signed in), AC-3 (guest) |
| queue read and subscribe | `document.querySelector('#queue').queue.store.store` → `getState().queue.{items, repeatMode, shuffleEnabled}` and `.subscribe(cb)`. Rows are `playlistPanelVideoRenderer`, or `playlistPanelVideoWrapperRenderer.primaryRenderer.playlistPanelVideoRenderer`, each with `videoId`, `title.runs`, `longBylineText.runs`, `thumbnail.thumbnails`, `lengthText.runs`, `selected` and `playlistSetVideoId` [pear] | reference-only | `#queue.queue.getItems()` re-read on a `videodatachange` (no subscription) | MC-C |
| add to queue (play next / at end) | `ytmusic-app.networkManager.fetch('/music/get_queue', {queueContextParams, queueInsertPosition: 'INSERT_AFTER_CURRENT_VIDEO' or 'INSERT_AT_END', videoIds:[id]})` → `#queue.dispatch({type:'ADD_ITEMS', payload:{nextQueueItemId, index, items, shuffleEnabled:false, shouldAssignIds:true}})` [pear, verbatim] | reference-only | **unreachable**: report in 02 §4.2 and refuse the command | MC-C |
| remove | `#queue.dispatch({type:'REMOVE_ITEM', payload:index})` [pear] | reference-only | none | MC-C |
| move | `#queue.dispatch({type:'MOVE_ITEM', payload:{fromIndex,toIndex}})` [pear] | reference-only | none | MC-C |
| jump (playQueueItem) | `#queue.dispatch({type:'SET_INDEX', payload:index})` [pear, `PATCH /queue`] | reference-only. Whether it **starts playback** is unknown. | click the row's `ytmusic-player-queue-item` play button | MC-C |
| ad state | a MutationObserver on the `class` attribute of `#movie_player`; `ad-showing` (or `ad-interrupting`) means an ad is playing | **unknown** [general; pear has no ad detection] | while `ad-showing` cannot be confirmed, `getPlayerResponse().videoDetails.videoId` differs from the queue's selected `videoId` | MC-D (guest session) |
| unavailable / region-blocked | `getPlayerResponse().playabilityStatus.status !== 'OK'` (`UNPLAYABLE`, `LOGIN_REQUIRED`, `ERROR`, `AGE_CHECK_REQUIRED`), checked **before** the `videoDetails` guard in `postSong`. Today an unplayable track stalls silently. | reference-only [pear types; pear downloader uses the same field] | the Swift watchdog fires `playerTimeout` when no `song` arrives | MC-E |
| player appears | the `#movie_player`, `<video>` and `ytmusic-app` wait (existing) | verified [3.1] | none | n/a |
| WebContent crash | `webViewWebContentProcessDidTerminate` (existing hook) | verified API | none | MC-B |

Anything still missing after the probe is recorded in 02 §4.2 as "unreachable". The matching command is refused and logged, and its event is never emitted.

## 3. Public surface (contract for #16, #21, #22)

### Contract for frontend

The aspect is `none`, so there is no HTTP contract. This is the Swift API that the UI issues build on:

```swift
public enum PlayerCommand: Sendable, Equatable {
    case play, pause, togglePlay, next, previous
    case seek(to: TimeInterval), seek(by: TimeInterval)
    case setVolume(Double)                 // 0…1, clamped; NaN is refused
    case toggleMute, toggleShuffle, cycleRepeat
    case setLike(LikeStatus)               // signed-in only, via the injected `rate`
    case playQueueItem(index: Int)
    case enqueue(videoId: String, playNext: Bool)
    case removeQueueItem(index: Int)       // the current item is refused
    case moveQueueItem(from: Int, to: Int)
    case load(videoId: String, playlistId: String?)
}

public enum PlayerEvent: Sendable, Equatable {
    case ready, songChanged(SongInfo), playbackChanged(isPaused: Bool, elapsed: TimeInterval), timeChanged(TimeInterval)
    case volumeChanged(volume: Double, isMuted: Bool)   // 0…1
    case likeChanged(LikeStatus)
    case repeatChanged(RepeatMode)
    case shuffleChanged(Bool)
    case queueChanged([QueueItem])
    case adChanged(Bool)
    case error(PlayerError)
}

public enum LikeStatus: Sendable { case like, dislike, indifferent }
public enum RepeatMode: Sendable { case off, all, one }
public enum PlayerError: Sendable, Equatable {
    case pageLoadFailed, playerTimeout, unavailable(videoId: String), contentProcessCrashed, signInRequired
}
public struct QueueItem: Sendable, Equatable {
    public let videoId: String; public let title: String; public let artist: String
    public let artworkURL: URL?; public let duration: TimeInterval; public let isCurrent: Bool
}

// PlayerEngine additions
public func send(_ command: PlayerCommand)
public private(set) var volume: Double, isMuted: Bool, like: LikeStatus, repeatMode: RepeatMode,
                         isShuffled: Bool, queue: [QueueItem], isAd: Bool
public var rate: (@MainActor (_ videoId: String, _ status: LikeStatus) async throws -> Void)?
```

- `load(videoId:playlistId:)` stays public. `send(.load)` forwards to it.
- `seeked` (Q6) is left out: the bridge already turns `seeked` into `timeChanged`.
- `queue` holds only the main queue. The Autoplay/automix section (Q7) is excluded. The queue is capped at 500 rows: JS trims, and Swift rejects anything larger.
- A queue index refers to a position in the last `queueChanged`. The engine attaches the expected `videoId` (and `playlistSetVideoId`) of that row, and JS refuses the operation if the row no longer matches. The same check covers duplicate ids and stale indices.

## 4. Files

### Create (PlayerEngine package)

| File | Type | Purpose |
|---|---|---|
| `Packages/PlayerEngine/Sources/PlayerEngine/PlayerCommand.swift` | model | The `PlayerCommand` enum. |
| `Packages/PlayerEngine/Sources/PlayerEngine/PlayerState.swift` | model | `LikeStatus`, `RepeatMode` and `PlayerError`. Raw-value parsers `init?(page:)` take `LIKE`/`DISLIKE`/`INDIFFERENT` and `NONE`/`ALL`/`ONE`. These are small and live in one file to avoid a file per tiny enum. |
| `Packages/PlayerEngine/Sources/PlayerEngine/QueueItem.swift` | model | `QueueItem`, plus internal `playlistSetVideoId: String?` for the race guard and a `static func parse(_:)`-style validator in the `SongInfo` style: valid id, 1 KiB name cap, allowed artwork host, `lengthText` "m:ss" or "h:mm:ss" → seconds (finite, ≥ 0). A message with any invalid row is rejected **whole**, because dropping rows would shift indices. |
| `Packages/PlayerEngine/Tests/PlayerEngineTests/BridgeCallTests.swift` | test | Command → bridge-call mapping: volume clamp, NaN refused, seek(by:) args, queue guard args. |
| `Packages/PlayerEngine/Tests/PlayerEngineTests/RecoveryTests.swift` | test | Recovery target, attempt cap, dedupe bypass, ad time not recorded. |
| `Packages/PlayerEngine/Tests/PlayerEngineTests/LivePlaybackTests.swift` | test (opt-in) | AC-7. Runs only `.enabled(if: ProcessInfo.processInfo.environment["REDWAVE_LIVE_TESTS"] == "1")`. Starts as a guest, attaches the web view to an offscreen `NSWindow`, loads `dQw4w9WgXcQ` and waits for `songChanged`, then `pause`, `playbackChanged(isPaused: true)`, `seek(to: 30)`, `timeChanged` ≈ 30 ± 1, with a 30 s overall timeout. |
| `Packages/PlayerEngine/Tests/PlayerEngineTests/Fixtures/queue.json` | fixture | A trimmed queue message as `bridge.js` posts it, written by hand with illustrative ids like the existing fixture. Covers a wrapped row, a selected row and `lengthText` in h:mm:ss. |

### Create (App)

| File | Type | Purpose |
|---|---|---|
| `App/PlayerDebugView.swift` | screen (DEBUG) | Whole file inside `#if DEBUG`. Text fields for `videoId` and `playlistId`, one button per `PlayerCommand`, sliders and steppers for the seek and volume values, a queue list (play / play next / remove / move up / move down per row) and a live event log fed by `.task { for await e in player.events() }`, newest last, capped at 500 lines. It never hosts or re-parents the web view. Built from small subviews (`CommandGrid`, `QueueSection`, `EventLog`). Every control gets an accessibility label, and fonts and colors come from the system. |

### Modify

| File | Change |
|---|---|
| `Packages/PlayerEngine/Sources/PlayerEngine/Resources/bridge.js` | (a) Replace `if (window.__bridge) return;` and the method-name whitelist with `Object.defineProperty(window, '__bridge', {value: Object.freeze({run}), writable:false, configurable:false})`. Here `run(action, args)` looks the action up in a frozen null-prototype table of named operations (section 2) and returns `true`/`false`. Capture the message handler at injection time. (b) Add `volumechange`, a like observer, the queue-store `subscribe` (one push source for queue, repeat and shuffle, debounced by about 100 ms, posting only when the compact projection's JSON string changes, trimmed to 500 rows) and the `#movie_player` class observer for ads. (c) In `postSong`, check `playabilityStatus` first and post `{type:'error', kind:'unavailable', videoId}`. Skip posting `song` while an ad shows. Send no reason text. (d) Shorten the wait deadline from 30 s to 15 s; Swift owns the error. |
| `Packages/PlayerEngine/Sources/PlayerEngine/BridgeMessage.swift` | Add `.volume(Double, muted: Bool)` (page 0…100 → 0…1; non-finite or out-of-range values rejected), `.like(LikeStatus)`, `.modes(repeat: RepeatMode, shuffle: Bool)`, `.queue([QueueItem])`, `.ad(Bool)` and `.unavailable(videoId:)`. Strict decode, the same 256 KiB cap, unknown types dropped. Add the extra `Envelope` fields as optionals. |
| `Packages/PlayerEngine/Sources/PlayerEngine/PlayerEvent.swift` | Add the new cases. |
| `Packages/PlayerEngine/Sources/PlayerEngine/PlayerRules.swift` | Add `maxReloadAttempts = 2`, `playerTimeout: Duration = .seconds(15)` and `maxQueueItems = 500`. Add `static func bridgeCall(for: PlayerCommand, queue: [QueueItem]) -> (action: String, args: [Any])?`, a pure function with the volume clamp, the queue-guard id lookup and refusal of a current-item remove; `load` and `setLike` return nil. Add `parseDuration(_ lengthText:)`. Add the two reject rows the 3.1 security review asked for (Info 5). |
| `Packages/PlayerEngine/Sources/PlayerEngine/PlayerEngine.swift` | `send(_:)`; the new observable properties; `rate`; `handle(_:)` cases for the new messages; recovery (section 5); `WebDelegate` gains `didFailProvisionalNavigation` and `didFail`; `stop()` resets all new state; `emit` gets log rules per case (queue logged as a count only, `unavailable` ids hashed). |
| `Packages/PlayerEngine/Tests/PlayerEngineTests/BridgeMessageTests.swift` | AC-1 for each new type, including malformed, oversize, NaN, bad id and > 500 rows. |
| `Packages/PlayerEngine/Tests/PlayerEngineTests/PlayerEngineTests.swift` | AC-2 (each new message updates state and emits exactly one event), AC-3 (a guest `setLike` → `error(.signInRequired)` and the `rate` spy is never called), AC-5 (`send` before start or ready does nothing and does not crash), AC-6 (a repeat message maps to `RepeatMode`), ad gating. |
| `App/RedwaveApp.swift` | Set `player.rate` once, in `startPlayer()` or on first appearance. The closure reads `session.state` for cookies and `session.authUserIndex`, maps `LikeStatus` → `Rating` and calls `InnerTubeClient().rate(videoId:_:credentials:)`. Under `#if DEBUG`, add `Window("Player Debug", id: "player-debug") { PlayerDebugView(player: player) }`. A `Window` scene appears in the Window menu automatically, so no command is needed. Keep the `debugVideoId` launch hook, which is still useful. |
| `docs/02-architecture.md` | §4.2: the probe results (section 2 table, verified or unreachable). §4.3: the contract as built (`enqueue`/`remove`/`move`, `adChanged`, `error`, no `seeked`, volume 0…1). §4.4: the queue guard and the 500-row cap. A new paragraph for the recovery policy. |

No new dependencies. `Package.swift` is unchanged: PlayerEngine does **not** depend on InnerTube.

## 5. Recovery design

All recovery state lives in `PlayerEngine` as `@ObservationIgnored` fields, in memory only:
- `target: (videoId, playlistId)?`. It is set by `load()` and updated on each committed `songChanged`, so a crash right after `load` restores the requested id, not a stale one.
- `position`. It is `elapsed`, which is **not** updated while `isAd` (ad time never reaches the snapshot).
- `attempts: Int`. It is shared by crash, timeout and load failure, and reset to 0 when a song for the target commits.
- `resumeAt: TimeInterval?`
- `watchdog: Task<Void, Never>?`. Its generation is the `webView` identity plus a load counter.

Flow:
1. `load()` and every recovery reload start the watchdog: sleep `PlayerRules.playerTimeout`. If the task is not cancelled, the same view is still current and no `song` for the target has arrived, emit `error(.playerTimeout)` and run `reload()`. The first committed `song` cancels it. A Swift timer is used because a JS timer dies with the crashed process.
2. `contentProcessTerminated()`: set `resumeAt = position`, emit `error(.contentProcessCrashed)` and run `reload()` immediately to meet the 10 s budget.
3. `navigationFailed(error)` (`didFailProvisionalNavigation` or `didFail`): ignore `NSURLErrorCancelled` (-999) and WebKit 102 (frame load interrupted), which a superseding `load` or the navigation lock produce. Otherwise emit `error(.pageLoadFailed)` and let the watchdog drive the retry, so an offline launch makes at most 2 extra loads and stops.
4. `reload()`: `guard attempts < maxReloadAttempts, let webView, let target`. Otherwise it logs "gave up"; the last `error` stands and no further error is emitted (owner decision 3). It increments `attempts` and loads `PlayerRules.loadURL(... authUserIndex: isEphemeral ? nil : authUserIndex)`, so a signed-in session goes through `/signin` with the **current** index. The navigation lock is unchanged.
5. Restore: while `resumeAt != nil`, `handle(.song)` bypasses the `videoId` dedupe, so `songChanged` fires again for the same track and consumers see the restore. In `commit`, when the song is the target and `resumeAt` is set, send `seekTo(resumeAt)` and clear it. The seek happens on the song, not on `ready`, because with `/signin`, `ready` can come before the video.
6. `stop()` and `start()` (a guest/signed-in switch or sign-out) cancel the watchdog and clear `target`, `resumeAt` and `attempts`. Every async step checks `webView === view`.
7. An `unavailable` message emits `error(.unavailable(videoId:))` only. Skipping is the UI's job (#16).

## 6. Command gating (Q5, stated as an assumption)

- If the player is not started, not `isReady`, or `webView.url?.host != music.youtube.com`, the command is ignored and logged. No `error`. `load` is exempt.
- **While an ad plays, `next`, `seek(to:)` and `seek(by:)` are refused by the engine** (logged, no `error`). The UI also disables them (#16).
- `setLike` from a guest (`isEphemeral`), or with no `rate` injected, or with no `song`, emits `error(.signInRequired)` and nothing else; this is the only refusal that emits an error. For a signed-in user, `rate` is called. On success the engine sets `like` and emits `likeChanged`. On failure it logs and emits nothing.
- Volume: `setVolume(x)` is clamped to 0…1 and multiplied by 100 for the page. NaN or infinity is refused.
- Commands go through `webView.callAsyncJavaScript("return window.__bridge.run(action, args)", arguments: [...], in: nil, contentWorld: .page)`. There is no string building. A `false` result is logged.

## 7. Implementation order

1. **Probe (manual, about 15 min):** run the section 2 presence checks in Web Inspector on a guest page and fix the primary and fallback per row.
2. Models: `PlayerCommand`, `PlayerState`, `QueueItem` (+ parse), with the `PlayerRules` additions and their unit tests.
3. `BridgeMessage` decode for the new types, plus tests and the `queue.json` fixture.
4. `PlayerEvent` cases; `PlayerEngine.handle` for the new messages and observable state; `emit` logging; tests.
5. `bridge.js`: frozen `__bridge.run`, the operation table, observers and subscribe, playability, ad suppression.
6. `PlayerEngine.send` and gating; `rate` injection; tests.
7. Recovery: watchdog, crash, navigation failure, restore; `RecoveryTests`.
8. App: wire `rate`, add the `PlayerDebugView` and the `Window` scene; run `xcodegen generate` and build.
9. Opt-in `LivePlaybackTests`.
10. `docs/02-architecture.md` §4.2–4.4.
11. Verification: `swift test` (offline), `REDWAVE_LIVE_TESTS=1 swift test --filter LivePlayback` (local), and the `xcodebuild` Debug build. Release build check for MC-F: `-configuration Release` builds with no `PlayerDebugView` symbol.

## 8. Design decisions

1. **setLike goes through an injected closure.** `PlayerEngine.rate` is set by App, which calls InnerTube. It keeps the single `send` entry point and the offline-testable guest gating in the engine (AC-3), and adds no InnerTube dependency to PlayerEngine (owner decision 1). An App-only route would split the command surface and move AC-3 out of the testable package.
2. **One page push source for queue, repeat and shuffle:** the queue Redux store's `subscribe`, with a debounced compact projection that is posted only on change. There is no polling (the 3 % CPU budget), and trimming keeps messages far below 256 KiB.
3. **Named bridge operations instead of `#movie_player` method names.** The queue-aware player-bar methods are used where pear shows that the raw player methods bypass the YTM queue. `__bridge` is frozen and non-configurable (3.1 Info 1).
4. **The Swift-side watchdog and a single attempt counter are shared by crash, timeout and load failure** (15 s and 2 attempts, owner decision 3). The engine only emits `error`, and the skip on an unavailable track is left to #16.
5. **Queue ops are index-based with a row-identity guard** (`videoId` + `playlistSetVideoId` checked in JS). Swift keeps only a display mirror that `queueChanged` replaces wholesale (02 §4.4).

Skipped on purpose (YAGNI): a `seeked` event, an Autoplay section, a "gave up" error case, queue clear, an `error` on refused commands, and the 3.1 Info 2 HEAD-session reuse.

## 9. Convention skills to invoke during implementation

`apple-plugin:swiftui-conventions`, `apple-plugin:swiftui-state`, `apple-plugin:macos-app` (the `Window` scene), `apple-plugin:apple-testing`, `swift-foundation:swift-conventions` (strict concurrency, `Sendable`, `@MainActor` closure), `swift-foundation:swift-testing` (`.enabled(if:)` traits, async confirmation), `swift-foundation:swift-tooling` (the XcodeGen regenerate step). `apple-plugin:swiftui-navigation` is not needed because no navigation changes.

## 10. Risks and edge cases

- **R1: every queue, like, repeat, shuffle, ad and unavailable path is reference-only or unknown.** The step-1 probe and MC-A/C/D/E are mandatory. Any path that is unreachable is recorded and its command is refused.
- **Ad detection is unknown** (`ad-showing` comes from general YouTube knowledge, not pear). If the class is absent on YTM, `isAd` never turns on, so seek and next are not gated during ads.
- **Like drift.** After an InnerTube like, the hidden page's `like-status` is stale. The engine emits `likeChanged` itself, but the page observer may re-emit the stale value for the same track (repeat-one, previous). Manual check under MC-A.
- **Shuffle may be a one-shot reshuffle, not a mode.** If so, `shuffleChanged` may never fire. Record what the probe finds and keep `isShuffled` as whatever the page reports.
- **Whether `SET_INDEX` starts playback** is unknown. The fallback is clicking the row.
- **Volume set through `#movie_player.setVolume` may be reverted on the next track.** That is why the player-bar `updateVolume` is primary.
- **Navigation errors -999 and WebKit 102 must not become `pageLoadFailed`.** A consent redirect on a fresh guest store is cancelled by the lock and leads to the watchdog `playerTimeout` after 15 s, bounded by 2 reloads.
- **A crash during an ad:** the snapshot excludes ad time, and the restore may play an ad first. The seek is deferred until the target song commits.
- **Live integration test:** WKWebView under `swift test` needs an `NSWindow` and a main run loop, and the consent wall can block a guest. It is opt-in through an env var, so "passes locally" depends on the network and on Google.
- **MC-1 (background audio) is still listed as a manual check** in 02 §4.1. Confirm it before sign-off.
- **The debug window must not add a third `PlayerHost`.** It only reads `player` state.
- **New `App/` file:** `xcodegen generate` is required, because the project uses no buildable folders and is gitignored.

## 11. Manual checks for the owner (⛔)

| Check | What |
|---|---|
| Probe | Section 2 presence checks in Web Inspector (dev step 1). |
| MC-A | In the debug window, every command produces its page effect and event; the log is ordered; volume survives a track change; repeat cycles off → all → one; like works signed in and is refused for a guest. |
| MC-B | Kill the WebContent process: the same track resumes at ±3 s within 10 s, for a guest and for a signed-in session. |
| MC-C | Play next, add, remove, move and jump from Swift show in the page queue; a page edit shows in `queueChanged`. |
| MC-D | In a guest session, `isAd` turns on during an ad, and seek and next are refused. |
| MC-E | An unavailable or region-blocked id emits `error(.unavailable)` and does not stall. |
| MC-F | A Release build has no Player Debug window. |
| AC-7 | `REDWAVE_LIVE_TESTS=1 swift test --filter LivePlayback` passes locally. |
