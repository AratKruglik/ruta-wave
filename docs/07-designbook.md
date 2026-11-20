# 07. Designbook — how Rutawave looks

This file fixes the **visual** language of the app: layout, tokens, components
and their states. What every part of the interface **does** is described in
[08-ui-spec.md](08-ui-spec.md).

## 1. Source and rules of the game

- **Reference design:** seven screenshots of the original app (`pear-desktop` on
  `music.youtube.com`, Ukrainian locale, artwork colour theme on), supplied by
  the user on 2026-11-18. They show: Home, Explore, a playlist page (plain and
  with a hovered row), the search history dropdown and the player page (song
  and video). The screenshots are **not** stored in the repository: they carry
  account data and copyrighted artwork. **[decision]**
- **Reference metrics:** CSS tokens of `music.youtube.com`, read from the live
  site on 2026-11-18 as a guest (`--ytmusic-*` custom properties). **[observed]**
- **Functionality** is YouTube Music's; the **look** is the screenshots'.
- Sizes come from the CSS metrics (1 CSS px ≈ 1 pt). The screenshots were taken
  at about 0.75 page zoom on a 2× display, so their pixels are only used for
  colour, proportions and composition, never as sizes. **[decision]**
- Labels in this document:
  - **[observed]** — measured on the live site or sampled from the screenshots;
  - **[decision]** — a choice for Rutawave.

### What we deliberately do not copy

