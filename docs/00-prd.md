# 00. Product requirements — RutaWave

Status: draft 1, 2026-11-18. Owner: Oleksii Kruhlyk.

This document says **what** the product is, **for whom** and **why**, and what
"done" means for each release. The other documents say **how**:
[02](02-architecture.md) architecture, [03](03-roadmap.md) stages,
[06](06-backlog.md) delivery rows, [07](07-designbook.md) look,
[08](08-ui-spec.md) behaviour of every screen. When this file and one of them
disagree on scope, this file wins; on implementation detail, they win.

Labels as in the rest of the docs: **[decision]** — a product choice;
**[observed]** / **[known]** — a fact about YouTube Music, see the README.

---

## 1. Name and positioning

| | |
|---|---|
| Name | **RutaWave** **[decision, 2026-11-20; spelled with a capital W since 2026-11-25]**. Identifiers stay lower case (`rutawave`); the Xcode project, targets, scheme and `RutawaveApp` keep the old spelling. |
| Subtitle (DMG, README, About window, GitHub description) | *A native YouTube Music client for macOS* |
| One-liner | YouTube Music as a real Mac app: native SwiftUI interface, media keys, menu bar, plugins — no Electron. |
| Disclaimer (README, About window) | *RutaWave is an independent project and is not affiliated with, endorsed or sponsored by Google or YouTube.* |
| Previous working names | Redwave (2026-11-18 – 2026-11-20, used in code until backlog 0.4), Tunewave (used in code and docs up to backlog 1.4) |

