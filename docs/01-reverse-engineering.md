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

### 4.9. InnerTube discovery endpoints (verified 2026-11-19)

Checked with live guest requests (`WEB_REMIX`, client `1.20261115.14.00`, `hl=en`, `gl=US`), not read from the Electron bundle. The scrubbed captures are the test fixtures in `Packages/InnerTube/Tests/InnerTubeTests/Fixtures`.

| Page | Request | Root |
|---|---|---|
| Home | `browse FEmusic_home` | `contents.singleColumnBrowseResultsRenderer.tabs[0].tabRenderer.content.sectionListRenderer` |
| Explore and its subpages | `browse FEmusic_explore`, `FEmusic_new_releases`, `FEmusic_moods_and_genres`, `FEmusic_moods_and_genres_category` + `params`, a shelf's More target | the same section list, plus `header.musicHeaderRenderer` for the page title |
| Charts | `browse FEmusic_charts` + `formData` | the same section list, plus `frameworkUpdates` |
| Search | `search` + `query` (+ filter `params`) | `contents.tabbedSearchResultsRenderer.tabs[0].tabRenderer.content.sectionListRenderer` |
| Suggestions | `music/get_search_suggestions` + `input` | `contents[].searchSuggestionsSectionRenderer.contents[]` |
| Album | `browse MPREb_…` | `contents.twoColumnBrowseResultsRenderer`: header `tabs[0]…sectionListRenderer.contents[0].musicResponsiveHeaderRenderer`, tracks and shelves `secondaryContents.sectionListRenderer.contents[]` |
| Artist | `browse UC…` | the single-column section list, plus `header.musicImmersiveHeaderRenderer` |
| Artist Show all | `browse MPAD…` or `UC…` + `params` (albums, live, playlists); `VLOLAK…` + `params` (Top songs, Videos) | a section list with one `gridRenderer` or `musicShelfRenderer`; the `VL…` target is a single-column **playlist** (`header.musicHeaderRenderer`, `musicPlaylistShelfRenderer`) |
| Playlist | `browse VL…` | the album layout, with `musicPlaylistShelfRenderer` instead of `musicShelfRenderer` |
| Up next | `next` + `videoId`, `playlistId`, `params` | `contents.singleColumnMusicWatchNextResultsRenderer.tabbedRenderer.watchNextTabbedResultsRenderer.tabs[]` |
| Lyrics | `browse MPLY…` | `contents.sectionListRenderer.contents[0].musicDescriptionShelfRenderer`, or `contents.messageRenderer` |
| Related | `browse MPTR…` | `contents.sectionListRenderer` (no single-column wrapper) |
| Library, history (signed in) | `browse FEmusic_liked_playlists`, `FEmusic_liked_videos`, `FEmusic_liked_albums`, `FEmusic_library_corpus_track_artists`, `FEmusic_library_corpus_artists`, `FEmusic_history` | the single-column section list. Signed-in shapes follow `ytmusicapi` and are **unverified**; a guest gets a `messageRenderer` sign-in card. |
| Sidebar | `guide` `{}` | `items[].guideSectionRenderer.items[].guideEntryRenderer`. Signed-in shape follows `youtubei.js` and is **unverified**; a guest gets Home, Explore and Library and no `VL…` entries. |

