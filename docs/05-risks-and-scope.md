# 05. Risks, scope and open questions

## 1. Risks

| # | Risk | Likelihood | Impact | What we do |
|---|---|---|---|---|
| 1 | Google blocks sign-in in `WKWebView` as an "insecure browser" | medium | the project stops | **go — checked 2026-11-18 (stage 1.1, macOS 27):** sign-in in `WKWebView` with the Safari User-Agent works; the session survives a relaunch, add-account and sign-out work. Fallbacks (`ASWebAuthenticationSession`, importing cookies) are not needed for now |
| 2 | The InnerTube response format changes without notice | high over time | individual screens come up empty | parsers are isolated, tolerant of unknown blocks, covered by fixture tests |
| 3 | The site player's methods differ from what is expected, or change | medium | controls do not work | all access is in one `bridge.js`; we consult the `pear-desktop` code, which solves the same problem |
| 4 | WebKit suspends the hidden web view | medium | audio stops in the background | the web view is attached to a window; checked at stage 3 with the window minimized and hidden |
| 5 | Now Playing conflict between WebKit and the app | medium | duplicated or wrong metadata in Control Centre | checked at stage 5; disable Media Session on the page |
| 6 | DRM-protected videos or tracks do not play in `WKWebView` | low for music | individual tracks unavailable | WebKit supports FairPlay; check at stage 3 on several content types |
| 7 | Web Audio effects break because of CORS on the media stream | medium | equalizer and visualizer do not work | check with one prototype at the start of stage 7, before writing all audio plugins |
| 8 | The session expires, cookies rotate | high | sudden 401s | on a 401 the session is dropped and sign-in is shown (no cookie re-read; decided in 2.1) |
| 9 | Web view memory use | high | 150–300 MB on top of the native UI | acceptable; still far less than Electron |
| 10 | Amount of work: a native UI is effectively a new client | high | the project drags on | stages are ordered so that after stage 5 there is an app fit for daily use with no plugins at all |
| 11 | Ad-hoc signature: Keychain and system permissions are requested again after every new build | high | repeated Keychain password prompt or repeated sign-in | acceptable for personal use; check at stage 8, and if needed use a local self-signed certificate with a stable identity |
| 12 | Guest mode: signed-out playback includes YouTube audio ads, and the hidden web view plays them | certain for guests | ads between tracks for users who are not signed in | accepted (decision 2026-11-18): guest mode is in scope (backlog 1.4); ads are not blocked or skipped. Signing in with a Premium account removes them |

## 2. Legal and policy constraints

