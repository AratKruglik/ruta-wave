# 05. Risks, scope and open questions

## 1. Risks

| # | Risk | Likelihood | Impact | What we do |
|---|---|---|---|---|
| 1 | Google blocks sign-in in `WKWebView` as an "insecure browser" | medium | the project stops | checked first (stage 1); Safari User-Agent; fallbacks are `ASWebAuthenticationSession` or importing cookies |
| 2 | The InnerTube response format changes without notice | high over time | individual screens come up empty | parsers are isolated, tolerant of unknown blocks, covered by fixture tests |
| 3 | The site player's methods differ from what is expected, or change | medium | controls do not work | all access is in one `bridge.js`; we consult the `pear-desktop` code, which solves the same problem |
| 4 | WebKit suspends the hidden web view | medium | audio stops in the background | the web view is attached to a window; checked at stage 3 with the window minimized and hidden |
| 5 | Now Playing conflict between WebKit and the app | medium | duplicated or wrong metadata in Control Centre | checked at stage 5; disable Media Session on the page |
| 6 | DRM-protected videos or tracks do not play in `WKWebView` | low for music | individual tracks unavailable | WebKit supports FairPlay; check at stage 3 on several content types |
| 7 | Web Audio effects break because of CORS on the media stream | medium | equalizer and visualizer do not work | check with one prototype at the start of stage 7, before writing all audio plugins |
| 8 | The session expires, cookies rotate | high | sudden 401s | on a 401 re-read cookies from the web view store; if that does not help, show the sign-in window |
| 9 | Web view memory use | high | 150–300 MB on top of the native UI | acceptable; still far less than Electron |
| 10 | Amount of work: a native UI is effectively a new client | high | the project drags on | stages are ordered so that after stage 5 there is an app fit for daily use with no plugins at all |
| 11 | Ad-hoc signature: Keychain and system permissions are requested again after every new build | high | repeated Keychain password prompt or repeated sign-in | acceptable for personal use; check at stage 8, and if needed use a local self-signed certificate with a stable identity |

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
4. **Credentials.** Session cookies give full access to the Google account
   within YouTube. They are stored only in the Keychain, never logged, and never
   end up in fixtures or crash reports.

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
| 1 | App name, bundle ID, icon | stage 0 |
| 2 | Whether multiple accounts are needed (`X-Goog-AuthUser`) | stage 1 |
| 3 | Whether to show music videos, or only audio with artwork | stages 3–4 |
| 4 | Whether podcasts and user-uploaded music are needed | stage 2 |
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
