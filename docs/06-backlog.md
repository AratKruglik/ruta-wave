# 06. Backlog — subtasks for step-by-step delivery

Each subtask is one SDLC pipeline run (BA → plan/approve → implement → QA → security → PR)
on its own git-flow branch: `feature/<name>` from `develop`, PR into `develop`.
Releases go through `release/<version>` → `main` (+ back-merge into `develop`).

Run each one with the ready-made command in the "Run" column. `--type=feature` and an
English description are required: without them the classifier picks the wrong task type
and the slug breaks.

Legend: ⛔ — decision point / manual check by the user (sign-in, listening to audio).

## Stage 0. Preparation

| ID | Branch | What | Depends on | Run |
|---|---|---|---|---|
| [x] 0.1 | `main`, `develop` | `git init`, `.gitignore`, docs commit, `develop` branch, GitHub remote | — | done by hand, outside the pipeline |
| [x] 0.2 | `feature/project-skeleton` | XcodeGen `project.yml` (app **Tunewave**, bundle ID `dev.kruhlyk.tunewave`, macOS 14, Swift 6, empty window), `Packages/` with empty packages, `xcodebuild build` + `swift test` pass. **Prerequisites:** Xcode installed, `sudo xcode-select -s /Applications/Xcode.app`, `brew install xcodegen` | 0.1 | `/sdlc:start "Create Tunewave macOS app skeleton: XcodeGen project.yml (bundle id dev.kruhlyk.tunewave, macOS 14, Swift 6, empty SwiftUI window) and empty local Swift packages per docs/02-architecture.md section 12" --type=feature --stack=apple` |

## Stage 1. Sign-in and session

| ID | Branch | What | Depends on | Run |
|---|---|---|---|---|
| [x] 1.1 ⛔ | `feature/auth-signin` | `Auth`: sign-in window on `WKWebView`, Safari UA, success detection via `SAPISID`, cookies → Keychain, sign-out. **Go/no-go:** if Google blocks the web view, stop and pick a fallback | 0.2 | `/sdlc:start "Auth package: Google sign-in in WKWebView, cookie capture to Keychain, sign-out (docs/03 stage 1)" --type=feature` |
| [ ] 1.2 | `feature/innertube-core` | `JSONValue`, `InnerTubeClient` actor, `SAPISIDHASH` (+ vector test), `account/account_menu`, account screen with name/avatar | 1.1 | `/sdlc:start "InnerTube core client: WEB_REMIX context, SAPISIDHASH signing, account_menu request and account screen" --type=feature` |

> Security note for 1.1 (from 0.2 review): `WKWebsiteDataStore.default()` persists cookies on disk under ~/Library outside the Keychain — include this in the 1.1 threat model.

## Stage 2. InnerTube client

| ID | Branch | What | Depends on | Run |
|---|---|---|---|---|
| [ ] 2.1 | `feature/innertube-paging-errors` | `INNERTUBE_CLIENT_VERSION` from the page + cache, `Page<T>`/`continuation`, errors (401 → sign-in, retry, unknown blocks skipped) | 1.2 | `/sdlc:start "InnerTube client version discovery, continuation paging and error handling" --type=feature` |
| [ ] 2.2 | `feature/innertube-browse-search` | Models; home, explore, search, suggestions parsers; fixtures without personal data; tests | 2.1 | `/sdlc:start "InnerTube models and parsers for home, explore, search and suggestions with fixture tests" --type=feature` |
| [ ] 2.3 | `feature/innertube-entities` | Album, artist, playlist, library, history, `next` (up next) parsers; tests | 2.2 | `/sdlc:start "InnerTube parsers for album, artist, playlist, library, history and up-next queue" --type=feature` |
| [ ] 2.4 | `feature/innertube-mutations` | `like/*`, `playlist/create|delete`, `browse/edit_playlist` | 2.1 | `/sdlc:start "InnerTube mutation endpoints: likes and playlist management" --type=feature` |

## Stage 3. Playback engine

