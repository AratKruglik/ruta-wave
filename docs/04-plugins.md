# 04. The original's plugins and what happens to them

41 plugin identifiers were found in the original **[bundle]**.

The "What it does" column is based on the plugin name and general knowledge of
the `pear-desktop` project. Plugins were **not traced** individually; before
implementing one, check its source in the repository.

Labels in the "Decision" column:
- **S5 / S6 / S7** — ported at that stage ([03-roadmap.md](03-roadmap.md));
- **Built in** — in a native interface this is an ordinary property, not a plugin;
- **If needed** — implemented only if it turns out to be wanted;
- **Later** — deferred by a decision, not scheduled ([#12](https://github.com/AratKruglik/yt-music-mac/issues/12));
- **No** — not ported.

| # | Plugin | What it does | Decision | In the Swift version |
|---|---|---|---|---|
| 1 | `album-actions` | action buttons for a whole album (like or dislike all tracks) | Built in | album context menu |
| 2 | `album-color-theme` | interface theme from the artwork colour | S7 | average artwork colour through Core Image → accent and background |
| 3 | `ambient-mode` | blurred glow around the video or artwork | S7 | blurred artwork as the player background |
| 4 | `amuse` | integration with the 6K Labs Amuse widget | If needed | through `api-server` |
| 5 | `api-server` | local HTTP and WebSocket control API | S7 | `Network.framework`, `/api/v1/*` routes as in the original |
| 6 | `audio-compressor` | dynamic range compressor | S7 | `DynamicsCompressorNode` in the page |
| 7 | `auth-proxy-adapter` | support for authenticated proxies (SOCKS) | No | the system proxy is used |
| 8 | `blur-nav-bar` | blurred navigation bar | Built in | SwiftUI materials |
| 9 | `captions-selector` | caption selection | Later (#12) | command through the bridge, menu in the player |
| 10 | `clock` | shows a clock in the interface | If needed | — |
| 11 | `crossfade` | smooth transition between tracks | S7 | Web Audio in the page; the hardest of the audio plugins |
| 12 | `custom-output-device` | audio output device selection | S7 | `setSinkId` in the page, or the system picker |
| 13 | `disable-autoplay` | do not start playback automatically | S6 | pause after `songChanged` under a condition |
| 14 | `discord` | Discord Rich Presence | S6 | Discord's local IPC socket, no SDK |
| 15 | `do-not-track` | blocks analytics requests | No | the same class of interference as ad blocking |
| 16 | `downloader` | downloads tracks to files | **No** | violates YouTube's terms and copyright |
| 17 | `equalizer` | equalizer | S7 | `BiquadFilterNode` in the page, native slider UI |
| 18 | `exponential-volume` | exponential volume curve | S6 | transform the value before `setVolume` |
| 19 | `in-app-menu` | app menu inside the window | Built in | the system menu bar |
| 20 | `lumiastream` | Lumia Stream integration | If needed | through player events |
| 21 | `music-together` | listening together over PeerJS | If needed | needs WebRTC; a project of its own |
| 22 | `navigation` | back and forward buttons | Built in | `NavigationStack` |
| 23 | `notifications` | track-change notifications | S5–S6 | `UNUserNotificationCenter` |
| 24 | `performance-improvement` | web page optimizations | No | a native UI does not need them |
| 25 | `picture-in-picture` | picture-in-picture mode | Later (#12) | music videos only; needs a visible web view |
| 26 | `playback-speed` | playback speed | S6 | `video.playbackRate` through the bridge |
| 27 | `precise-volume` | precise volume step, hotkeys | S6 | logic in Swift, value through the bridge |
| 28 | `quality-changer` | quality selection | S6 | player method through the bridge |
| 29 | `scrobbler` | Last.fm and ListenBrainz | S6 | `URLSession`, keys in the Keychain |
| 30 | `shortcuts` | global hotkeys | S6 | Carbon `RegisterEventHotKey` |
| 31 | `skip-disliked-songs` | skips disliked tracks | S6 | `next` after `songChanged` if the status is dislike |
| 32 | `skip-silences` | skips silence | S7 | Web Audio analyser in the page |
| 33 | `sponsorblock` | skips segments using SponsorBlock data | S7 | request to `sponsor.ajay.app`, seek on a timer |
| 34 | `synced-lyrics` | synchronized lyrics with romanization | S6 | a separate screen; romanization later |
| 35 | `taskbar-mediacontrol` | buttons on the Windows taskbar | No | Windows only |
| 36 | `touchbar` | Touch Bar controls | S7 | `NSTouchBar`; low priority |
| 37 | `transparent-player` | transparent player window | Built in | window materials |
| 38 | `tuna-obs` | sends the track to OBS (Tuna plugin) | If needed | HTTP request to a local port |
| 39 | `unobtrusive-player` | hides the player while scrolling | Built in | player bar behaviour |
| 40 | `video-toggle` | switches between video and artwork | Later (#12) | the native UI shows artwork by default; video is a separate mode |
| 41 | `visualizer` | audio visualization | S7 | `AnalyserNode` → data to Swift → `Canvas` |

## Summary

| Decision | Count |
|---|---|
| S5–S6 (first wave) | 11 |
| S7 (second wave) | 11 |
| Built into the native UI | 6 |
| If needed | 5 |
| Not ported | 5 |
| Later (music video mode, #12) | 3 |

## Notes

- **Ad blocking.** The `@ghostery/adblocker-electron` library is among the
  original's dependencies, but text search found no separate entry for it among
  the 41 plugin identifiers — it may be enabled another way or have a different
  name. The Swift version does not implement ad blocking.
- **Audio plugins** (6, 11, 12, 17, 32, 41) run inside the player page: the app
  injects JS that builds a Web Audio graph around the `<video>` element. Only
  the settings interface is native. Risk: several such plugins must share one
  graph, so `bridge.js` needs a common "audio chain".
- **Lyrics romanization** in the original pulls in heavy dictionaries (kuromoji,
  pinyin-pro and others). The first version of `synced-lyrics` has none; if
  needed, `CFStringTransform` from the system SDK can be used.