**Why this name.**
- The main audience is Ukrainian. "Ruta" comes from *Chervona Ruta* ("Red
  Rue"), a song every Ukrainian knows: it says "music" and "red" at once,
  and red points at YouTube's colour. "Wave" is sound.
- Redwave was dropped because it was too generic: nothing in it said music.
  "Wave" alone still does not, so the name always goes with the subtitle.
- "Ruta" alone is used by too many products; "RutaWave" was free on GitHub
  on 2026-11-20.
- "YouTube", "YT" and "YouTube Music" are Google trademarks ([05 §2.2](05-risks-and-scope.md#2-legal-and-policy-constraints)).
  They appear only in the descriptive subtitle ("a client **for** YouTube Music"),
  never in the name, icon or bundle ID.
- The capital W splits the two parts (Ruta + Wave), so the word reads at a glance.
- Easy to read in Latin and Cyrillic (Рутавейв), and different from existing
  clients (Pear Desktop and others).

**Identifiers that follow from the name** **[decision]**:

| What | Value |
|---|---|
| App and product name | `RutaWave` / `RutaWave.app` |
| Bundle ID | `dev.kruhlyk.rutawave` |
| Keychain service of the session | `dev.kruhlyk.rutawave.session` |
| Xcode project (generated) | `Rutawave.xcodeproj` |
| DMG file | `RutaWave-<version>-arm64.dmg` |
| URL scheme for links (stage 5.4) | `rutawave://` |

Backlog row **0.4** ([06](06-backlog.md#stage-0-preparation)) moved the code
from the Redwave identifiers (`dev.kruhlyk.redwave`, …) to the ones above. The
renamed build removes the session stores of the previous identifiers on launch,
as row 0.3 did for Tunewave
([05 §2.4](05-risks-and-scope.md#2-legal-and-policy-constraints)).

**Name check, 2026-11-25** ([#28](https://github.com/AratKruglik/yt-music-mac/issues/28)). This is a self-check, not legal advice.

- **Domains:** `rutawave.com`, `.app`, `.dev`, `.net`, `.org`, `.io`, `.ua` and `.com.ua` are unregistered (WHOIS / RDAP).
- **Trademarks:** "RutaWave" has no exact match in TMview, which covers EUIPO, the USPTO, WIPO, the UK, the Ukrainian register and other national offices. The УКРНОІВІ register (СІС) itself was also searched directly by keyword and has no match.
- **Products:** no software, app or GitHub repository is called RutaWave (web search, the App Store, GitHub).
- **Nearby marks to keep in mind:**
  - *RUTA*, two pending applications in classes 9 and 42. EUIPO 019445038 is a figurative mark for software and SaaS, filed 2026-11-04, with opposition open until 2027-02-10. USPTO 98145984 is a word mark for field-service CRM software. RutaWave shares the prefix, but the whole word, the sound and the field (music client vs business software) differ, so the risk is judged low.
  - *червона рута* is registered in Ukraine in class 9 (m202212262, owned by an individual, filed 2022-10-05).
  - *червона ruta* is registered in Ukraine in classes 35, 38 and 41 (m201704221, ТОВ «МЮЗІКРАДІО»).
  - *фестиваль червона рута* was filed in Ukraine in classes 35 and 41 (m202618337, 2026-09-04).
  - RutaWave uses neither "червона"/"chervona" nor the festival's name, so it does not reproduce these marks; the reference stays in the backstory, not in the name, icon or copy.
- **Not done:** registering "RutaWave" as a trademark or buying a domain is the owner's decision. Repeat the TMview search before release 0.1, because new applications appear weekly.

---

## 2. Problem

YouTube Music has no native macOS app. People listen in a browser tab, an
installed web app (PWA) or an Electron wrapper ([pear-desktop](01-reverse-engineering.md)). Both:

- feel like a web page: no native menus, sidebar, keyboard focus, VoiceOver,
  window behaviour or system look;
- use a lot of memory (a whole Chromium for one site);
- are lost among browser tabs, so media keys and Now Playing work unreliably;
- with the wrapper, add extra features (lyrics, scrobbling, Discord, equalizer)
  only as page injections that break when the site changes.

## 3. Product goal

A YouTube Music client that a Mac user picks over the browser tab every day:
**it looks and behaves like a Mac app, starts fast, stays out of the way, and
plays everything the site plays** — with the same account, library,
recommendations and Premium benefits.

### 3.1. Goals

| # | Goal | How we know |
|---|---|---|
| G1 | Daily listening without opening the browser | Release 0.1 covers every flow in §5.1–§5.6 |
| G2 | Native macOS feel | Every screen follows [07](07-designbook.md) §8 checklist; system menus, media keys, Now Playing, menu bar work |
| G3 | Lighter than Electron | §7.1 budgets |
| G4 | Works with or without an account | Guest mode covers browse, search, play (§5.1) |
| G5 | The extras people install the wrapper for | Release 0.2 ships the first plugin wave (§5.9) |

### 3.2. Non-goals

Taken from [05 §3](05-risks-and-scope.md#3-what-we-deliberately-do-not-do);
they are product decisions, not just postponed work:

- downloading tracks to files, offline caching of audio;
- ad blocking or analytics blocking;
- direct audio streams / `AVPlayer` (audio stays in the site player);
- Windows, Linux, iOS, iPadOS;
- App Store distribution; third-party plugins; user CSS themes;
- a light theme (dark only, like the reference).

---

## 4. Users

| Persona | Who | What matters to them |
|---|---|---|
| **P1. Premium listener** (primary) | Mac user with YouTube Music Premium, listens several hours a day while working | No ads, media keys, menu bar control, low memory, library and playlists at hand |
| **P2. Free listener** | Signed in, no Premium | Same as P1; accepts the ads YouTube serves (we do not block them) |
| **P3. Guest** | Not signed in, or trying the app | Browse, search and play without giving the app a Google account |
| **P4. Power user** | Former pear-desktop user | Plugins: lyrics, scrobbling, Discord, equalizer, global hotkeys, local API |

Primary platform: Apple Silicon Macs, macOS 14 or later. Distribution is a
DMG for personal use and a small circle of people ([05 §2.1](05-risks-and-scope.md#2-legal-and-policy-constraints)).

---

## 5. Functional requirements

Priority: **P0** — release 0.1 cannot ship without it; **P1** — expected in
0.1, can slip to 0.1.x; **P2** — release 0.2 or later. "Spec" points to the
detailed behaviour; "Row" to the backlog row that delivers it.

### 5.1. Session and accounts

| ID | Requirement | Pri | Spec | Row |
|---|---|---|---|---|
| F-AUTH-1 | The app starts in guest mode with no sign-in step; browse, search and playback work without an account | P0 | 08 §1.1 | 1.4 |
| F-AUTH-2 | Sign in on Google's own page inside the app; the password never passes through app code | P0 | 02 §6 | 1.1 ✓ |
| F-AUTH-3 | The session survives a relaunch | P0 | — | 1.1 ✓ |
| F-AUTH-4 | ~~Several Google accounts in one session; switching reloads data and keeps playback~~ — out of scope (decided no, single-account) | P1 | 08 §13 | 1.3 |
| F-AUTH-5 | Sign out clears the session on this Mac (Keychain + web data) and returns to guest mode | P0 | 05 §2.4 | 1.1 ✓, 1.4 |
| F-AUTH-6 | Account-only actions stay visible for guests and explain "Sign in to …" with a Sign in button | P0 | 08 §1.2 | 1.4, 4.x |
| F-AUTH-7 | An expired session leads to a clear re-sign-in, not empty screens | P0 | 08 §14.1 | 2.1 |

### 5.2. Browse and discovery

| ID | Requirement | Pri | Spec | Row |
|---|---|---|---|---|
| F-BRW-1 | Home: mood chips and horizontal shelves, paged | P0 | 08 §5 | 2.2, 4.2 |
| F-BRW-2 | Explore: New releases, Charts with country selector, Moods & genres | P1 | 08 §6 | 4.2 |
| F-BRW-3 | Album, artist (with Subscribe), playlist pages, long playlists paged | P0 | 08 §8 | 2.3, 2.4, 4.4 |
| F-BRW-4 | "More" lists for every shelf | P1 | 08 §1.3 | 4.2 |
| F-BRW-5 | ~~Podcasts (show, episode, library section)~~ — out of scope (decided no, #7) | P2 | 08 §8.4 | 4.9 |

### 5.3. Search

| ID | Requirement | Pri | Spec | Row |
|---|---|---|---|---|
| F-SRC-1 | Search field in the top bar, ⌘F / ⌘L, suggestions while typing | P0 | 08 §3.1 | 2.2, 4.3 |
| F-SRC-2 | Results page with filters (songs, videos, albums, artists, playlists) | P0 | 08 §3.2 | 4.3 |
| F-SRC-3 | Search history in the dropdown with delete (signed in) | P1 | 08 §3.1 | 2.4, 4.3 |

### 5.4. Library (signed in)

| ID | Requirement | Pri | Spec | Row |
|---|---|---|---|---|
| F-LIB-1 | Playlists, songs, albums, artists, subscriptions, liked music | P0 | 08 §7 | 2.3, 4.5 |
| F-LIB-2 | Sidebar list of own and saved playlists; New playlist | P0 | 08 §4 | 2.3, 4.1, 4.5 |
| F-LIB-3 | Like / dislike, save to library, add to playlist, edit own playlist | P0 | 08 §11 | 2.4, 4.6 |
| F-LIB-4 | History page with removal from history | P1 | 08 §7 | 2.3, 2.4, 4.5 |

### 5.5. Playback

| ID | Requirement | Pri | Spec | Row |
|---|---|---|---|---|
| F-PLY-1 | Everything the site plays plays here, including Premium quality and, for free accounts and guests, the ads YouTube serves | P0 | 02 §3 | 3.1 |
| F-PLY-2 | Player bar: artwork, title, artist, play/pause, previous/next, seek, volume, like, shuffle, repeat | P0 | 08 §9 | 3.2, 4.1 |
| F-PLY-3 | Audio continues with the window minimized, hidden or on another Space | P0 | 05 risk 4 | 3.1 |
| F-PLY-4 | Up next queue: view, jump, reorder by drag, remove, play next / add to queue, radio chips, save queue as playlist | P0 | 08 §10.2 | 2.3, 3.2, 4.6 |
| F-PLY-5 | Player page with Lyrics and Related tabs (the Song/Video toggle is deferred, [#12](https://github.com/AratKruglik/yt-music-mac/issues/12)) | P1 | 08 §10 | 2.3, 4.8 |
| F-PLY-6 | Comments tab | P2 | 08 §10.4 | 4.8 |
| F-PLY-7 | A web view crash or a stalled player recovers by itself and returns to the same track and position | P0 | 03 stage 3 | 3.2 |

### 5.6. macOS integration

| ID | Requirement | Pri | Spec | Row |
|---|---|---|---|---|
| F-MAC-1 | Now Playing in Control Centre and the lock screen; media keys and AirPods controls | P0 | 03 stage 5 | 5.1 |
| F-MAC-2 | App menu with every command and its shortcut; keyboard map of 08 §14.3 | P0 | 08 §14.3 | 4.7, 5.2 |
| F-MAC-3 | Menu bar item with current track and mini controls | P1 | — | 5.2 |
| F-MAC-4 | Dock menu; track-change notifications (can be turned off) | P1 | — | 5.2 |
| F-MAC-5 | Settings window: General (incl. app language), Playback, Account (Plugins in 0.2) | P0 | — | 5.3 |
| F-MAC-6 | Resume on start: last track and position, paused | P1 | 08 §14.5 | 5.3 |
| F-MAC-7 | Launch at login, always on top, starting page | P2 | — | 5.3 |
| F-MAC-8 | Mini player window | P2 | — | 5.4 |
| F-MAC-9 | Opening `music.youtube.com/...` links and `rutawave://` links | P2 | 08 §1.3 | 5.4 |

### 5.7. Cross-cutting UX

| ID | Requirement | Pri | Spec | Row |
|---|---|---|---|---|
| F-UX-1 | Loading skeletons, empty states, page / inline / action errors with Retry | P0 | 08 §14.1 | 4.7 |
| F-UX-2 | Offline banner; retries resume when the network returns | P1 | 08 §14.1 | 4.7 |
| F-UX-3 | Toasts with Undo for reversible changes | P1 | 08 §14.2 | 4.6 |
| F-UX-4 | Context menus with one shared action set; multi-select; drag and drop to playlists and the queue | P1 | 08 §11–12 | 4.6 |
| F-UX-5 | Navigation state, sidebar, volume, repeat, shuffle remembered between launches | P1 | 08 §14.5 | 4.1, 5.3 |

### 5.8. Distribution

| ID | Requirement | Pri | Spec | Row |
|---|---|---|---|---|
| F-DST-1 | One command builds an ad-hoc signed DMG with Hardened Runtime | P0 | 03 stage 8 | 8.1 |
| F-DST-2 | README: install from DMG, allowing a non-notarized app, disclaimer, limitations | P0 | 03 | R1 |
| F-DST-3 | Auto-update (Sparkle) | P2 | 05 Q10 | after R1 |

### 5.9. Plugins

Built in, switched on and off in Settings without a relaunch; full list and
decisions in [04](04-plugins.md).

| ID | Requirement | Pri | Row |
|---|---|---|---|
| F-PLG-1 | Plugin infrastructure, toggles in Settings | P2 | 6.1 |
| F-PLG-2 | Synced lyrics in the Lyrics tab (built in, not a plugin toggle) | P2 | 6.2 |
| F-PLG-3 | Last.fm and ListenBrainz scrobbling | P2 | 6.3 |
| F-PLG-4 | Discord Rich Presence | P2 | 6.4 |
| F-PLG-5 | Playback tweaks: precise / exponential volume, speed, skip disliked, disable autoplay | P2 | 6.5 |
| F-PLG-6 | Configurable global hotkeys | P2 | 6.6 |
| F-PLG-7 | Equalizer, compressor, crossfade, visualizer, skip silences (after the Web Audio spike 7.0) | P2 | 7.0–7.3 |
| F-PLG-8 | Output device, SponsorBlock, local `/api/v1` server, artwork colour theme | P2 | 7.4–7.6 |

---

## 6. Key user flows

1. **First launch as a guest.** Open the DMG, drag to Applications, allow the
   launch in Privacy & Security → the app opens on Home with no sign-in →
   search a song → play → media keys work.
2. **Sign in.** Sign in button → Google's page in a sheet → back on Home with
   the account's recommendations, library in the sidebar, playback not interrupted.
3. **Daily listening.** Launch at login → resume last track paused → space or
   media key to play → control from the menu bar or Control Centre while the
   window is hidden.
4. **Build a playlist.** Search → select several rows → drag to a sidebar
   playlist → toast with Undo.
5. **Queue work.** Play an album → open the player page → reorder Up next,
   remove a track, "Play next" from a context menu elsewhere, save queue as playlist.
6. **Recover.** Network drops → offline banner → network returns → pages and
   the player continue without a relaunch.

---

## 7. Non-functional requirements

### 7.1. Performance and resources

| Metric | Target | How measured |
|---|---|---|
| Cold start to interactive Home (cached client version, signed in) | ≤ 2 s on M1 | Instruments, App Launch |
| Track start after click | ≤ 1.5 s on a normal connection | log timestamps `load` → `songChanged` |
| Memory while playing, main window open | ≤ 400 MB total (app + WebKit processes) | Activity Monitor, 30 min session |
| Memory, window closed, playing from the menu bar | ≤ 300 MB | same |
| CPU while playing audio, window hidden | ≤ 3 % average | same |
| Scrolling shelves and long playlists | no visible stutter at 60 fps | Instruments, Hitches |

### 7.2. Reliability

- Unknown blocks in InnerTube responses are skipped and logged; a screen never
  fails completely because of one unknown shelf ([05](05-risks-and-scope.md) risk 2).
- A web view crash or a stalled player recovers within 10 s to the same track
  and position (F-PLY-7).
- One hour of continuous playback with the window hidden has no stops caused
  by the app.

### 7.3. Security and privacy

- Google password never touches app code; sign-in happens on Google's page.
- Session cookies live only in the Keychain and the WebKit data store; never
  in logs, fixtures, crash reports or `UserDefaults` ([05 §2.4](05-risks-and-scope.md#2-legal-and-policy-constraints)).
- The app sends data only to Google (YouTube Music) and to services of plugins
  the user turned on (Last.fm, ListenBrainz, Discord, SponsorBlock). No
  analytics or telemetry of our own.
- Hardened Runtime on; no `get-task-allow` in release builds.
- The accepted residual risk of the WebKit data store holding Google-wide
  cookies is documented in 05 and stays accepted for personal-use distribution.

### 7.4. Accessibility

Full VoiceOver labels, keyboard-only use of every flow in §6, focus order and
hover-only actions reachable from menus, as in [08 §14.4](08-ui-spec.md#144-accessibility).
Dynamic Type is not used on macOS; text sizes follow 07 §4.

### 7.5. Localization

English and Ukrainian strings from the first UI release, through a String
Catalog; no other languages are planned (#15). By default the app follows the
system language order (Ukrainian if it comes before English, otherwise
English). Settings → General lets the user pick System, English or
Українська; the choice applies after a relaunch, and the app offers to
relaunch right away. Content from YouTube (shelf titles, labels) is requested
in the same language.

### 7.6. Compatibility

macOS 14 or later, Apple Silicon only: the Release build and the DMG are
`arm64`; Intel Macs are not supported (open question #9, [#29](https://github.com/AratKruglik/yt-music-mac/issues/29)).

---

## 8. Releases

| Release | Content | Exit criteria |
|---|---|---|
| **0.1.0** — daily driver | Stages 0–5 and 8: all P0, most P1 of §5.1–§5.8 | Flows 1–7 of §6 pass by hand; §7.1 budgets met; DMG installs on a clean user account |
| **0.1.x** | Remaining P1, fixes from daily use | — |
| **0.2.0** — plugins | Stages 6–7: §5.9 | Every plugin toggles without a relaunch, has unit tests for its logic; audio effects survive track changes |
| **later** | P2 leftovers, Sparkle, music video mode (Song/Video toggle, captions, picture-in-picture; [#12](https://github.com/AratKruglik/yt-music-mac/issues/12)) | by decision |

Order and dependencies are in [06](06-backlog.md); the DMG stage is moved
before the plugins so working builds can be installed early.

---

## 9. Success measures

The app is for personal use and a small circle, so measures are practical, not growth metrics:

| Measure | Target |
|---|---|
| The browser tab with music.youtube.com is no longer opened | after 0.1.0, for two weeks of daily use |
| Crashes and stuck playback | none in a week of daily use |
| Screens broken by a YouTube change | fixed within one release; parser tests catch the change first |
| §7.1 budgets | met at every release |

---

## 10. Risks, constraints, open questions

Kept in one place, [05](05-risks-and-scope.md). The ones that shape the product:

- **Terms of Service and trademarks** — personal use, own name and icon,
  disclaimer, DMG outside the App Store.
- **YouTube changes** — InnerTube format and the site player can change at
  any time; isolated parsers and one `bridge.js` keep fixes small.
- **Ads for guests and free accounts** — accepted, not blocked.

Open questions that affect this PRD:
#5 lyrics source, #6 optional plugins, #10 auto-update.
Question #9 is settled: Apple Silicon only (§7.6).
Question #1 (name, bundle ID, icon) is settled here; the icon is done (2026-11-25, [spec](superpowers/specs/2026-11-25-app-icon-design.md)), pending the trademark review of #28.

---

## 11. Change log

| Date | Change |
|---|---|
| 2026-11-18 | Draft 1. Product named **Redwave** (was Tunewave); bundle ID `dev.kruhlyk.redwave`; rename in code planned as backlog 0.3 |
| 2026-11-19 | Podcasts and user uploads out of scope (open question #4, #7); F-BRW-5 dropped |
| 2026-11-19 | Music video mode deferred to later (open question #3, #12); Song/Video toggle removed from F-PLY-5; 02 §4.1 requires a re-parentable web view |
| 2026-11-20 | Product renamed **RutaWave** (was Redwave: too generic, nothing said music; main audience is Ukrainian); bundle ID `dev.kruhlyk.rutawave`; rename in code planned as backlog 0.4 |
| 2026-11-20 | Localization decided (open question #7, #15): English and Ukrainian only; in-app language switch in Settings → General, system language by default; removed from non-goals |
| 2026-11-25 | Architecture decided (open question #9, [#29](https://github.com/AratKruglik/yt-music-mac/issues/29)): Apple Silicon only; the Release build and the DMG are `arm64`, no universal binary (§7.6) |