1. **YouTube's Terms of Service** prohibit accessing the service other than
   through official interfaces, and using private APIs. The project is suitable
   for **personal use**. Distribution is by DMG file outside the App Store
   (user's decision); public distribution carries the risk of claims from
   Google, and Apple can revoke a notarization or a Developer ID certificate
   following a complaint.
2. **Trademarks.** "YouTube", "YouTube Music" and the logo belong to Google.
   The app must have its own name and icon and must not pass itself off as official.
3. **The original's license is MIT.** Ideas, the `peard:*` protocol, regular
   expressions and API routes can be ported. If a noticeable amount of code or
   text is copied, keep the copyright notice.
4. **Credentials.** Two stores hold the session.
   - The Keychain item (`dev.kruhlyk.redwave.session`, generic password in the login keychain, not synchronized) holds only the `youtube.com` cookies. It is the source of the app's session state and of the cookies InnerTube sends; they give full access to the Google account within YouTube.
   - The WebKit website data store (`WKWebsiteDataStore.default()`; files named after `dev.kruhlyk.redwave` under `~/Library/HTTPStorages`, `~/Library/WebKit` and `~/Library/Caches`) is the browser session that the sign-in window and the player share. It also holds the `google.com` / `accounts.google.com` session cookies, which give access to the **whole Google account** (Gmail, Drive, account settings), not only YouTube. Unlike Safari's cookies, which macOS protects behind Full Disk Access, these files are readable without any prompt by every process running as the same user, and the cookie files can be copied by file backups such as Time Machine.
   - Since backlog 0.3 every launch removes the Keychain item and the WebKit, cookie, cache and preferences files of the previous working-name identifier until none are left.
   - **Status: accepted for personal use (user decision, 2026-11-18, re-confirmed after the security review).**
   - Sign-out clears both stores on this Mac only. It does not end the session at Google: a copy that has already leaked, or sits in a backup, stays valid until Google expires it or the user signs the device out in the Google Account or changes the password.
   - Cookie values are never logged and never end up in fixtures, test output or crash reports.

## 3. What we deliberately do not do

| What | Why |
|---|---|
| Downloading tracks to files | violates YouTube's terms and copyright |
| Blocking ads and analytics | interferes with the service; Premium has no ads |
| Direct audio streams and `AVPlayer` | requires bypassing the signature and PoToken; see [02](02-architecture.md#3-why-audio-goes-through-a-hidden-wkwebview) |
| Windows and Linux | the project is specifically about native macOS |
| Dynamic third-party plugins | security and complexity; plugins are built in |
| Themes through user CSS | a native UI has no CSS |
| A proxy of our own | the system proxy is used |
| An in-app language switch | the system language is used |
| Auto-update before the first release | there is nobody to update |

## 4. Open questions

They need a decision from the user or are settled at the stage shown.

| # | Question | When |
|---|---|---|
| 1 | ~~App name, bundle ID~~ — **decided: Rutawave, `dev.kruhlyk.rutawave`** (was Redwave; code rename is backlog 0.4) ([00](00-prd.md#1-name-and-positioning)); the icon is still open | stage 0 |
| 2 | ~~Whether multiple accounts are needed (`X-Goog-AuthUser`)~~ — **decided: yes.** Google keeps all accounts in one cookie session, so one Keychain item holds it; `Auth` stores the selected `authUserIndex` (default 0) and offers `addAccount()` (stage 1.1). `account/accounts_list` was checked on 2026-11-18 (AC13) and returned no accounts, so the list comes from `GET /getAccountSwitcherEndpoint` and switching is only a change of `X-Goog-AuthUser` (backlog 1.3; Google accounts only, brand accounts are out of scope). Sign-out ends the session of every account | — |
| 3 | ~~Whether to show music videos, or only audio with artwork~~ — **decided: later** (2026-11-19, [#12](https://github.com/AratKruglik/yt-music-mac/issues/12)). v1 plays audio with artwork only: no Song / Video toggle (#22), no `captions-selector` or `video-toggle` (#39), no `picture-in-picture` (#46). Video items (OMV, UGC) still play as audio with their 16:9 thumbnail. The player web view stays re-parentable so video mode can be added later ([02 §4.1](02-architecture.md#41-web-view), #13) | — |
| 4 | ~~Whether podcasts and user-uploaded music are needed~~ — **decided: no** (podcasts and user uploads, 2026-11-19, [#7](https://github.com/AratKruglik/yt-music-mac/issues/7)). The parsers skip podcast and upload items and hide the Podcasts, Episodes and Profiles search filters and the Podcasts and Uploads library sections. Known limitation: uploaded tracks and episodes inside own playlists, Liked songs and history are dropped, so a playlist's "N songs" can exceed its rows | — |
| 5 | Source of synchronized lyrics: YouTube only, or third-party services too (LRCLIB and others) | stage 6 |
| 6 | Which of the "If needed" plugins are actually wanted | stage 7 |
| 7 | Localization: only Ukrainian and English, or more | stage 4 |
| 8 | ~~Whether there is an Apple Developer account~~ — **decided: no**, the DMG is ad-hoc signed and not notarized | — |
| 9 | DMG for Apple Silicon only, or universal (arm64 + x86_64) | stage 8 |
| 10 | Whether auto-update (Sparkle) is needed | before release |

## 5. What remains uninvestigated in the original

Details are in [01](01-reverse-engineering.md#5-limits-of-the-analysis). In short:

- runtime behaviour was not observed;
- plugins were not traced individually;
- the exact way the site player is accessed has not been established;
- the list of IPC channels was obtained by text search and may be incomplete.

If any of this is missing at some stage, the cheapest route is to read the
relevant file in the `pear-devs/pear-desktop` repository; the fallback is to
launch the original with `--inspect` (the `EnableNodeCliInspectArguments` fuse
is enabled) and observe it with REA's Electron tools.
