# 01. Reverse-engineering results

Target: `/Volumes/YouTube Music 3.12.0-arm64/YouTube Music.app`.
The analysis is **static only**: the app was not launched and no network traffic was captured.

## 1. Identity

| Field | Value | Source |
|---|---|---|
| Bundle ID | `com.github.th-ch.youtube-music` | Info.plist |
| Version | 3.12.0, arm64 | Info.plist |
| Minimum macOS | 12.0 | Info.plist |
| Package name | `youtube-music`, "YouTube Music Desktop App - including custom plugins" | package.json in the ASAR |
| Repository | `pear-devs/pear-desktop` | package.json |
| License | MIT | package.json, `license` file |
| SHA-256 of `app.asar` | `b88bdf7ed0687740f421be2fab9a86a636b670d0326440dad5b56679ba223e5d` | [REA] |
| SHA-256 of Electron Framework | `24c2d8df8a5366e0ea700f6e91c3d6a02bd1b144302c53fe5a22cbf86df322d3` | [REA] |

The code is open source, so for anything ambiguous it is more reliable to read
the upstream repository than the minified bundle.

## 2. Package structure

```
YouTube Music.app/Contents
├─ MacOS/YouTube Music                 — standard Electron launcher
├─ Frameworks/
│  ├─ Electron Framework.framework     — 189 MB, Chromium + Node
│  ├─ Squirrel / Mantle / ReactiveObjC — auto-update
│  └─ YouTube Music Helper (GPU|Plugin|Renderer).app
└─ Resources/
   ├─ app.asar            — 40 MB, 253 files, all application code
   ├─ app.asar.unpacked   — 2 MB, icons
   ├─ app-update.yml      — electron-updater config
   └─ *.lproj, Assets.car, icon.icns
```

Contents of `app.asar` [bundle]:

| Path | Files | Size | What it is |
|---|---|---|---|
| `node_modules` | 18 | 25.9 MB | `@ffmpeg.wasm/core-mt`, `@ghostery/adblocker-electron-preload`, `custom-electron-prompt` |
| `dist/main` | 135 | 7.5 MB | main process: `index.js` (677 KB) + plugin and locale chunks |
| `dist/renderer` | 3 | 6.5 MB | `youtube-music.iife.js` (6.45 MB) — the code injected into the page |
| `dist/preload` | 67 | 1.7 MB | `preload.cjs` (408 KB) + locales |
| `assets` | — | ~2 MB | icons, tray icons, `mdui.css`, `error.html` |

There is no native code of its own: everything except Electron is JS/TS
(SolidJS for its own UI elements, built with Rolldown/Vite).

## 3. Electron fuses [REA]

Evidence: `ev_be28de1178510a80de51cb4fe683f81c608dc6dcae9be9e70ac8dd82777f88d5`.

| Fuse | State |
|---|---|
| RunAsNode | enabled |
| EnableNodeOptionsEnvironmentVariable | enabled |
| EnableNodeCliInspectArguments | enabled |
| EnableCookieEncryption | disabled |
| EnableEmbeddedAsarIntegrityValidation | disabled |
| OnlyLoadAppFromAsar | disabled |
| GrantFileProtocolExtraPrivileges | enabled |

Practical consequence: the app honours `--inspect`, so the inspector can be
attached to observe real behaviour if needed (not done in this investigation).

## 4. How the app works

### 4.1. Startup and window

Source: [REA + bundle]. Graph Evidence:
`ev_6d06177908951217fb8d0ba97d57e052674efda519b2af9d4f0dd8197ccce042`
(1 BrowserWindow, 3 protocol registrations, 6 IPC handlers in the main process).

1. `app.requestSingleInstanceLock()` — only one instance is allowed.
2. The `http` and `https` schemes are registered as privileged with
   `bypassCSP: true`, `corsEnabled: true`, `allowServiceWorkers: true`. This is
   what lets plugins inject code into Google's page despite its Content Security Policy.
3. A single window is created:
   - `minWidth: 325`, `minHeight: 425`, `backgroundColor: "#000"`, `show: false`;
   - `webPreferences.contextIsolation: true`, `preload: dist/preload/preload.cjs`,
     `sandbox: false` (except in one special mode);
   - size and position are restored from the config, with a check that the
     window does not end up off-screen.
