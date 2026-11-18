# 03. Roadmap

Seven development stages and an eighth for building the DMG.
After each one the app launches and does something useful.
There are deliberately no day estimates: stages 1–3 contain unknowns the rest depends on.

The order is by risk: first whatever could stop the project
(sign-in → data → audio), then the interface, and plugins last.

---

## Stage 0. Preparation

- [ ] `git init`, `.gitignore` for Xcode and Swift.
- [ ] Choose the app name, bundle ID and icon (not "YouTube Music", see [05](05-risks-and-scope.md)).
- [ ] Xcode project: macOS 14+, Swift 6, an empty window.
- [ ] `Packages/` directory with empty packages from [02](02-architecture.md#12-repository-layout).

**Done when:** `xcodebuild build` and `swift test` in every package pass.

---

## Stage 1. Sign-in and session

The goal is to prove that Google sign-in works in a `WKWebView`. If it does not,
the plan is revised before the rest of the code is written.

- [ ] `Auth`: a window with a `WKWebView`, Safari User-Agent, URL
      `accounts.google.com/ServiceLogin?ltmpl=music&service=youtube&continue=…`.
- [ ] Detecting a successful sign-in: navigation returned to `music.youtube.com`
      and the store contains the `SAPISID` cookie.
- [ ] Read cookies from `WKHTTPCookieStore`, save them to the Keychain.
- [ ] `InnerTube`: a minimal client — `WEB_REMIX` context, `SAPISIDHASH`
      signature, a single `account/account_menu` request.
- [ ] Screen: account name and avatar, a "Sign out" button.
- [ ] Sign-out: clear the Keychain and website data.
- [ ] Test of the `SAPISIDHASH` signature on a known vector.

**Done when:** after signing in and relaunching, the app shows the account name
without signing in again; after "Sign out" it asks to sign in again.

**Decision point:** if Google blocks sign-in in the web view even with a Safari
User-Agent, stop and pick a fallback (importing cookies from a browser, or
sign-in through `ASWebAuthenticationSession`) before going further.

---

## Stage 2. InnerTube client

- [ ] Fetch `INNERTUBE_CLIENT_VERSION` from the `music.youtube.com` page and cache it.
- [ ] Typed requests: `browse`, `search`, `music/get_search_suggestions`,
      `next`, `like/*`, `playlist/*`, `browse/edit_playlist`.
- [ ] `continuation` support — a `Page<T>` type with paging.
- [ ] `JSONValue` and helpers for walking "renderer" structures.
- [ ] Parsers: home (shelves), explore, search results, suggestions, album,
      artist, playlist, library (playlists, songs, albums, artists), history,
      "up next" queue.
- [ ] Models: `Song`, `Album`, `Artist`, `Playlist`, `Shelf`, `SearchResults`.
- [ ] Fixtures: save real responses and strip personal data from them.
- [ ] Unit tests of every parser on the fixtures.
- [ ] Error handling: 401 → session invalid → sign-in window; network errors
      with a retry; an unknown block in a response is skipped and logged.

**Done when:** parser tests pass; from the command line or a temporary screen
you can fetch home, search results for a query and the contents of a playlist.

---

## Stage 3. Playback engine

- [ ] `PlayerEngine`: hidden `WKWebView` attached to a window; verify that audio
      does not stop when the window is minimized or hidden.
- [ ] `bridge.js`: waiting for the player, event subscriptions, the command function.
- [ ] Check on the live page which player methods are really available
      (the list in [02](02-architecture.md#42-js-bridge) is labelled unverified);
      on any mismatch, consult the `pear-desktop` source.
- [ ] `PlayerCommand`, `PlayerEvent`, `SongInfo`; the event `AsyncStream`.
- [ ] Build `SongInfo` from the player response; title cleaning; artwork selection.
- [ ] Commands: play, pause, next, previous, seek, volume, mute, shuffle, repeat, like.
- [ ] Read and change the queue through the bridge.
- [ ] Failure handling: the page did not load, the player did not appear within
      N seconds, the track is unavailable, the web view crashed (reload and
      restore the position).
- [ ] Tests: title cleaning; integration test "load → `songChanged` → pause → seek".

**Done when:** from a test window with a `videoId` field and buttons, a track
plays, every command works, and the log shows the event stream with a correct `SongInfo`.

---

## Stage 4. Main interface

- [ ] Skeleton: `NavigationSplitView`, sidebar, `NavigationStack`, routes.
- [ ] Player bar: artwork, title, artist, buttons, position slider, volume,
      like, shuffle, repeat, queue button.
- [ ] Home: horizontally scrolling shelves.
- [ ] Explore.
- [ ] Search: toolbar field, suggestions, filters, results.
- [ ] Album page.
- [ ] Artist page.
- [ ] Playlist page with paging.
- [ ] Library: playlists, songs, albums, artists, liked.
- [ ] Queue panel: view, jump, drag to reorder, remove.
- [ ] Context menus: play next, add to queue, add to playlist, go to album or
      artist, share link.
- [ ] Loading states, empty states, errors with a retry button.
- [ ] Keyboard: space, arrows, ⌘F, ⌘L and so on.
- [ ] Accessibility: VoiceOver labels, focus order.

**Done when:** you can sign in, find a track through search or the library,
start it, and control playback and the queue without touching the web interface.

---

## Stage 5. macOS integration

- [ ] `MPNowPlayingInfoCenter`: title, artist, album, artwork, position.
- [ ] `MPRemoteCommandCenter`: play, pause, next, previous, seek.
- [ ] Check for a conflict with WebKit's own Now Playing; disable Media Session
      on the page if needed.
- [ ] Track-change notifications with artwork (can be turned off in settings).
- [ ] App menu: Playback, View, Go.
- [ ] Menu bar item with mini controls.
- [ ] Dock menu.
- [ ] Settings window: General, Playback, Plugins, Account.
- [ ] `resumeOnStart`: store track, playlist and position; restore paused.
- [ ] Starting page, always on top, launch at login.
- [ ] Mini player.
- [ ] Handling `music.youtube.com/...` links dropped on the icon or opened
      through "Open with".

**Done when:** media keys and Control Centre control playback, and after a
relaunch the app returns to the last track.

---

## Stage 6. Plugins, first wave

- [ ] Infrastructure: `Plugin` protocol, registry, toggles in settings, `PluginContext`.
- [ ] `notifications` (move from stage 5 into plugin form).
- [ ] `synced-lyrics`: lyrics source, synchronized line highlighting, lyrics screen.
- [ ] `scrobbler`: Last.fm (`ws.audioscrobbler.com/2.0/`) and ListenBrainz
      (`api.listenbrainz.org/1/`); keys in the Keychain.
- [ ] `discord`: Rich Presence through Discord's local IPC socket.
- [ ] `precise-volume`: volume step, hotkeys, scrolling.
- [ ] `exponential-volume`.
- [ ] `playback-speed`.
- [ ] `skip-disliked-songs`.
- [ ] `disable-autoplay`.
- [ ] `shortcuts`: configurable global hotkeys.
- [ ] `quality-changer`, `captions-selector`, `video-toggle` — if the bridge
      gives access to them.

**Done when:** every plugin can be turned on and off without a relaunch and has
unit tests for its logic.

---

## Stage 7. Plugins, second wave

- [ ] `equalizer`, `audio-compressor` — Web Audio in the page through `injectScript`.
- [ ] `crossfade`.
- [ ] `skip-silences`.
- [ ] `visualizer` — analyser data from the page, drawn in a SwiftUI `Canvas` or Metal.
- [ ] `custom-output-device`.
- [ ] `sponsorblock` (`sponsor.ajay.app`).
- [ ] `api-server`: a local HTTP server on `Network.framework` with `/api/v1/*`
      routes compatible with the original (listed in [01](01-reverse-engineering.md#47-plugins)).
- [ ] `album-color-theme`, `ambient-mode` — as properties of the native theme.
- [ ] `picture-in-picture` — for music videos.
- [ ] `touchbar`.
- [ ] `music-together`, `tuna-obs`, `lumiastream`, `amuse` — if needed.

**Done when:** the chosen plugins work and audio effects do not break playback
when the track changes.

---

## Stage 8. Building the DMG

The app is distributed as a DMG file, not through the App Store. The build
script is worth adding right after stage 5, so working builds can be installed
on your own machine.

- [ ] Release configuration: Hardened Runtime, no sandbox, architectures
      arm64 + x86_64 (or arm64 only — to be decided).
- [ ] `scripts/build-dmg.sh`:
      1. `xcodebuild archive` → `xcodebuild -exportArchive` (the `mac-application`
         method, no Developer ID);
      2. ad-hoc signing: `codesign --force --deep --sign -`;
      3. a temporary folder with the `.app` and a symlink to `/Applications`;
      4. `hdiutil create -volname … -srcfolder … -format UDZO` → `<Name>-<version>-arm64.dmg`.
- [ ] The version comes from a single place (`MARKETING_VERSION`) and ends up in the file name.
- [ ] Check: mount the DMG, drag to `/Applications`, launch, sign in, play a track.

There are two signing options; which one is used determines how the app opens for other people:

| Option | What it needs | How it opens |
|---|---|---|
| **Developer ID + notarization** | paid Apple Developer Program; `codesign --options runtime`, `xcrun notarytool submit --wait`, `xcrun stapler staple` for the `.app` and the `.dmg` | double-click, no warnings |
| **No Developer ID** (ad-hoc signature) | nothing | Gatekeeper blocks it; the user allows the launch in "System Settings → Privacy & Security" or removes the quarantine flag with `xattr -dr com.apple.quarantine` |

**Chosen: no Developer ID** (user's decision, 2026-11-18). The script signs the
app ad-hoc (`codesign --force --deep --sign -`) — on Apple Silicon an app with
no signature at all does not launch. There is no notarization.

Consequences:
- on the machine where the app was built it launches without obstacles, because
  it carries no quarantine flag;
- on another Mac, after downloading the DMG, Gatekeeper blocks the first launch;
  the README needs instructions: "System Settings → Privacy & Security → Open
  Anyway" or `xattr -dr com.apple.quarantine /Applications/<Name>.app`;
- the ad-hoc signature changes with every build, so Keychain access and system
  permissions may be requested again after an update;
- Sparkle works without a Developer ID too (updates are signed with your own EdDSA key).

**Done when:** one command produces the DMG, and the app from it installs and
works on a clean user account.

---

## Before the first public release

- [ ] README instructions on allowing a non-notarized app to launch.
- [ ] Auto-update (Sparkle) with a DMG or ZIP on your own hosting or GitHub Releases.
- [ ] README: installing from the DMG, limitations, disclaimer of any affiliation with Google.
- [ ] Review the name, icon and copy for Google trademarks.
- [ ] License review: if code or text was ported from `pear-desktop`, keep the
      MIT copyright notice.
