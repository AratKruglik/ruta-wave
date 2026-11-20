# Development report: player commands, queue, recovery, debug window

Branch `feature/player-commands-queue`. Nothing committed. `.gitignore` and `.claude/` untouched.

## Project shape
XcodeGen (`project.yml`, scheme Redwave), macOS 14, Swift 6.0, SwiftUI, `@MainActor @Observable`, Swift Testing, no persistence, no String Catalog. `xcodegen generate` was run (the project is gitignored). No `project.yml`, entitlement, Info.plist or dependency change.

## Files created
- `Packages/PlayerEngine/Sources/PlayerEngine/PlayerCommand.swift` (model)
- `.../PlayerState.swift` (model: LikeStatus, RepeatMode, PlayerError)
- `.../QueueItem.swift` (model + validator)
- `Packages/PlayerEngine/Tests/PlayerEngineTests/BridgeCallTests.swift`, `RecoveryTests.swift`, `LivePlaybackTests.swift` (opt-in, `REDWAVE_LIVE_TESTS=1`), `Fixtures/queue.json`
- `App/PlayerDebugView.swift` (screen, whole file `#if DEBUG`)

## Files modified
`BridgeMessage.swift`, `PlayerEvent.swift`, `PlayerRules.swift`, `PlayerEngine.swift`, `Resources/bridge.js`, `BridgeMessageTests.swift`, `PlayerEngineTests.swift`, `PlayerRulesTests.swift`, `App/RedwaveApp.swift`, `docs/02-architecture.md` (§4.2-4.4).

## Decisions
1. All page access is a named operation in a frozen table behind a frozen `__bridge.run`; a missing path returns `false`, Swift logs it. Operations may be async (enqueue).
2. Command to page-call mapping is the pure `PlayerRules.bridgeCall`, so the volume clamp, NaN refusal and queue guard are unit-tested without a web view. The recovery decision is the pure `nextRecoveryURL()` for the same reason.
3. Queue guard: index plus `videoId` plus `playlistSetVideoId` sent with every queue operation; JS refuses on mismatch. JS flattens rows (unwraps the wrapper renderer) so Swift parses a compact projection; one invalid row rejects the whole message.
4. `repeat` and `shuffle` are two separate bridge messages (not one `modes`), so each message emits exactly one event.
5. Recovery: Swift watchdog (15 s), one attempt counter (cap 2) shared by crash, timeout and load failure; every failure emits its `error`, retries stop silently at the cap. `unavailable` cancels the watchdog. Restore re-announces the song (dedupe bypass) and seeks on the committed song.

## Deviations from the plan
- `seek(by:)` is `skip(by:)`. Swift cannot pattern-match two enum cases that differ only by label (ambiguous use of 'seek'). §4.3 in `02-architecture.md` is updated; the issues #16/#21/#22 should use `skip(by:)`.
- The shuffle/repeat attribute-observer fallback and the ad "videoId differs from the selected queue row" fallback are not implemented (YAGNI until the probe shows the primary paths are missing).
- Like drift and the `like` read: JS re-posts `like` on every `videodatachange`, with no dedupe.
- Info 5 of the 3.1 security review: added `https://www.youtube.com/watch?v=x` and `https://accounts.google.com/` to the `rejects` arguments. The dropped-message counter (Info 3) is out of scope.
- `PlayerEngine.init(isReachable:playerTimeout:)` gained a defaulted `playerTimeout` (internal).

## Needs owner verification (the plan's step 1 probe was not run: no browser)
Every one of these is reference-only (pear-desktop) or unknown, and is recorded as such in `02-architecture.md` §4.2:
next/previous button selectors, `updateVolume`, `queue.shuffle()`, `onRepeatButtonClick`, `onVolumeClick`, queue store path and `subscribe` (`#queue.queue.store.store`), `like-status` on `#like-button-renderer`, `SET_INDEX` (does it start playback), `REMOVE_ITEM`, `MOVE_ITEM`, `ADD_ITEMS` and the `networkManager.fetch('/music/get_queue')` enqueue (field names `queueContextParams`, `selectedItemIndex`, `nextQueueItemId`, `queueDatas[].content` were written from memory of pear and are the least certain), `ad-showing` / `ad-interrupting` class, `playabilityStatus.status`, whether shuffle is a mode, `__bridge.run` being callable through `callAsyncJavaScript` in `.page` world.
Manual checks MC-A to MC-F and AC-7 are still the owner's. MC-1 (background audio) unchanged.

## Verification
- `swift test` in `Packages/PlayerEngine`: 66 tests, 9 suites, pass (live test skipped without the env var).
- `xcodebuild -project Redwave.xcodeproj -scheme Redwave -destination 'platform=macOS' build`: clean, no warnings (Debug and Release). The Release binary has no `PlayerDebugView` symbol.
- `node --check bridge.js`: ok. bridge.js itself was not exercised against the live page.

## Blockers
None for the next phase; the live probe results can change which JS fallbacks are needed.

## Security fix pass

Fixes from `04-security.md`, applied as prescribed (owner approved M1, L1-L4):

- M1 (`PlayerEngine.swift`): the three error logs (page call failed, rate failed, navigation failed) now log only `(error as NSError).domain` and `.code`, both `.public`. The failing-URL key no longer reaches the log.
- L1 (`RedwaveApp.swift`): the `rate` closure throws `InnerTubeError.signInRequired` when not signed in, so the engine does not report a like that never happened.
- L2 (`bridge.js`): the truthy `window.__bridge` guard is removed. The frozen, non-configurable define is wrapped in `try/catch` that returns, so a page-defined `__bridge` cannot pre-empt ours and a second injection does not throw or double-register listeners.
- L3 (`PlayerEngine.swift`): `commit` resets `attempts` only when not restoring (`attempts = 0` moved into the `else` of `if let resume = resumeAt`). Test added: `restoreCommitKeepsTheAttemptCount` in `RecoveryTests.swift`.
- L4 (`bridge.js`): `lastUnavailable = null;` is set before the `song` post.

Verification: `swift test` in `Packages/PlayerEngine` passes; the `Redwave` macOS scheme builds clean (project `Redwave.xcodeproj`; the repo holds two projects, so `-project` is required).