4. The window loads the URL from the config — `https://music.youtube.com` by
   default. With `resumeOnStart` enabled, the last track is opened.

### 4.2. Google sign-in

Source: [bundle].

- With the `overrideUserAgent` option, the window gets a regular browser
  User-Agent (separate strings for mac, windows, linux), while requests to
  `accounts.google.com` get the original User-Agent back through `onBeforeSendHeaders`.
- Navigation to the `/premium` path is intercepted and replaced with
  `https://accounts.google.com/ServiceLogin?ltmpl=music&service=youtube&continue=…music.youtube.com…`.
- Load failures (`did-fail-load`) are logged, except code `-3` and requests to
  `doubleclick.net`; `assets/error.html` is shown when needed.

### 4.3. Bridge between the page and the app

Source: [bundle].

`preload.cjs` exposes to the page through `contextBridge`:
`ipcRenderer`, `mainConfig`, `electronIs`, `reload`, `_pruner`,
`ELECTRON_RENDERER_URL`.

Handlers in the main process (`ipcMain.handle`):
`peard:get-config`, `peard:set-config`, `peard:get-main-plugin-names`.

Messages from the main process to the page:
`config-changed`, `log`, `plugin:enable`, `plugin:unload`, `refresh-in-app-menu`.

### 4.4. Player control

Source: [bundle].

The `youtube-music.iife.js` script runs inside the page, gets access to the
site's internal player API (the bundle references `playerApi`,
`getPlayerResponse` and the `ytmusic-app` element) and listens on `peard:*` channels.

**Commands (app → page):**

| Group | Channels |
|---|---|
| Playback | `peard:play`, `peard:pause`, `peard:toggle-play`, `peard:next-video`, `peard:previous-video` |
| Position | `peard:seek-to`, `peard:seek-by` |
| Volume | `peard:update-volume`, `peard:toggle-mute` |
| Modes | `peard:shuffle`, `peard:switch-repeat`, `peard:get-shuffle` |
| Rating | `peard:update-like` |
| Queue | `peard:get-queue`, `peard:add-to-queue`, `peard:remove-from-queue`, `peard:move-in-queue`, `peard:set-queue-index`, `peard:clear-queue` |
| Search | `peard:search` |
| Screen | `peard:get-fullscreen`, `peard:set-fullscreen`, `peard:click-fullscreen-button`, `peard:pip-toggle` |
| Other | `peard:captions-selector`, `peard:quality-changer`, `peard:menu-event`, `peard:reload` |
| Subscriptions | `peard:setup-time-changed-listener`, `peard:setup-seeked-listener`, `peard:setup-volume-changed-listener`, `peard:setup-like-changed-listener`, `peard:setup-repeat-changed-listener`, `peard:setup-shuffle-changed-listener`, `peard:setup-autoplay-changed-listener`, `peard:setup-fullscreen-changed-listener` |

**Events (page → app):**

| Channel | Content |
|---|---|
| `peard:player-api-loaded` | the player API is ready |
| `peard:video-src-changed` | new track; carries the player response with metadata |
| `peard:src-changed`, `peard:audio-can-play` | source change and audio readiness |
| `peard:play-or-paused` | `{ isPaused, elapsedSeconds }` |
| `peard:time-changed` | current position in seconds |
| `peard:seeked` | a seek happened |
| `peard:volume-changed` | volume and mute state |
| `peard:like-changed`, `peard:repeat-changed`, `peard:shuffle-changed`, `peard:autoplay-changed`, `peard:fullscreen-changed` | state changes |
| `peard:get-queue-response`, `peard:get-shuffle-response`, `peard:search-results` | replies to requests |
| `peard:update-song-info` | the assembled track object (sent back to the page) |

### 4.5. The SongInfo track model

Source: [bundle, `song-info-*.js`].

On `peard:video-src-changed` the main process builds a track object from the
player response, serialising the work with a mutex (`async-mutex`), and
broadcasts it to subscribed plugins. On `play-or-paused` and `time-changed`
only the `isPaused` and `elapsedSeconds` fields are updated.

Behaviour worth porting:
- artwork is the last (largest) item in the thumbnail list, with the URL
  stripped of its query; if a `HEAD` request to it fails, the URL with the
  query is used instead;