- **Section kinds.** `musicCarouselShelfRenderer` (items are `musicTwoRowItemRenderer` cards or `musicResponsiveListItemRenderer` rows), `gridRenderer` and `musicShelfRenderer`. The guest Home also holds a `musicTastebuilderShelfRenderer` that is not a catalogue shelf.
- **Chips.** Home mood chips and search filters are `header.chipCloudRenderer.chips[].chipCloudChipRenderer`. A Home chip carries `browseEndpoint{browseId, params}`; a search filter carries `searchEndpoint{query, params}`.
- **Continuation.** The body `{"continuation": token}` works. A guest request **must carry the same `X-Goog-Visitor-Id`** as the page that issued the token; without it the response has an empty tab and no continuation. Home page 2 is under `continuationContents.sectionListContinuation`, filtered search page 2 under `continuationContents.musicShelfContinuation`. Both use `continuations[0].nextContinuationData.continuation`.
- **More target.** `moreContentButton.buttonRenderer.navigationEndpoint` is a `browseEndpoint` (More) or a `watchEndpoint` ("Play all"). Only the first is a More target. A More page is a section list with one `gridRenderer`.
- **Charts country.** The body `formData: {"selectedValues": ["US"]}` selects the country. Without it the country follows the caller's IP address, not `gl`. The country menu is `musicSortFilterButtonRenderer.menu.musicMultiSelectMenuRenderer.options[]`, and its options have no country code. The code (`ZZ` = Global) is only in `frameworkUpdates.entityBatchUpdate.mutations[].payload.musicFormBooleanChoice{id, opaqueToken, selected}`, joined to the option on `formItemEntityKey == id`. Ranked rows have `customIndexColumn.musicCustomIndexColumnRenderer` with the position and an `ARROW_DROP_UP`, `ARROW_DROP_DOWN` or `ARROW_CHART_NEUTRAL` icon (or none). The US page also has a podcast shelf (skipped, #7).
- **Search results are flat.** An unfiltered search is a `musicCardShelfRenderer` top-result card (`title`, `subtitle`, `thumbnail`, `onTap`) followed by about 28 `itemSectionRenderer`s with one `musicResponsiveListItemRenderer` each. There are no per-type sections, no "Show all" targets and no continuation. A filtered search is one `musicShelfRenderer` with a continuation. The correction line is `itemSectionRenderer.contents[0].showingResultsForRenderer{correctedQueryEndpoint, originalQueryEndpoint}`. Google returns fuzzy results for any guest query, so "no results" cannot be reproduced.
- **Item kind** comes from the item's own endpoint, never from the localized "Song" / "Album" label and never from a search through the item (menus hold unrelated artist, album and track-credits endpoints): `browseEndpoint` page type `ALBUM`, `ARTIST` or `PLAYLIST`, or `watchEndpoint` with `musicVideoType` (`ATV` song, `OMV` and `UGC` video, `PODCAST_EPISODE` not supported). Rows without a top-level `navigationEndpoint` use the first title run's endpoint, then the overlay play endpoint, then `playlistItemData.videoId`.
- **Suggestions.** Text suggestions are `searchSuggestionRenderer{suggestion.runs, navigationEndpoint.searchEndpoint.query}`, entities are `musicResponsiveListItemRenderer`. History entries (signed in) are `historySuggestionRenderer` with `serviceEndpoint.feedbackEndpoint.feedbackToken`; that shape was not observed as a guest and follows the public `ytmusicapi` parser.
- **Thumbnails** come from `yt3.googleusercontent.com`, `lh3.googleusercontent.com`, `i.ytimg.com` and `yt3.ggpht.com`. Icon-like images on `www.youtube.com` and `music.youtube.com` are outside the avatar allowlist and are not used.
- **Album and playlist pages (2026-11-19).**
  - The header is `musicResponsiveHeaderRenderer`: `subtitle` ("Album • 1997"), `straplineTextOne` (artist links), `secondSubtitle` ("12 songs • 53 minutes"), `description.musicDescriptionShelfRenderer`, and `buttons[]` with the Play `musicPlayButtonRenderer` and a `menuRenderer` whose `MUSIC_SHUFFLE` and `MIX` items hold the `watchPlaylistEndpoint`s. A playlist's owner is `facepile.avatarStackViewModel` (a channel link only for a user playlist). An own playlist wraps the header in `musicEditablePlaylistDetailHeaderRenderer.header` (`ytmusicapi`, unverified).
  - There is **no footer**: no release date, label or copyright text. An album track's duration is only in `fixedColumns` and its artist column is empty.
  - A long playlist ends with a `continuationItemRenderer` after 100 tracks; page 2 (`{"continuation": token}`) is `onResponseReceivedActions[0].appendContinuationItemsAction.continuationItems[]`. A second token, `secondaryContents.sectionListRenderer.continuations[0].nextContinuationData`, returns `continuationContents.sectionListContinuation` with "Related playlists" (guest) or the "Suggestions" shelf (own playlist, `ytmusicapi`).
  - **A playlist continuation sent without the issuing visitor does not fail: it silently returns page 1 again.**
  - The artist `subscribeButtonRenderer.channelId` differs from the page `browseId`. A guest gets `subscribed: false`.
- **Not available.** A non-existent `VL…`, `VLOLAK…`, `MPREb_…` or `UC…` id returns HTTP 200 with no `contents` key (only `trackingParams` and `microformat.noindex`): no `alerts`, no 4xx. Private playlists of another user were not captured and are assumed to behave the same.
- **Up next (`next`).**
  - There are 4 tabs: Up next, Lyrics, Comments, Related. Tabs are found by `endpoint.browseEndpoint` page type (`MUSIC_PAGE_TYPE_TRACK_LYRICS`, `MUSIC_PAGE_TYPE_TRACK_RELATED`), never by title. A track without lyrics keeps the endpoint and adds `unselectable: true`.
  - Tab 0 `musicQueueRenderer`: `header.musicQueueHeaderRenderer.subtitle` is the source name without an endpoint; `subHeaderChipCloud` chips (radio only) carry `navigationEndpoint.queueUpdateCommand.fetchContentsCommand.watchEndpoint{playlistId, params}`; `content.playlistPanelRenderer{playlistId, contents[], continuations[0].nextRadioContinuationData}`. Rows are `playlistPanelVideoRenderer` (`selected` marks the current one). An album or bare-video queue ends with `automixPreviewVideoRenderer…watchPlaylistEndpoint`. Queue page 2 is `continuationContents.playlistPanelContinuation`.
  - A song / video counterpart (`playlistPanelVideoWrapperRenderer`) was **never returned to a guest**; the parser follows `ytmusicapi` and is unverified.
- **Lyrics.** The text uses `\r\n`; the source line is `footer` ("Source: LyricFind"). A track without lyrics returns `messageRenderer` ("Lyrics not available").
- **Library, history and guide (signed in, unverified).** The grid or shelf sits in `itemSectionRenderer.contents[0]` or directly in the section list; page 2 is `gridContinuation` or `musicShelfContinuation`. The sort options are `itemSectionRenderer.header.itemSectionTabbedHeaderRenderer.endItems[].dropdownRenderer.entries[].dropdownItemRenderer`. The "New playlist" card has no browse or watch endpoint. History is `musicShelfRenderer` per day; the removal token is the menu item with icon `REMOVE_FROM_HISTORY` (`serviceEndpoint.feedbackEndpoint.feedbackToken`). The guide entry has no owner field.
- **Out of scope by decision #7.** Podcast shows, episodes and user profiles in search results, and the weekly podcast shelf on Charts, are skipped and logged; the Podcasts, Episodes and Profiles search filters and the Podcasts and Uploads library sections are dropped by `params` / `browseId`.

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