| ID | Branch | What | Depends on | Run |
|---|---|---|---|---|
| [ ] 3.1 ⛔ | `feature/player-bridge` | Hidden `WKWebView` attached to a window, `bridge.js`, `PlayerEvent` `AsyncStream`, `SongInfo`, title cleaning (+ tests). Check that audio does not stop with the window minimized | 1.1 | `/sdlc:start "PlayerEngine: hidden WKWebView with JS bridge, PlayerEvent stream, SongInfo and title cleaning" --type=feature` |
| [ ] 3.2 ⛔ | `feature/player-commands-queue` | All `PlayerCommand`s, queue through the bridge, failure handling (crash → restore position), test window, integration test | 3.1 | `/sdlc:start "PlayerEngine commands, queue access, failure recovery and debug test window" --type=feature` |

## Stage 4. Main interface

| ID | Branch | What | Depends on | Run |
|---|---|---|---|---|
| [ ] 4.1 | `feature/ui-shell-player-bar` | `NavigationSplitView`, sidebar, routes, player bar | 3.2 | `/sdlc:start "Main window shell with NavigationSplitView, routing and player bar" --type=feature` |
| [ ] 4.2 | `feature/ui-home-explore` | Home (shelves), Explore | 4.1, 2.2 | `/sdlc:start "Home and Explore screens with horizontal shelves" --type=feature` |
| [ ] 4.3 | `feature/ui-search` | Search: toolbar field, suggestions, filters, results | 4.1, 2.2 | `/sdlc:start "Search screen with suggestions, filters and results" --type=feature` |
| [ ] 4.4 | `feature/ui-entity-pages` | Album, artist, playlist pages (with paging) | 4.1, 2.3 | `/sdlc:start "Album, artist and playlist pages with paging" --type=feature` |
| [ ] 4.5 | `feature/ui-library` | Library: playlists, songs, albums, artists, liked | 4.4 | `/sdlc:start "Library screens: playlists, songs, albums, artists, liked" --type=feature` |
| [ ] 4.6 | `feature/ui-queue-menus` | Queue panel (jump, drag, remove), context menus | 4.4, 2.4 | `/sdlc:start "Queue panel and context menus for tracks, albums and playlists" --type=feature` |
| [ ] 4.7 | `feature/ui-polish-a11y` | Loading/empty/error states, keyboard, VoiceOver | 4.2–4.6 | `/sdlc:start "Loading, empty and error states, keyboard shortcuts and VoiceOver accessibility" --type=feature` |

## Stage 5. macOS integration

| ID | Branch | What | Depends on | Run |
|---|---|---|---|---|
| [ ] 5.1 ⛔ | `feature/now-playing` | `MPNowPlayingInfoCenter`, `MPRemoteCommandCenter`, WebKit Media Session conflict | 4.1 | `/sdlc:start "Now Playing and media keys integration, resolve WebKit Media Session conflict" --type=feature` |
| [ ] 5.2 | `feature/menus-menubar-dock` | App menu, `MenuBarExtra`, Dock menu, notifications | 5.1 | `/sdlc:start "App menus, menu bar extra, Dock menu and track-change notifications" --type=feature` |
| [ ] 5.3 | `feature/settings-resume` | Settings window, `resumeOnStart`, starting page, always on top, launch at login | 5.1 | `/sdlc:start "Settings window, resume on start, starting page, always on top, launch at login" --type=feature` |
| [ ] 5.4 | `feature/mini-player-links` | Mini player, opening `music.youtube.com/...` links | 5.3 | `/sdlc:start "Mini player window and music.youtube.com link handling" --type=feature` |

## Stage 8 (moved up). DMG and first release

| ID | Branch | What | Depends on | Run |
|---|---|---|---|---|
| [ ] 8.1 ⛔ | `feature/build-dmg` | `scripts/build-dmg.sh`, Hardened Runtime, ad-hoc signing, version from `MARKETING_VERSION` | 5.x | `/sdlc:start "DMG build script with ad-hoc signing per docs/03 stage 8" --type=feature` |
| [ ] R1 | `release/0.1.0` | Release: README (Gatekeeper, disclaimer), version, merge into `main` + back-merge | 8.1 | `/sdlc:start "Release 0.1.0" --type=release` |

