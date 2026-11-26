# Owner checklist: Web Audio chain spike (#40)

Drive everything from Web Inspector. The chain is disabled by default and nothing in the app calls it.

## Preconditions

- DEBUG build.
- Safari, Develop, then the RutaWave player page, so Web Inspector is attached to the player web view.
- Start playback **before** running `enable()`.

## Decision rule for silence

- `contextState` is `suspended`, or `resumeResult` is `timeout` or an error name: an autoplay or policy finding, **not** CORS. Record it, run `__bridge.audio.enable()` again after clicking play in the app, and treat it as a separate question.
- `contextState` is `running`, `paused` is `false`, `probe().attached` is `true`, `probe().sourceError` is `null` and `probe().nonZero` is `false` (repeat twice): a tainted stream, counts toward **no-go**.
- `sourceError.name` is `SecurityError`: also counts toward no-go. Record the message.
- Any other attach failure (`attached: false`, or a `sourceError` other than `SecurityError`, for example `InvalidStateError` because the page owns a source for the element): **not** a CORS result. Record it and treat it as a separate question.

## Checks

| ID | Steps | Pass |
|---|---|---|
| MC-W1 | Signed in, album track: `await __bridge.audio.enable()`, then `await __bridge.audio.probe()`. Then `setGain(0)`, `setGain(1)`, `setGain(2)` in turn | `running`, `nonZero: true`, silent at 0 while `currentTime` advances, normal at 1, louder at 2. Record `src` and `crossOrigin` |
| MC-W2 | Same as MC-W1 for a signed-in music video (OMV) | Same as MC-W1 |
| MC-W3 | Same as MC-W1 for a guest session track | Same as MC-W1 |
| MC-W4 | `const c = __bridge.audio.context(); const g = c.createGain(); g.gain.value = 0.2; __bridge.audio.insert('test', g)`. Then go to the next track and let a track auto-advance | `keys` still holds `test`, output stays quieter, `elementCurrent: true` |
| MC-W5 | Guest session, during an audio ad and after it: `probe()` and `setGain(0)` | Record whether the ad passes the chain. A bypass is acceptable but must be documented. After the ad the chain routes again |
| MC-W6 | Trigger a reload (recovery, or a guest/signed-in switch), read `__bridge.audio.state()`, enable again | `enabled: false` first, then enabling works again |
| MC-W7 | With the chain on, change the app volume and mute | Output follows, and the volume slider still round-trips |
| MC-W8 | With the chain on, open Control Centre | One RutaWave entry; play, pause, next and previous work |
| MC-W9 | With the chain on, hide the app or close all windows | Audio continues |
| Element swap | Compare `state().elementCurrent` across the checks above | Record "not observed" or that a reattach happened |

## Also record

- any `interrupted` value in `states` (after sleep or wake, or after unplugging headphones);
- the stream type (`blob:` means MSE).

## Verdict

Write go or no-go into `docs/05-risks-and-scope.md` risk 7, replacing "pending owner".