| In the reference | In Rutawave | Why |
|---|---|---|
| YouTube Music logo and red play mark in the top bar | Rutawave wordmark and the app's own icon | trademarks, [05 §2.2](05-risks-and-scope.md#2-legal-and-policy-constraints) |
| YouTube Sans, Roboto | SF Pro (system font) with the same sizes and weights | YouTube Sans is proprietary; no bundled fonts ([02 §1](02-architecture.md#1-key-decisions)) |
| Download button on the playlist header | not shown | downloading is excluded ([05 §3](05-risks-and-scope.md#3-what-we-deliberately-do-not-do)) |
| Hamburger that collapses the sidebar | the system sidebar toggle of `NavigationSplitView` | native behaviour, same result |
| "Upgrade" / Premium promos | not shown | not needed in a native UI ([02 §9](02-architecture.md#9-settings)) |

## 2. Window anatomy

```
┌──────────────────────────────────────────────────────────────────────────────┐
│ ● ● ●  [≡] Rutawave      [ 🔍 Search songs, albums, artists ]             ‹ › (A) │ top bar, 64 pt
├──────────────┬───────────────────────────────────────────────────────────────┤
│ ⌂ Home       │                                                               │
│ ◎ Explore    │                                                               │
│ ⊡ Library    │                     Content (NavigationStack)                 │
│ ──────────── │                                                               │
│ (+ New pl…)  │       one screen at a time: Home, Explore, Library, Search,   │
│ Liked music  │       Album, Artist, Playlist, Player page                    │
│  Auto        │                                                               │
│ Playlist 1   │                                                               │
│  Owner       │                                                               │
│ …            │                                                               │
├──────────────┴───────────────────────────────────────────────────────────────┤
│ ━━━━●──────────────────────────────────────────────────────── progress, 3 pt │
│ ⏮ ▶ ⏭ 0:07 / 3:47   [art] Title / Artist • Album • Year  👍 👎 ⋮   🔈 ⟳ ⤮ ▲ │ player bar, 64 pt
└──────────────────────────────────────────────────────────────────────────────┘
```

| Region | Size | Source |
|---|---|---|
| Top bar | 64 pt high, spans the full width, traffic lights sit inside it (`.windowStyle(.hiddenTitleBar)` + full-size content) | `--ytmusic-nav-bar-height: 64px` **[observed]** |
| Sidebar | 240 pt wide, collapsible | guide width 240 px **[observed]** |
| Player bar | 64 pt high plus the 3 pt progress line on its top edge; hidden until the first track is loaded | `--ytmusic-player-bar-height: 64px`, `0px` when inactive **[observed]** |
| Content bottom inset | player bar height + 48 pt, so the last row and keyboard focus are never hidden under the bar | `--ytmusic-base-page-padding-bottom: 112px` **[observed]** |
| Content max width | 1200 pt, centred; shelves scroll horizontally inside it | **[decision]** |
| Minimum window | 960 × 600 pt; below 1100 pt width the sidebar auto-collapses | **[decision]** |

The top bar and the player bar float above the content: content scrolls under
the top bar, which gains a 1 pt bottom separator (`border`) once content is
scrolled or the player page is open (screenshots 1 and 6).

## 3. Colour

### 3.1. Model

All surfaces are **the base colour plus white at a fixed opacity**. The base
colour is the theme; everything else follows from it. Sampled pairs fit this
model within 1–2 % **[observed]**:

| Surface | Neutral base `#313131` | Brown base `#433624` | Overlay |
|---|---|---|---|
| Base (window, sidebar, content) | `#313131` | `#433624` | — |
| Chip, secondary button, selected sidebar item, hovered row | `#464646` | `#574a3a` / `#564c39` | white 10 % |
| Player bar, menus, search dropdown | `#4a4a49` | — | white 12 % |
| Search field | `#50504f` | — | white 15 % |

### 3.2. Theme

- **Neutral theme** (always available, default until S7): base `#313131`
  (`theme.base`). **[observed]** in screenshots 5–7.
- **Artwork theme** (the target look of the screenshots): the base is derived
  from the current track's artwork. It belongs to the `album-color-theme`
  plugin, scheduled for S7 in [04](04-plugins.md); the designbook only fixes
  how it must look:
  - take the average artwork colour (Core Image `CIAreaAverage`);
  - convert to HSB, keep the hue, clamp saturation to ≤ 0.45 and brightness to
    0.18–0.28, so `text.secondary` keeps at least 4.5:1 contrast on the base;
  - pages with a header image (playlist, album, Home with a mood) add a
    vertical gradient from the base tinted 15 % lighter at the top to the plain
    base at 400 pt (screenshots 2, 3, 7);
  - the base animates to a new colour over 0.6 s ease-in-out on track change;
    with Reduce Motion it switches instantly.
- Rutawave is **dark only**, like the reference. Light appearance is not
  supported; the window forces `.preferredColorScheme(.dark)`. **[decision]**

### 3.3. Tokens

Names are the asset-catalog / `Color` extension names **[decision]**; values
come from the site's tokens **[observed]** unless stated.

| Token | Value | Use |
|---|---|---|
| `theme.base` | dynamic, `#313131` neutral | window background |
| `surface.fill` | white 10 % | chips, secondary circular buttons, selected sidebar item, hovered row, Explore tiles |
| `surface.raised` | white 12 % | player bar, popovers, menus, search dropdown |
| `surface.field` | white 15 % | search field |
| `surface.inverse` | `#f1f1f1` | primary play button, "Save" pill, selected chip, selected segment |
| `text.primary` | `#f1f1f1` | titles, body |
| `text.secondary` | white 70 % | subtitles, metadata, durations |
| `text.tertiary` | `#aaaaaa` | inactive tab labels, captions, placeholder |
| `text.onInverse` | `#0f0f0f` | text on `surface.inverse` |
| `text.disabled` | `#717171` | disabled controls |
| `accent.progress` | `#ff0033` | played part of the progress line and its knob |
| `accent.link` | `#3ea6ff` | links inside descriptions and lyrics source |
| `stroke.subtle` | white 20 % | outlined pill ("More"), field border, separators |
| `stroke.focus` | `#f1f1f1`, 2 pt | keyboard focus ring (screenshot 6) |
| `scrim` | black 60 % | artwork overlays (play icon on hover, now-playing row) |

## 4. Typography

SF Pro, sizes and weights taken from the site **[observed]**, mapped to SwiftUI
**[decision]**. All sizes scale with the macOS text-size setting where SwiftUI
allows it.

| Style | Size / weight | Where |
|---|---|---|
| `display` | 40 / bold (SF Pro Display) | entity page title ("Rock of Ages" in screenshot 2) |
| `shelfTitle` | 24 / bold | shelf headers, Explore tile titles |
| `shelfStrapline` | 12 / regular | the line above a shelf title (account name) |
| `tab` | 14 / medium, uppercase, tracking 0.5 | player page tabs |
| `nav` | 16 / regular; selected 16 / medium | sidebar items |
| `body` | 14 / regular | card subtitles, metadata, descriptions |
| `title` | 14 / medium | track and card titles |
| `caption` | 12 / regular | time codes, sidebar playlist owners, "Playing from" label |
| `button` | 14 / medium | pills and chips |

Truncation: titles are one line with a tail ellipsis, except card titles (two
lines) and the entity description (three lines, expandable).

## 5. Spacing, shape, icons, motion

| Token | Value |
|---|---|
| Spacing scale | 4, 8, 12, 16, 24, 32, 48 pt |
| Page side padding | 32 pt (24 pt below 1100 pt width) |
| Shelf gap (vertical) | 48 pt |
| Card gap (horizontal) | 16 pt |
| `radius.thumb` | 4 pt (list thumbnails) |
| `radius.card` | 8 pt (card artwork, search field, chips, sidebar items) |
| `radius.tile` | 12 pt (Explore tiles, hovered rows on entity pages) |
| `radius.cover` | 12 pt (entity cover) |
| `radius.pill` | height / 2 (buttons, segmented control) |
| Icons | SF Symbols, outline at rest, filled when selected or on (sidebar, like/dislike) |
| Icon sizes | 16 pt in rows, 20 pt in bars, 24 pt sidebar, 28 pt prev/next, 36 pt play in the player bar |
| Hit target | at least 32 × 32 pt for every icon button (desktop pointer), focusable with Tab |
| Hover | background fade 120 ms; never the only way to reach an action (see [08 §14](08-ui-spec.md#14-cross-cutting-behaviour)) |
| Transitions | 200 ms ease-out for panels and the player page; 0 with Reduce Motion |

## 6. Components

Each entry: anatomy → sizes → states. Behaviour is in [08](08-ui-spec.md).

### 6.1. Top bar
- Left: sidebar toggle (`sidebar.left`), Rutawave wordmark (title 20 / bold).
- Centre: search field, 480–720 pt wide (flexes), 42 pt high, `radius.card`,
  `surface.field`, magnifier icon 20 pt at 12 pt inset, placeholder in
  `text.tertiary`. Focused: `stroke.subtle` border and the dropdown below it
  (6.4).
- Right: back `‹` and forward `›` (20 pt, disabled = `text.disabled`), then the
  avatar (32 pt circle) when signed in, or a **Sign in** pill (32 pt high,
  `surface.inverse`, `text.onInverse`) for a guest.

### 6.2. Sidebar
- Navigation items: 48 pt high, `radius.card`, icon 24 pt + label `nav`.
  Selected: `surface.fill` background and filled icon. Focused: `stroke.focus`.
- Divider: 1 pt `stroke.subtle`, 16 pt vertical margin.
- **New playlist** pill: 36 pt high, `surface.fill`, `plus` icon + label,
  truncated with ellipsis.
- Playlist rows: two lines (title `title`, owner `caption` in
  `text.secondary`), 8 pt vertical padding, `radius.card`. The pinned
  auto-playlist shows a `pin.fill` 10 pt before "Auto-generated". The open
  playlist is selected like a navigation item.
- Guest: the playlist section is replaced by a sign-in card: **Sign in** pill
  (`surface.fill`) and the explanation in `caption`, `text.secondary`
  (the site's own guest promo **[observed]**).

### 6.3. Chips
- 36 pt high, horizontal padding 12 pt, `radius.card`, `surface.fill`,
  `button` style. Selected: `surface.inverse` + `text.onInverse`.
- A chip row is one line that scrolls horizontally, with a fade on the trailing
  edge when it overflows.

### 6.4. Search dropdown
- Attached to the bottom of the field, same width, `surface.raised`,
  `radius.card` on the bottom corners, shadow black 25 % / 16 pt.
- Rows 48 pt: leading icon 20 pt (`clock.arrow.circlepath` for history,
  `magnifyingglass` for a suggestion), text `body` with the typed part in
  `text.primary` and the rest in `text.secondary`; history rows end with a
  `trash` button 20 pt. Highlighted row: `surface.fill`.
- Entity suggestions (artist, album, song) are 56 pt rows with a 40 pt
  thumbnail (circle for an artist) and a subtitle.

### 6.5. Shelf (carousel)
- Header: optional 48 pt avatar or thumbnail on the left, optional strapline
  (`shelfStrapline`, `text.secondary`) above the title (`shelfTitle`); on the
  right **More** (outlined pill, 36 pt, `stroke.subtle`) and two 36 pt circular
  arrow buttons (outlined; disabled at the ends).
- Body: one row of cards, scrolls horizontally by a page with the arrows,
  trackpad or Shift+wheel; no scroll indicator.

### 6.6. Cards
| Kind | Artwork | Text |
|---|---|---|
| Square (album, playlist, mix) | 180 × 180 pt, `radius.card` | title 2 lines, subtitle 2 lines ("Album • Artist") |
| Video | 320 × 180 pt (16:9), `radius.card` | title 2 lines, "Channel • N views" |
| Artist | 180 pt circle | name 1 line centred, "N subscribers" |
| Quick pick (list in a shelf) | 48 pt thumb, `radius.thumb` | title + subtitle, 4 rows per column |

Hover: a 40 pt circular play button (`scrim` background, white icon) in the
bottom-right corner of the artwork for squares and in the centre for videos;
the ⋮ button appears at the top-right. The currently playing item shows an
animated equaliser glyph instead of the play button.

### 6.7. Track rows
Three densities, same behaviour:

| Density | Height | Thumb | Text | Trailing |
|---|---|---|---|---|
| `compact` (queue) | 56 pt | 32 pt | title / artist | duration |
| `detailed` (playlist, album, search) | 64 pt | 48 pt | title / "Artist • N plays • Album" | duration |
| `numbered` (album) | 48 pt | track number instead of thumb | title / plays | duration |

- Hover (screenshot 3): background `surface.fill` with `radius.tile`; the thumb
  gets a play icon on `scrim`; the trailing area swaps the duration for
  👍 👎 ⋮ and a selection checkbox (multi-select).
- Now playing (screenshots 1–2): background `surface.fill`, the thumb shows a
  play/pause glyph on `scrim`.
- Explicit tracks show an `E` badge (`text.secondary` square, 14 pt) before
  the artist.
- Unavailable tracks: whole row at 40 % opacity, not playable.

### 6.8. Entity header (playlist, album)
Two-column layout above 1100 pt (screenshot 2), stacked below it.
- Cover 240 × 240 pt, `radius.cover`.
- Title `display`, centred under the cover; owner line `body` (a link);
  meta lines `body`, `text.secondary` ("Playlist • 2026", "95 songs • 6 hours
  33 minutes"); description up to three lines with **More**.
- Action row: secondary circular buttons 40 pt (`surface.fill`) around a
  primary play button 64 pt (`surface.inverse`, black glyph). Order: Save to
  library (bookmark), **Play**, Share, ⋮ (plus Shuffle as a 40 pt button for
  albums and artists).
- The four thumbs row in the reference comes from the `album-actions` plugin;
  in Rutawave those actions live in the ⋮ menu ([04](04-plugins.md) #1).

### 6.9. Artist header
Full-width image 16:9 cropped to 360 pt high, `theme.base` gradient at the
bottom, name `display` over it, then Shuffle, Radio and Subscribe (pill with
the subscriber count) buttons.

### 6.10. Explore tiles
Three tiles in a row, each ≈ 1/3 of the content width × 108 pt, `radius.tile`,
`surface.fill`, icon 24 pt top-left, label `shelfTitle` bottom-left
(screenshot 5): New releases (`music.note.list`),
Charts (`chart.line.uptrend.xyaxis`), Moods & genres (`face.smiling`).

### 6.11. Player bar
- Progress line along the top edge: 3 pt track in `stroke.subtle`, played part
  `accent.progress`; on hover it grows to 5 pt and shows a 12 pt knob and a
  time tooltip over the pointer.
- Left group: previous (28 pt), play/pause (36 pt), next (28 pt), time
  "0:07 / 3:47" `caption`, `text.secondary`.
- Centre group (max 560 pt): artwork 40 pt (square) or 71 × 40 pt (video),
  title `title`, subtitle `body`/`text.secondary`
  ("Artist • Album • Year" or "Channel • N views • N likes"), then 👍 👎 ⋮.
- Right group: volume (icon; slider appears on hover), repeat (off / all / one:
  `repeat`, `repeat` filled, `repeat.1`), shuffle, expand chevron (`▲` opens the
  player page, `▼` closes it). Captions **CC** (only for videos with captions,
  `captions-selector`) is deferred with music video mode ([#12](https://github.com/AratKruglik/yt-music-mac/issues/12)).

### 6.12. Player page
Covers the content area (sidebar, top bar and player bar stay), slides up from
the player bar.
- Left: artwork, square up to 560 pt for songs, 16:9 for videos, `radius.card`.
  The **Song | Video** segmented pill (36 pt, selected segment
  `surface.inverse`, centred above the artwork) is deferred with music video
  mode ([#12](https://github.com/AratKruglik/yt-music-mac/issues/12)).
- Right panel, 360–420 pt wide: tabs **Up next / Lyrics / Comments / Related**
  (`tab` style, selected `text.primary` with a 2 pt underline, others
  `text.tertiary`, disabled ones at `text.disabled`).
- Up next header: "Playing from" (`caption`, `text.secondary`) + source name
  (`title`); **Save** pill on the right (`surface.inverse`, `text.badge.plus`
  icon). For radio queues a chip row under it: All / Familiar / Discover
  (labels come from the response).
- Queue rows use `compact` density.

### 6.13. Menus and dialogs
- Context menus are native `NSMenu` (`.contextMenu`), not custom popovers.
- Dialogs (new playlist, delete confirmation) are native sheets.
- Toasts ("Added to queue", "Saved to library") appear above the player bar,
  centred, `surface.raised`, `radius.card`, 3 s, with an optional **Undo**.

## 7. Existing screens and how they fit

| Screen today | In the designed shell |
|---|---|
| `SignInView` (sheet / window with Google's page) | unchanged; opened from the **Sign in** pill or the avatar menu |
| `AccountView` (header + row of 34 pt avatars, Add account, Sign out) | becomes the avatar popover in the top bar (stage 4.1): header, avatars row, Add account, Settings, Sign out |
| Guest placeholder (1.4) | replaced by the real shell in 4.1 |

## 8. Checklist for every new screen

- Uses tokens only; no raw hex or font sizes in views.
- Every icon button has an accessibility label and a tooltip (`.help`).
- Every hover action is also in the context menu and reachable from the
  keyboard.
- Focus ring visible on everything focusable; nothing focused hides under the
  player bar.
- Text keeps 4.5:1 on the base, controls 3:1 — check on the brightest allowed
  artwork base, not only on `#313131`.
- Loading, empty, error and guest states exist (see [08 §14](08-ui-spec.md#14-cross-cutting-behaviour)).
- Works with Reduce Motion and with the largest macOS text size.