> Security note for 8.1 (from 0.2 review): sign with `codesign --force --options runtime --sign -` (no `--deep`), and make the script assert the final artifact has the `runtime` flag and no `get-task-allow`.

## Stage 6. Plugins, first wave

| ID | Branch | What | Depends on | Run |
|---|---|---|---|---|
| [ ] 6.1 | `feature/plugin-infra` | `Plugin` protocol, registry, toggles, `PluginContext`; `notifications` as a plugin | R1 | `/sdlc:start "Plugin infrastructure and notifications plugin" --type=feature` |
| [ ] 6.2 | `feature/plugin-synced-lyrics` | Synced lyrics + screen | 6.1 | `/sdlc:start "synced-lyrics plugin with lyrics screen" --type=feature` |
| [ ] 6.3 | `feature/plugin-scrobbler` | Last.fm + ListenBrainz, keys in the Keychain | 6.1 | `/sdlc:start "scrobbler plugin for Last.fm and ListenBrainz" --type=feature` |
| [ ] 6.4 | `feature/plugin-discord` | Discord Rich Presence over local IPC | 6.1 | `/sdlc:start "discord rich presence plugin over local IPC" --type=feature` |
| [ ] 6.5 | `feature/plugin-playback-tweaks` | precise-volume, exponential-volume, playback-speed, skip-disliked, disable-autoplay | 6.1 | `/sdlc:start "Playback plugins: precise-volume, exponential-volume, playback-speed, skip-disliked-songs, disable-autoplay" --type=feature` |
| [ ] 6.6 | `feature/plugin-shortcuts` | Global hotkeys (Carbon) | 6.1 | `/sdlc:start "shortcuts plugin with configurable global hotkeys" --type=feature` |
| [ ] 6.7 | `feature/plugin-video-options` | quality-changer, captions-selector, video-toggle (if the bridge allows) | 6.1 | `/sdlc:start "quality-changer, captions-selector and video-toggle plugins" --type=feature` |

## Stage 7. Plugins, second wave

| ID | Branch | What | Depends on | Run |
|---|---|---|---|---|
| [ ] 7.0 ⛔ | `feature/web-audio-spike` | Web Audio prototype + common audio chain in `bridge.js` (CORS risk #7) — **before** the audio plugins | 6.1 | `/sdlc:start "Web Audio chain prototype in player page, verify CORS on media stream" --type=feature` |
| [ ] 7.1 | `feature/plugin-eq-compressor` | equalizer, audio-compressor | 7.0 | `/sdlc:start "equalizer and audio-compressor plugins" --type=feature` |
| [ ] 7.2 | `feature/plugin-crossfade` | crossfade | 7.0 | `/sdlc:start "crossfade plugin" --type=feature` |
| [ ] 7.3 | `feature/plugin-visualizer-silences` | visualizer, skip-silences | 7.0 | `/sdlc:start "visualizer and skip-silences plugins" --type=feature` |
| [ ] 7.4 | `feature/plugin-output-sponsorblock` | custom-output-device, sponsorblock | 6.1 | `/sdlc:start "custom-output-device and sponsorblock plugins" --type=feature` |
| [ ] 7.5 | `feature/plugin-api-server` | Local `/api/v1/*` on `Network.framework` | 6.1 | `/sdlc:start "api-server plugin compatible with original /api/v1 routes" --type=feature` |
| [ ] 7.6 | `feature/plugin-visual-theme` | album-color-theme, ambient-mode, picture-in-picture, touchbar | 6.1 | `/sdlc:start "album-color-theme, ambient-mode, picture-in-picture and touchbar plugins" --type=feature` |
| [ ] R2 | `release/0.2.0` | Release with the plugins | 7.x | `/sdlc:start "Release 0.2.0" --type=release` |

"If needed" plugins (`amuse`, `clock`, `lumiastream`, `music-together`, `tuna-obs`) are not in
the backlog until there is a decision (open question #6 in [05](05-risks-and-scope.md)).