- the title is cleaned with regular expressions that strip these suffixes:
  `- topic`, `vevo`, `(official …)`, `(lyrics|visualizer|audio [video])`,
  `(performance video)`, `(clip official)`, `(video version)`,
  `(HD|HQ [audio])`, `(live)`, `(4K [upgrade])`.

### 4.6. Configuration

Source: [bundle, `config-*.js`]. Stored as JSON through `electron-store`. Defaults:

```jsonc
{
  "window-size": { "width": 1100, "height": 550 },
  "window-maximized": false,
  "window-position": { "x": -1, "y": -1 },
  "url": "https://music.youtube.com",
  "options": {
    "tray": false,
    "appVisible": true,
    "autoUpdates": true,
    "alwaysOnTop": false,
    "hideMenu": false,
    "hideMenuWarned": false,
    "startAtLogin": false,
    "disableHardwareAcceleration": false,
    "removeUpgradeButton": false,
    "restartOnConfigChanges": false,
    "trayClickPlayPause": false,
    "autoResetAppCache": false,
    "resumeOnStart": true,
    "likeButtons": "",
    "swapLikeButtonsOrder": false,
    "proxy": "",
    "startingPage": "",
    "overrideUserAgent": false,
    "usePodcastParticipantAsArtist": false,
    "themes": []
  },
  "plugins": {}
}
```

The menu code also references the `language` and `customWindowTitle` options.

### 4.7. Plugins

Source: [bundle].

41 plugin identifiers were found (the full list and the fate of each is in
[04-plugins.md](04-plugins.md)). Each plugin is a separate chunk in `dist/main`
plus a part in the page bundle; enabling and disabling goes through the
`plugin:enable` / `plugin:unload` messages.

External services found in plugin chunks:

| Plugin | Addresses |
|---|---|
| scrobbler | `https://ws.audioscrobbler.com/2.0/`, `https://www.last.fm/api/auth/`, `https://api.listenbrainz.org/1/` |
| sponsorblock | `https://sponsor.ajay.app` |
| api-server | local HTTP server on Hono with OpenAPI |

Routes of the local API server (`/api/v1/…`):
`play`, `pause`, `toggle-play`, `next`, `previous`, `seek-to`, `volume`,
`toggle-mute`, `shuffle`, `repeat-mode`, `switch-repeat`, `like`, `dislike`,
`like-state`, `fullscreen`, `go-back`, `go-forward`, `song`, `song-info`,
`queue`, `queue-info`, `queue/next`, `queue/{index}`, `search`, `ws` (WebSocket),
and also `/auth/{id}`.

### 4.8. Third-party libraries that explain the features

| Library | Purpose |
|---|---|
| `youtubei.js`, `bgutils-js` | InnerTube client and PoToken (downloader, lyrics, search) |
| `@ffmpeg.wasm/*`, `node-id3` | transcoding and tags in the downloader |
| `@ghostery/adblocker-electron` | ad blocking |
| `@xhayper/discord-rpc` | Discord Rich Presence |
| `hono`, `@hono/zod-openapi` | local API server |
| `peerjs` | listening together (music-together) |
| `butterchurn`, `vudio`, `@foobar404/wave` | visualizers |
| `kuroshiro`, `pinyin-pro`, `es-hangul`, `hanja`, `sanscript`, `romanize-thai`, `tinyld` | lyrics romanization |
| `fast-average-color`, `color` | theme from the artwork colour |
| `electron-updater` | auto-update from GitHub Releases |

## 5. Limits of the analysis

- REA could not build a graph of the whole ASAR: the full result needs more than
  1 GB of session memory. Only `dist/main/index.js` and
  `dist/preload/preload.cjs` were analysed semantically, and even there coverage
  is **partial** (node and unknown limits were reached).
- Page channels, the plugin list, the config and the API-server routes were
  obtained by **text search**, without tracing calls. The channel list may be incomplete.
- No plugin was traced individually: the descriptions in
  [04-plugins.md](04-plugins.md) rely on the name and general knowledge of the project.
- Exactly how the page calls the site player's methods was not investigated; for
  the Swift version this is settled at stage 3 or by reading the upstream repository.
- Runtime behaviour (network requests, event ordering) was not observed.
