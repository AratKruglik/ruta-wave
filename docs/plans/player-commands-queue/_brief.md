# Brief

PlayerEngine commands, queue access, failure recovery and debug test window — GitHub issue AratKruglik/yt-music-mac#14. Branch: feature/player-commands-queue.

## Issue #14 (verbatim)

Backlog row **3.2** of [06](https://github.com/AratKruglik/yt-music-mac/blob/develop/docs/06-backlog.md). Requirements: F-PLY-2, F-PLY-4, F-PLY-7 ([00 §5](https://github.com/AratKruglik/yt-music-mac/blob/develop/docs/00-prd.md)).

## Goal

Full control of the site player from Swift, a queue that cannot drift from the page, and self-recovery.

## Scope
- [ ] Every `PlayerCommand`: play, pause, togglePlay, next, previous, seek(to:), seek(by:), setVolume, toggleMute, toggleShuffle, cycleRepeat, setLike, playQueueItem, load
- [ ] Events for the rest of the contract: `volumeChanged`, `likeChanged`, `repeatChanged`, `shuffleChanged`, `queueChanged`, `error`
- [ ] Queue through the bridge: read `[QueueItem]`; play next, add to queue, remove, move, jump. The page stays the source of truth (02 §4.4)
- [ ] Ad state exposed to the UI (the bar shows "Ad" and disables seek and next)
- [ ] Failure handling: page did not load; player did not appear within N seconds; track unavailable or region-blocked; web view process crashed → reload and restore the track and position
- [ ] `setLike` and other account-only commands gated on `AuthSession.State.isSignedIn`
- [ ] Debug window (debug builds): `videoId` field, a button per command, live event log
- [ ] Integration test: load → `songChanged` → pause → seek

## Done when
- [ ] ⛔ By hand, in the debug window: a track plays, every command works, the log shows a correct event stream
- [ ] Killing the WebContent process returns playback to the same track and position within 10 s (PRD §7.2)
- [ ] Queue changes made from Swift are visible in the page queue and the other way round
- [ ] Integration test passes locally

## Dependencies

Blocked by: #13

Blocks: #16, #21, #22

## References

[02 §4.3, §4.4](https://github.com/AratKruglik/yt-music-mac/blob/develop/docs/02-architecture.md) · [03 Stage 3](https://github.com/AratKruglik/yt-music-mac/blob/develop/docs/03-roadmap.md) · [08 §9](https://github.com/AratKruglik/yt-music-mac/blob/develop/docs/08-ui-spec.md) · [00 §7.2](https://github.com/AratKruglik/yt-music-mac/blob/develop/docs/00-prd.md)

## Delivery

Branch `feature/player-commands-queue`, PR into `develop`. One SDLC pipeline run:

```
/sdlc:start "PlayerEngine commands, queue access, failure recovery and debug test window" --type=feature
```

## Owner decisions (after business analysis, 2026-11-20)

1. `setLike` goes through the existing InnerTube `rate(videoId:_:credentials:)`, not through the page DOM. Gated on `AuthSession.State.isSignedIn`. Decide in the plan which layer (PlayerEngine vs App) calls InnerTube; avoid adding an InnerTube dependency to PlayerEngine unless justified.
2. Unverified page internals (queue, like state, repeat/shuffle, ad detection, unavailable-track signal): spike inside this issue. The architect researches the live page (and pear-desktop as a reference) during planning and marks in the plan whatever turns out unreachable.
3. Recovery: "player did not appear" timeout N = 15 s, at most 2 reload attempts. The engine only emits `error`; the "toast + skip after 3 s" for unavailable tracks belongs to the UI (#16), not the engine.
