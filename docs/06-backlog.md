# 06. Backlog — subtasks for step-by-step delivery

Each subtask is one SDLC pipeline run (BA → plan/approve → implement → QA → security → PR)
on its own git-flow branch: `feature/<name>` from `develop`, PR into `develop`.
Releases go through `release/<version>` → `main` (+ back-merge into `develop`).

Run each one with the ready-made command in the "Run" column. `--type=feature` and an
English description are required: without them the classifier picks the wrong task type
and the slug breaks.

Legend: ⛔ — decision point / manual check by the user (sign-in, listening to audio).

Every open row links to its GitHub issue; the ordered list of all of them is the tracking issue [#51](https://github.com/AratKruglik/yt-music-mac/issues/51).
Decisions on the open questions of [05](05-risks-and-scope.md#4-open-questions) have issues of their own: podcasts [#7](https://github.com/AratKruglik/yt-music-mac/issues/7) (decided: no), music videos [#12](https://github.com/AratKruglik/yt-music-mac/issues/12) (decided: later), languages [#15](https://github.com/AratKruglik/yt-music-mac/issues/15), DMG architecture [#29](https://github.com/AratKruglik/yt-music-mac/issues/29), lyrics source [#33](https://github.com/AratKruglik/yt-music-mac/issues/33), auto-update [#49](https://github.com/AratKruglik/yt-music-mac/issues/49), "If needed" plugins [#50](https://github.com/AratKruglik/yt-music-mac/issues/50); the app icon and the name check are [#28](https://github.com/AratKruglik/yt-music-mac/issues/28).

## Stage 0. Preparation

| ID | Branch | What | Depends on | Run |
|---|---|---|---|---|
| [x] 0.1 | `main`, `develop` | `git init`, `.gitignore`, docs commit, `develop` branch, GitHub remote | — | done by hand, outside the pipeline |
| [x] 0.2 | `feature/project-skeleton` | XcodeGen `project.yml` (app **Tunewave**, bundle ID `dev.kruhlyk.tunewave`, macOS 14, Swift 6, empty window), `Packages/` with empty packages, `xcodebuild build` + `swift test` pass. **Prerequisites:** Xcode installed, `sudo xcode-select -s /Applications/Xcode.app`, `brew install xcodegen` | 0.1 | `/sdlc:start "Create Tunewave macOS app skeleton: XcodeGen project.yml (bundle id dev.kruhlyk.tunewave, macOS 14, Swift 6, empty SwiftUI window) and empty local Swift packages per docs/02-architecture.md section 12" --type=feature --stack=apple` |
| [x] 0.3 [#6](https://github.com/AratKruglik/yt-music-mac/issues/6) | `feature/rename-redwave` | Rename the app to **Redwave** ([00](00-prd.md#1-name-and-positioning)): `project.yml` name, target, `PRODUCT_NAME`, bundle ID `dev.kruhlyk.redwave`; `TunewaveApp` → `RedwaveApp`; Keychain service `dev.kruhlyk.redwave.session`; UI strings. **Old session:** sign out in the old build first, or have the first launch delete the `dev.kruhlyk.tunewave.session` Keychain item and the old WebKit data under `~/Library` (they hold Google cookies, 05 §2.4); the user signs in again. Do **after 1.4 is merged**, so the guest-mode branch does not conflict | 1.4 | `/sdlc:start "Rename app from Tunewave to Redwave: project.yml, bundle id dev.kruhlyk.redwave, app struct, keychain service, UI strings, remove old-identifier keychain item and WebKit data" --type=feature --stack=apple` |
| [ ] 0.4 | `feature/rename-rutawave` | Rename the app to **Rutawave** ([00](00-prd.md#1-name-and-positioning)): `project.yml` name, target, `PRODUCT_NAME`, bundle ID `dev.kruhlyk.rutawave`; `RedwaveApp` → `RutawaveApp`; Keychain service `dev.kruhlyk.rutawave.session`; URL scheme `rutawave://`; DMG name; UI strings; Redwave identifiers left in docs 02 and 05. **Old session:** extend `LegacyStores` so the first launch also deletes the `dev.kruhlyk.redwave.session` Keychain item and the `dev.kruhlyk.redwave` WebKit data under `~/Library` (they hold Google cookies, 05 §2.4); the user signs in again. Do **after 3.2 is merged**, so the player branch does not conflict. GitHub issue not created yet | 3.2 | `/sdlc:start "Rename app from Redwave to Rutawave: project.yml, bundle id dev.kruhlyk.rutawave, app struct, keychain service, url scheme, UI strings, extend LegacyStores to remove redwave-identifier keychain item and WebKit data" --type=feature --stack=apple` |

## Stage 1. Sign-in and session

| ID | Branch | What | Depends on | Run |
|---|---|---|---|---|
| [x] 1.1 ⛔ | `feature/auth-signin` | `Auth`: sign-in window on `WKWebView`, Safari UA, success detection via `SAPISID`, cookies → Keychain, sign-out. **Go/no-go:** if Google blocks the web view, stop and pick a fallback | 0.2 | `/sdlc:start "Auth package: Google sign-in in WKWebView, cookie capture to Keychain, sign-out (docs/03 stage 1)" --type=feature` |
| [x] 1.2 | `feature/innertube-core` | `JSONValue`, `InnerTubeClient` actor, `SAPISIDHASH` (+ vector test), `account/account_menu`, account screen with name/avatar | 1.1 | `/sdlc:start "InnerTube core client: WEB_REMIX context, SAPISIDHASH signing, account_menu request and account screen" --type=feature` |
| [x] 1.3 | `feature/account-switching` | Account list and switching: find the endpoint/body WEB_REMIX uses for the account switcher (accounts_list with this body returns no accounts), list + switch UI, index fallback | 1.2 | `/sdlc:start "Account list and switching for multiple Google accounts in the session" --type=feature` |
| [x] 1.4 | `feature/guest-mode` | Guest mode: the app starts without sign-in; `InnerTubeClient` sends unauthenticated requests (`visitorData`, no `Cookie`/`Authorization`); "Sign in" becomes an optional button; account-only actions (library, likes, playlists) are hidden or prompt to sign in | 1.2 | `/sdlc:start "Guest mode: browse and play without signing in, optional sign-in, unauthenticated InnerTube requests" --type=feature` |

> ~~Security note for 1.3~~ **resolved in 1.3:** the regex is replaced by a dated snapshot of google.com/supported_domains and only `/accounts/SetSID` is allowed on regional hosts. Original note (from the automated review of 1.2): `SignInRules.isRegionalAccountsHost` accepts any `accounts.google.(com.|co.)?<cc>` host. If some `google.com.<cc>` / `google.co.<cc>` domain is not Google-owned, a page on it could load in the credential web view. Replace the regex with Google's published supported-domains list (google.com/supported_domains) and allow only the `/accounts/SetSID` path on those hosts.

> Security note for 1.1 (from 0.2 review): `WKWebsiteDataStore.default()` persists cookies on disk under ~/Library outside the Keychain — include this in the 1.1 threat model.

## Stage 2. InnerTube client

| ID | Branch | What | Depends on | Run |
|---|---|---|---|---|
| [ ] 2.1 [#8](https://github.com/AratKruglik/yt-music-mac/issues/8) | `feature/innertube-paging-errors` | `INNERTUBE_CLIENT_VERSION` from the page + cache, `Page<T>`/`continuation`, errors (401 → sign-in, retry, unknown blocks skipped); works for guests too | 1.2, 1.4 | `/sdlc:start "InnerTube client version discovery, continuation paging and error handling" --type=feature` |
| [ ] 2.2 [#9](https://github.com/AratKruglik/yt-music-mac/issues/9) | `feature/innertube-browse-search` | Models; home, explore, search, suggestions parsers; fixtures without personal data; tests | 2.1 | `/sdlc:start "InnerTube models and parsers for home, explore, search and suggestions with fixture tests" --type=feature` |
| [ ] 2.3 [#10](https://github.com/AratKruglik/yt-music-mac/issues/10) | `feature/innertube-entities` | Album, artist, playlist, library, history, `next` (up next) parsers; tests | 2.2 | `/sdlc:start "InnerTube parsers for album, artist, playlist, library, history and up-next queue" --type=feature` |
| [x] 2.4 [#11](https://github.com/AratKruglik/yt-music-mac/issues/11) | `feature/issue-11` | `like/*`, `playlist/create|delete`, `browse/edit_playlist`, `subscription/subscribe|unsubscribe` (artist Subscribe), `feedback` (remove a search or history entry) | 2.1 | `/sdlc:start "InnerTube mutation endpoints: likes, playlist management, artist subscriptions and feedback tokens" --type=feature` |

## Stage 3. Playback engine

| ID | Branch | What | Depends on | Run |
|---|---|---|---|---|
| [ ] 3.1 ⛔ [#13](https://github.com/AratKruglik/yt-music-mac/issues/13) | `feature/player-bridge` | Hidden `WKWebView` attached to a window, `bridge.js`, `PlayerEvent` `AsyncStream`, `SongInfo`, title cleaning (+ tests). Check that audio does not stop with the window minimized. In guest state the player must not use a Google session left in the web view store (leftovers: `restore()` dropping an expired Keychain entry, sign-in failure + app quit, quit mid-2FA). Do not wipe `default()` on player start: after "Continue without signing in" (`.keychainUnavailable`) it holds the user's live session. Prefer a `WKWebsiteDataStore.nonPersistent()` store for guest playback. 3.1 must also handle "signed in (Keychain) but web view store empty" (e.g. Continue without signing in → Sign in → Cancel): restore the `youtube.com` cookies from the Keychain into the store or offer sign-in. Keep the web view re-parentable: it must be movable into a visible container later without reloading or stopping playback (video mode later, #12) | 1.1 | `/sdlc:start "PlayerEngine: hidden WKWebView with JS bridge, PlayerEvent stream, SongInfo and title cleaning" --type=feature` |
| [ ] 3.2 ⛔ [#14](https://github.com/AratKruglik/yt-music-mac/issues/14) | `feature/player-commands-queue` | All `PlayerCommand`s, queue through the bridge, failure handling (crash → restore position), test window, integration test | 3.1 | `/sdlc:start "PlayerEngine commands, queue access, failure recovery and debug test window" --type=feature` |

## Stage 4. Main interface

| ID | Branch | What | Depends on | Run |
|---|---|---|---|---|
| [ ] 4.1 [#16](https://github.com/AratKruglik/yt-music-mac/issues/16) | `feature/ui-shell-player-bar` | `NavigationSplitView`, sidebar, routes, player bar; guest and signed-in states (Sign in button for guests) | 3.2, 1.4 | `/sdlc:start "Main window shell with NavigationSplitView, routing and player bar per docs/07 and docs/08" --type=feature` |
| [ ] 4.2 [#17](https://github.com/AratKruglik/yt-music-mac/issues/17) | `feature/ui-home-explore` | Home (mood chips, shelves), Explore with its subpages: New releases, Charts (country selector), Moods & genres and one mood (08 §5–6) | 4.1, 2.2 | `/sdlc:start "Home and Explore screens with horizontal shelves, plus New releases, Charts and Moods subpages" --type=feature` |
| [ ] 4.3 [#18](https://github.com/AratKruglik/yt-music-mac/issues/18) | `feature/ui-search` | Search: toolbar field, suggestions, search history in the dropdown with delete, filters, results (08 §3) (Podcasts, Episodes and Profiles filters and Podcasts and Uploads sections are already dropped by the parsers, #7) | 4.1, 2.2, 2.4 | `/sdlc:start "Search screen with suggestions, search history with delete, filters and results" --type=feature` |
| [ ] 4.4 [#19](https://github.com/AratKruglik/yt-music-mac/issues/19) | `feature/ui-entity-pages` | Album, artist (with Subscribe), playlist pages (with paging) (08 §8) | 4.1, 2.3, 2.4 | `/sdlc:start "Album, artist and playlist pages with paging" --type=feature` |
| [ ] 4.5 [#20](https://github.com/AratKruglik/yt-music-mac/issues/20) | `feature/ui-library` | Library: playlists, songs, albums, artists, subscriptions, liked; History page with removal from history; guests see a sign-in prompt instead (08 §7) (Podcasts, Episodes and Profiles filters and Podcasts and Uploads sections are already dropped by the parsers, #7) | 4.4, 2.4 | `/sdlc:start "Library screens: playlists, songs, albums, artists, subscriptions, liked and history" --type=feature` |
| [ ] 4.6 [#21](https://github.com/AratKruglik/yt-music-mac/issues/21) | `feature/ui-queue-menus` | Player page with the Up next queue (jump, drag, remove, radio chips, Save queue), context menus, multi-select with selection bar, drag and drop to playlists and the queue (08 §10.2, §11, §12) | 4.4, 2.4 | `/sdlc:start "Player page with up-next queue, context menus, multi-select and drag and drop for tracks, albums and playlists" --type=feature` |
| [ ] 4.8 [#22](https://github.com/AratKruglik/yt-music-mac/issues/22) | `feature/ui-player-page-tabs` | Player page: Lyrics, Related and Comments tabs (Comments: check the data source and guest behaviour first) (08 §10) | 4.6, 2.3, 3.2 | `/sdlc:start "Player page Lyrics, Related and Comments tabs" --type=feature` |
| [ ] 4.7 [#23](https://github.com/AratKruglik/yt-music-mac/issues/23) | `feature/ui-polish-a11y` | Loading/empty/error states, offline banner with retry on reconnect, keyboard map, VoiceOver (08 §14) | 4.2–4.6, 4.8 | `/sdlc:start "Loading, empty, error and offline states, keyboard shortcuts and VoiceOver accessibility" --type=feature` |
| ~~4.9~~ ⛔ [#48](https://github.com/AratKruglik/yt-music-mac/issues/48) | `feature/ui-podcasts` | **Not planned** — open question #4 decided no in #7 | 4.4, 4.5 | — |

## Stage 5. macOS integration

| ID | Branch | What | Depends on | Run |
|---|---|---|---|---|
| [ ] 5.1 ⛔ [#24](https://github.com/AratKruglik/yt-music-mac/issues/24) | `feature/now-playing` | `MPNowPlayingInfoCenter`, `MPRemoteCommandCenter`, WebKit Media Session conflict | 4.1 | `/sdlc:start "Now Playing and media keys integration, resolve WebKit Media Session conflict" --type=feature` |
| [ ] 5.2 [#25](https://github.com/AratKruglik/yt-music-mac/issues/25) | `feature/menus-menubar-dock` | App menu, `MenuBarExtra`, Dock menu, notifications | 5.1 | `/sdlc:start "App menus, menu bar extra, Dock menu and track-change notifications" --type=feature` |
| [ ] 5.3 [#26](https://github.com/AratKruglik/yt-music-mac/issues/26) | `feature/settings-resume` | Settings window, `resumeOnStart`, starting page, always on top, launch at login | 5.1 | `/sdlc:start "Settings window, resume on start, starting page, always on top, launch at login" --type=feature` |
| [ ] 5.4 [#27](https://github.com/AratKruglik/yt-music-mac/issues/27) | `feature/mini-player-links` | Mini player, opening `music.youtube.com/...` links | 5.3 | `/sdlc:start "Mini player window and music.youtube.com link handling" --type=feature` |

## Stage 8 (moved up). DMG and first release

| ID | Branch | What | Depends on | Run |
|---|---|---|---|---|
| [ ] 8.1 ⛔ [#30](https://github.com/AratKruglik/yt-music-mac/issues/30) | `feature/build-dmg` | `scripts/build-dmg.sh`, Hardened Runtime, ad-hoc signing, version from `MARKETING_VERSION` | 5.x | `/sdlc:start "DMG build script with ad-hoc signing per docs/03 stage 8" --type=feature` |
| [ ] R1 [#31](https://github.com/AratKruglik/yt-music-mac/issues/31) | `release/0.1.0` | Release: README (Gatekeeper, disclaimer), version, merge into `main` + back-merge | 8.1 | `/sdlc:start "Release 0.1.0" --type=release` |

> Security note for 8.1 (from 0.2 review): sign with `codesign --force --options runtime --sign -` (no `--deep`), and make the script assert the final artifact has the `runtime` flag and no `get-task-allow`.

## Stage 6. Plugins, first wave

| ID | Branch | What | Depends on | Run |
|---|---|---|---|---|
| [ ] 6.1 [#32](https://github.com/AratKruglik/yt-music-mac/issues/32) | `feature/plugin-infra` | `Plugin` protocol, registry, toggles, `PluginContext`; `notifications` as a plugin | R1 | `/sdlc:start "Plugin infrastructure and notifications plugin" --type=feature` |
| [ ] 6.2 [#34](https://github.com/AratKruglik/yt-music-mac/issues/34) | `feature/plugin-synced-lyrics` | Synced lyrics + screen | 6.1 | `/sdlc:start "synced-lyrics plugin with lyrics screen" --type=feature` |
| [ ] 6.3 [#35](https://github.com/AratKruglik/yt-music-mac/issues/35) | `feature/plugin-scrobbler` | Last.fm + ListenBrainz, keys in the Keychain | 6.1 | `/sdlc:start "scrobbler plugin for Last.fm and ListenBrainz" --type=feature` |
| [ ] 6.4 [#36](https://github.com/AratKruglik/yt-music-mac/issues/36) | `feature/plugin-discord` | Discord Rich Presence over local IPC | 6.1 | `/sdlc:start "discord rich presence plugin over local IPC" --type=feature` |
| [ ] 6.5 [#37](https://github.com/AratKruglik/yt-music-mac/issues/37) | `feature/plugin-playback-tweaks` | precise-volume, exponential-volume, playback-speed, skip-disliked, disable-autoplay | 6.1 | `/sdlc:start "Playback plugins: precise-volume, exponential-volume, playback-speed, skip-disliked-songs, disable-autoplay" --type=feature` |
| [ ] 6.6 [#38](https://github.com/AratKruglik/yt-music-mac/issues/38) | `feature/plugin-shortcuts` | Global hotkeys (Carbon) | 6.1 | `/sdlc:start "shortcuts plugin with configurable global hotkeys" --type=feature` |
| [ ] 6.7 [#39](https://github.com/AratKruglik/yt-music-mac/issues/39) | `feature/plugin-quality-changer` | quality-changer (if the bridge allows) | 6.1 | `/sdlc:start "quality-changer plugin" --type=feature` |

## Stage 7. Plugins, second wave

| ID | Branch | What | Depends on | Run |
|---|---|---|---|---|
| [ ] 7.0 ⛔ [#40](https://github.com/AratKruglik/yt-music-mac/issues/40) | `feature/web-audio-spike` | Web Audio prototype + common audio chain in `bridge.js` (CORS risk #7) — **before** the audio plugins | 6.1 | `/sdlc:start "Web Audio chain prototype in player page, verify CORS on media stream" --type=feature` |
| [ ] 7.1 [#41](https://github.com/AratKruglik/yt-music-mac/issues/41) | `feature/plugin-eq-compressor` | equalizer, audio-compressor | 7.0 | `/sdlc:start "equalizer and audio-compressor plugins" --type=feature` |
| [ ] 7.2 [#42](https://github.com/AratKruglik/yt-music-mac/issues/42) | `feature/plugin-crossfade` | crossfade | 7.0 | `/sdlc:start "crossfade plugin" --type=feature` |
| [ ] 7.3 [#43](https://github.com/AratKruglik/yt-music-mac/issues/43) | `feature/plugin-visualizer-silences` | visualizer, skip-silences | 7.0 | `/sdlc:start "visualizer and skip-silences plugins" --type=feature` |
| [ ] 7.4 [#44](https://github.com/AratKruglik/yt-music-mac/issues/44) | `feature/plugin-output-sponsorblock` | custom-output-device, sponsorblock | 6.1 | `/sdlc:start "custom-output-device and sponsorblock plugins" --type=feature` |
| [ ] 7.5 [#45](https://github.com/AratKruglik/yt-music-mac/issues/45) | `feature/plugin-api-server` | Local `/api/v1/*` on `Network.framework` | 6.1 | `/sdlc:start "api-server plugin compatible with original /api/v1 routes" --type=feature` |
| [ ] 7.6 [#46](https://github.com/AratKruglik/yt-music-mac/issues/46) | `feature/plugin-visual-theme` | album-color-theme, ambient-mode, touchbar | 6.1 | `/sdlc:start "album-color-theme, ambient-mode and touchbar plugins" --type=feature` |
| [ ] R2 [#47](https://github.com/AratKruglik/yt-music-mac/issues/47) | `release/0.2.0` | Release with the plugins | 7.x | `/sdlc:start "Release 0.2.0" --type=release` |

"If needed" plugins (`amuse`, `clock`, `lumiastream`, `music-together`, `tuna-obs`) are not in
the backlog until there is a decision (open question #6 in [05](05-risks-and-scope.md)).

Music video mode (Song/Video toggle, `captions-selector`, `video-toggle`, `picture-in-picture`) is deferred by [#12](https://github.com/AratKruglik/yt-music-mac/issues/12) and is not in the backlog until it is revisited.
