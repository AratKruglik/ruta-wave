# 08. UI specification — what every part of the interface does

The functional companion to [07-designbook.md](07-designbook.md): 07 says how a
part looks, this file says what it shows, where the data comes from, what each
action does, which states it has and what a guest sees. It is the reference
for stages 2.x–5.x of the [backlog](06-backlog.md).

Behaviour follows YouTube Music; the layout follows the reference screenshots
(see 07 §1). Labels as in the rest of the docs: **[observed]** — seen on
`music.youtube.com` or in the screenshots; **[known]** — from open projects,
verify when implementing; **[decision]** — a Rutawave choice.

Every part is described with the same headings:
- **Shows** — content and layout order;
- **Data** — InnerTube endpoint or player bridge source;
- **Actions** — pointer, keyboard, context menu;
- **States** — loading, empty, error;
- **Guest** — what changes without sign-in;
- **Stage** — backlog row that delivers it.

## 1. App model

### 1.1. Session modes
| Mode | Meaning | Source |
|---|---|---|
| Guest | no session in the Keychain; InnerTube requests carry no cookies, only `X-Goog-Visitor-Id` | 1.4 |
| Signed in | a session in the Keychain; requests are signed (`SAPISIDHASH`, `X-Goog-AuthUser`) | 1.1–1.3 |
| Session unavailable | the Keychain could not be read; a full-window message with **Try again** | 1.1 |

- One observable flag, `AuthSession.isSignedIn`, decides everything below;
  views never inspect cookies. **[decision, 1.4]**
- Switching mode (sign in, sign out, switch account) reloads every visible
  screen and the sidebar, keeps playback going and keeps the navigation stack
  (pages that make no sense for the new mode, such as Library for a guest,
  fall back to Home). **[decision]**

### 1.2. Account-only actions (the gating rule)
Actions that need an account: Library and everything in it, Liked music,
History, like / dislike, Save to library, Add to playlist, New playlist, playlist
editing, Subscribe, Save queue as playlist, search history, Comments posting.

For a guest these controls stay **visible** and on use open a small popover
anchored to the control: a one-line reason ("Sign in to like songs") and a
**Sign in** button. The action is not queued; after sign-in the user repeats
it. This matches the site **[observed]** and keeps layouts identical in both
modes. **[decision]** Exceptions that are hidden instead of prompting: the
sidebar playlist list (replaced by the sign-in card) and the avatar menu.

### 1.3. Navigation
- Routes: `home`, `explore`, `explore.newReleases`, `explore.charts`,
  `explore.moods`, `explore.mood(params)`, `library(section)`, `search(query,
  filter)`, `album(browseId)`, `artist(channelId)`, `playlist(playlistId)`,
  `more(browseId, params)` (a "More" list of a shelf). Podcast deep links
  (`music.youtube.com/podcast/…`, `browse/MPSP…`) have no route; stage 5.4 opens
  them in the browser.
  The player page is an overlay, not a route.
- One `NavigationStack` per sidebar section; switching sections keeps each
  stack, re-selecting the active section pops it to the root. **[decision]**
- Back / forward in the top bar, ⌘[ / ⌘], mouse buttons 4/5 and the trackpad
  swipe walk the stack of the current section.
- `music.youtube.com/...` links (drop on the Dock icon, "Open with", custom
  scheme) map to these routes; `watch?v=` starts playback (stage 5.4).
- Restoration: last section, its stack and scroll positions survive a relaunch;
  the player state follows `resumeOnStart` (stage 5.3).

## 2. Top bar

**Shows:** sidebar toggle, Rutawave wordmark, search field, back, forward,
avatar (signed in) or **Sign in** pill (guest).

**Actions**
- Sidebar toggle (⌃⌘S): collapses / expands the sidebar; state is remembered.
- Wordmark: goes to Home (root of its stack).
- Back / forward: see 1.3; disabled when there is nowhere to go.
- Avatar: opens the account popover (§13).
- **Sign in** (guest): opens the sign-in window; on success the app switches to
  signed-in mode in place; on cancel nothing changes.
- Double-click on the empty part of the bar zooms the window (system
  behaviour of a title bar).

**Stage:** 4.1.

## 3. Search

### 3.1. Field and dropdown
**Shows:** placeholder "Search songs, albums, artists". Focusing the
empty field opens the dropdown with recent searches (signed in) — up to 7
**[observed]**. Typing replaces them with suggestions: plain text suggestions
first, then entity suggestions (artist, album, song) with thumbnails.

**Data:** `music/get_search_suggestions` with the typed text (debounced
150 ms, cancelled on the next keystroke); with an empty input the same endpoint
returns the history for a signed-in user **[known]**. Removing a history entry
sends its `feedbackToken` to `feedback` **[known]**.

**Actions**
- ⌘F or ⌘L focuses the field from anywhere; Esc closes the dropdown, a second
  Esc clears the field, a third returns focus to the content.
- ↑ / ↓ move the highlight through the dropdown, Return runs the highlighted
  item, Return with no highlight runs the typed query.
- Click on a text suggestion or history row: runs the search (§3.2).
- Click on an entity suggestion: opens the artist / album page, or plays the
  song (the song becomes the start of a radio queue, as on the site).
- Trash on a history row: removes it at once (optimistic; the row comes back
  with a toast if the request fails).
- Clicking outside closes the dropdown and keeps the text.

**States:** no suggestions → the dropdown hides; request error → the dropdown
hides silently (suggestions are optional).

**Guest:** no history section; suggestions work.

**Stage:** 2.2 (suggestions parser), 4.3 (UI). History delete: 2.4 + 4.3.

### 3.2. Results page
**Shows**
1. Filter chips: All, Songs, Videos, Albums, Artists, Community playlists,
   Featured playlists (labels come from the response; only the ones it offers
   are shown) **[known]**. The Podcasts, Episodes and Profiles filters are never
   shown, even when offered; the parser drops them by `params`, not by label (#7).
2. With **All**: the top result card (large artwork, type, title, subtitle,
   **Play** and **Shuffle** / **Subscribe** buttons), then one section per
   type with 3–4 rows and a **Show all** button that switches the chip.
3. With a filter: a single list of that type, paged with `continuation` while
   scrolling (load the next page 600 pt before the end).
4. A "Did you mean / Showing results for" line when the response corrects the
   query, with a link to search the original spelling.

**Data:** `search` with `query` and the filter's `params` **[known]**.

**Actions:** rows and cards behave as everywhere (§11); the query stays in the
field; changing the chip keeps the query and replaces the history entry, so
Back returns to the previous filter.

**States:** loading → skeleton rows; no results → "No results for "query"" with
a hint to check spelling; error → message with **Retry**.

**Guest:** same results; account actions follow 1.2.

**Stage:** 2.2, 4.3.

## 4. Sidebar

### 4.1. Navigation items
Home (⌘1), Explore (⌘2), Library (⌘3). Clicking the selected item pops its
stack to the root and scrolls to the top. **Stage:** 4.1.

### 4.2. New playlist
Opens a sheet: Title (required, ≤ 150 chars), Description (optional), Privacy
(Public / Unlisted / Private, default Private). **Create** calls
`playlist/create` **[known]**, adds the playlist to the top of the sidebar list
and opens it. If songs were selected when the sheet was opened from
"Add to playlist → New playlist", they are added in the same request.
**Guest:** prompt (1.2). **Stage:** 2.4 + 4.5.

### 4.3. Playlist list
**Shows:** "Liked music" (pinned, "Auto-generated" with a pin glyph), then the
user's and saved playlists in the site's order: title + owner.

**Data:** the list the site shows in its guide (`guide` endpoint) **[known]**;
fallback `browse FEmusic_liked_playlists`.

**Actions**
- Click: opens the playlist page; the row becomes selected while it is open.
- Context menu: Play, Shuffle, Play next, Add to queue, Share, Remove from
  library (saved playlists) / Delete (own playlists, with a confirmation
  sheet).
- Drop songs (dragged from any track row) on a playlist row: adds them to it.
- Refreshes after creating, deleting, saving or removing a playlist, and on
  account switch.

**States:** loading → three skeleton rows; error → "Couldn't load playlists"
with a **Retry** link; the rest of the app keeps working.

**Guest:** replaced by the sign-in card (07 §6.2).

**Stage:** 4.1 (list), 4.5 (actions), 2.4 (mutations).

## 5. Home

**Shows**
1. Mood chips row ("Relax", "Sleep", "Energize", "Workout", "Party",
   "Commute"…). The labels and their order come from the response
   **[observed]**.
2. Shelves, as many as the response has, each with its header (07 §6.5).
   Typical kinds **[observed]**: Listen again (strapline = account name, avatar
   on the left), Quick picks (list rows in columns), Mixed for you, Song mixes,
   From your library, Recommended albums / music videos, Charts, New releases,
   "Because you listened to …".
3. More shelves load while scrolling (`continuation`).

**Data:** `browse FEmusic_home`; a chip is a `browse` with the chip's `params`
**[known]**.

**Actions**
- Chip: filters the shelves; clicking the selected chip clears the filter. The
  base colour does not change.
- **More** on a shelf: opens the `more` route with the full grid / list.
- Arrows: scroll the shelf by its visible width; disabled at the ends.
- Card click: opens the entity (album, playlist, artist). Play button on a card:
  starts it at once without opening it. Video card click: plays it.
- Quick pick row click: plays the song and starts a radio queue from it.

**States:** first load → skeleton chips and two skeleton shelves; error →
full-page message with **Retry**; a shelf that fails to parse is skipped
(2.1 rule).

**Guest:** personalised shelves (Listen again, From your library) are absent
because the response has none; the screen is otherwise the same.

**Stage:** 2.2 (parsers), 4.2 (UI).

## 6. Explore

**Shows**
1. Three tiles: New releases, Charts, Moods & genres (07 §6.10).
2. Shelves: New albums & singles, Top songs, Moods & genres (chips grid),
   Trending, New music videos **[observed]**.

**Data:** `browse FEmusic_explore` **[known]**.

**Subpages**
| Page | Shows | Data |
|---|---|---|
| New releases | grid of new albums & singles, then new music videos | `browse FEmusic_new_releases` **[known]** |
| Charts | country selector (popup button, default = account / system region), Top songs (numbered list with trend arrows), Top music videos, Top artists (numbered, with trend), Trending | `browse FEmusic_charts` with the country in `formData` **[known]** |
| Moods & genres | sections "Moods & moments", "Genres" with coloured-edge chips | `browse FEmusic_moods_and_genres` **[known]** |
| One mood / genre | shelves of playlists for it | `browse FEmusic_moods_and_genres_category` + `params` **[known]** |

**Actions:** as on Home. The chart country is remembered.

**States, Guest:** as on Home; charts and moods work for guests.

**Stage:** 2.2, 4.2. Subpages are part of 4.2.

## 7. Library

**Shows:** a chip row of sections — Playlists, Songs, Albums, Artists,
Subscriptions (offered sections come from the response) — and a sort
popup (Recently added, Recently played, A–Z, Z–A). Default section: Playlists
as a grid with a "New playlist" card first and "Liked music" second.
Podcasts and Uploads sections are never shown, even when offered (#7).

| Section | Shows | Data **[known]** |
|---|---|---|
| Playlists | grid of square cards | `browse FEmusic_liked_playlists` |
| Songs | `detailed` track list | `browse FEmusic_liked_videos` |
| Albums | grid | `browse FEmusic_liked_albums` |
| Artists | list of artists of liked songs | `browse FEmusic_library_corpus_track_artists` |
| Subscriptions | list of subscribed artists | `browse FEmusic_library_corpus_artists` |
| History | grouped by day ("Today", "Yesterday", "This week"…), `detailed` rows | `browse FEmusic_history` |
| Liked music | the playlist page of `LM` | `browse VLLM` |

History is opened from the Library header (clock button) and from the
account popover. **[decision]**

**Actions:** section chip switches the list and is remembered; sort changes the
order (server-side when the response offers it, otherwise locally); paging by
`continuation`; History rows have "Remove from history" in the context menu.

**States:** empty section → an illustration-free message with a hint, e.g.
"Songs you like appear here"; error → **Retry**.

**Guest:** the whole page is a sign-in screen: title "Enjoy your favourite
music", one line of explanation and **Sign in** **[decision]** (the site
redirects to sign-in **[observed]**).

**Stage:** 2.3 (parsers), 4.5 (UI). History removal: 2.4 + 4.5.

## 8. Entity pages

### 8.1. Playlist
**Shows** (07 §6.8): cover, title, owner (link to the channel), "Playlist •
year", "N songs • duration" (uploaded tracks and podcast episodes are skipped, so the count can exceed the rows, #7), description; action row; the track list
(`detailed`); for own playlists a "Suggestions" shelf at the end with
**Add** buttons **[observed]**.

**Data:** `browse VL<playlistId>` + `continuation` for long lists **[known]**.

**Actions**
- **Play**: plays from the first track; ⌥-click shuffles.
- Save to library (bookmark): `like/like` with the playlist id; filled when
  saved; toggles **[known]**.
- Share: copies `https://music.youtube.com/playlist?list=<id>` and shows a
  toast; also the system share menu in ⋮.
- ⋮: Shuffle play, Start radio, Play next, Add to queue, Save to playlist
  (copy into another), Like all / Dislike all (`album-actions`), Edit
  (own), Delete (own), Share.
- Row click plays the playlist from that row. Double-click is the same.
- Hover actions on a row: 👍, 👎, ⋮, checkbox.
- Multi-select: the checkbox, ⌘-click, ⇧-click; a selection bar replaces the
  action row: "N selected", Play next, Add to queue, Add to playlist, Remove
  from playlist (own), Clear.
- Own playlist editing (Edit): rename, description, privacy, cover is not
  editable; drag rows to reorder; ⌫ removes selected rows. Each change is a
  `browse/edit_playlist` action **[known]** with Undo in a toast.

**States:** loading → skeleton header + 8 rows; private / deleted playlist →
"This playlist isn't available" with **Back**; partial list error → the loaded
rows stay, a **Retry** row at the end.

**Guest:** public playlists open and play; Save, Edit, likes follow 1.2.

**Stage:** 2.3, 2.4, 4.4 (page), 4.6 (menus).

### 8.2. Album
Same header as a playlist with "Album / Single / EP • year" and the artist
link; `numbered` rows; actions: Play, Shuffle, Save to library, Share, ⋮
(Start radio, Play next, Add to queue, Save to playlist, Go to artist,
Like all / Dislike all). Below the list: release date / track count / label
footer, "Other versions" and "More from <artist>" shelves **[observed]**.
**Data:** `browse MPREb…` **[known]**. **Stage:** 2.3, 4.4.

### 8.3. Artist
**Shows** (07 §6.9): header with Shuffle, Radio, Subscribe (+ count); "Top
songs" (5 `detailed` rows + **Show all** → the artist's songs playlist), then
shelves Albums, Singles & EPs, Videos, Featured on, Fans might also like,
Playlists, About (description, view count) **[observed]**.
**Data:** `browse <channelId>`; "Show all" of a shelf → `browse` with its
`params` **[known]**.
**Actions:** Subscribe toggles `subscription/subscribe` /
`subscription/unsubscribe` **[known]** (guest: prompt). Shuffle and Radio start
playback without leaving the page.
**Stage:** 2.3, 4.4.

### 8.4. Podcast and episode
Out of scope (decided no, [#7](https://github.com/AratKruglik/yt-music-mac/issues/7)); see [05](05-risks-and-scope.md#4-open-questions) row 4.

## 9. Player bar

**Shows** (07 §6.11) the current item from the player bridge; hidden until
something is loaded.

**Data:** `PlayerEvent` stream from `PlayerEngine` (track, position, paused,
volume, like status, repeat, shuffle) ([02 §4](02-architecture.md#4-playerengine)).

**Actions**
| Control | Click | Keyboard | Notes |
|---|---|---|---|
| Previous | to the start if position > 3 s, else previous track **[observed]** | ⌘← | |
| Play / pause | toggle | Space (when no text field has focus), media keys | |
| Next | next track | ⌘→ | |
| Progress line | seek to the clicked point; drag to scrub (audio follows on release) | ⇧⌘→ / ⇧⌘← seek ±10 s | tooltip shows the target time |
| Time | click toggles elapsed / remaining | | |
| Artwork, title | open the player page | ⌘P | |
| Subtitle parts | artist → artist page, album → album page | | links, underline on hover |
| 👍 / 👎 | set / clear the rating (`like/like`, `like/dislike`, `like/removelike`) | ⌥⌘L like, ⌥⌘D dislike | filled when on; guest: prompt |
| ⋮ | the track context menu (§11) | | |
| Volume | click mutes / unmutes; hover shows a slider; scroll over it changes volume | ⌘↑ / ⌘↓, ⌘⌥↓ mute | step 5 % (S6 `precise-volume` makes it configurable) |
| CC | captions menu (video only); **deferred**, music video mode is later ([#12](https://github.com/AratKruglik/yt-music-mac/issues/12)) — no CC control in v1 | | later ([#12](https://github.com/AratKruglik/yt-music-mac/issues/12)) |
| Repeat | off → all → one → off | ⌘R | |
| Shuffle | shuffles the remaining queue | ⌘S | |
| Chevron | opens / closes the player page | ⌘P, Esc closes | |

**States:** buffering → the play glyph becomes a spinner; playback error
("This video is unavailable", region block) → toast and skip to the next track
after 3 s; ads (guests and non-Premium) → the bar shows "Ad" instead of the
title and disables seeking and next, as the page does (risk #12 in 05).

**Guest:** identical except ratings (prompt) and "Save to playlist" in ⋮.

**Stage:** 3.1–3.2 (engine), 4.1 (bar), 5.1 (media keys).

## 10. Player page

### 10.1. Left side
- **Song | Video** toggle — **deferred** past v1 ([#12](https://github.com/AratKruglik/yt-music-mac/issues/12)); v1 shows the artwork
  only. Kept for the future work: shown only when the current item has both an
  audio track (ATV) and a music video (OMV) counterpart; switching keeps the
  position **[observed]**. The counterpart id comes from the player / `next`
  response **[known]**. Video mode shows the web view itself in the artwork area.
- Artwork: the largest thumbnail; click toggles play / pause.

### 10.2. Up next tab
**Shows:** "Playing from" + source name (link to the source page), **Save**
pill, radio chips (All / Familiar / Discover…, only for radio queues), the
queue (`compact` rows) with the current item highlighted and auto-scrolled
into view; an "Autoplay" section after the user's items when autoplay adds
tracks **[observed]**.

**Data:** the queue lives in the page ([02 §4.4](02-architecture.md#44-queue));
the chips and source come from `next` **[known]**.

**Actions**
- Row click: jump to it.
- Drag rows to reorder; drag out or ⌫ removes the selected row (current track
  cannot be removed).
- Context menu: Play next, Remove from queue, Add to playlist, Go to album, Go to
  artist, Like, Share.
- Chip: replaces the upcoming part of the radio queue with the filtered one;
  the current track keeps playing.
- **Save**: saves the whole queue as a new playlist (sheet as in §4.2) or adds
  it to an existing one. Guest: prompt.

### 10.3. Lyrics tab
Plain lyrics from YouTube with the source line ("Source: …") at the bottom;
disabled (dimmed label, tooltip "Lyrics aren't available") when the track has
none **[observed]**. **Data:** `browse` with the lyrics `browseId` from `next`
**[known]**. Synced lyrics and romanisation are the S6 `synced-lyrics` plugin.

### 10.4. Comments tab
Present in the reference (screenshot 1). Its data source and guest behaviour
are **not verified**; treat as optional until checked on the live site.
Reading comments only; posting is account-only.

### 10.5. Related tab
Shelves "You might also like", "Recommended playlists", "Similar artists",
"About the artist" **[observed]**. **Data:** `browse` with the related
`browseId` from `next` **[known]**. Cards behave as on Home.

**Stage:** 2.3 (`next` parser), 4.6 (queue), 4.8 (lyrics, related,
comments).

## 11. Context menus — one action set

Every card, row and the player bar's ⋮ use the same builder, filtered by item
type and mode **[decision]**:

| Action | Song | Video | Album | Playlist | Artist | Guest |
|---|---|---|---|---|---|---|
| Play / Shuffle play | ✓ | ✓ | ✓ | ✓ | Shuffle | ✓ |
| Start radio | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| Play next | ✓ | ✓ | ✓ | ✓ | — | ✓ |
| Add to queue | ✓ | ✓ | ✓ | ✓ | — | ✓ |
| Save to library / Remove from library | ✓ | — | ✓ | ✓ | — | prompt |
| Add to playlist… (popover with search + New playlist) | ✓ | ✓ | ✓ | ✓ | — | prompt |
| Remove from playlist (own playlist rows) | ✓ | ✓ | — | — | — | — |
| Like / Dislike | ✓ | ✓ | all tracks | all tracks | — | prompt |
| Go to album | ✓ | — | — | — | — | ✓ |
| Go to artist | ✓ | ✓ (channel) | ✓ | owner | — | ✓ |
| Subscribe / Unsubscribe | — | — | — | — | ✓ | prompt |
| Remove from history (History rows) | ✓ | ✓ | — | — | — | — |
| Share → Copy link / system share | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |

"Play next" and "Add to queue" show a toast with **Undo**. **Stage:** 4.6, 2.4.

## 12. Selection and drag and drop
- Any track list supports multi-select (checkbox, ⌘-click, ⇧-click, ⌘A when
  the list has focus). The selection bar offers the actions of §11 that work
  on several songs.
- Dragging rows or cards carries their video / playlist ids. Targets: a
  sidebar playlist (add), the Up next list (insert at the drop point), the
  player bar (play next). Dragging out of the app gives the share URL.
- **Stage:** 4.6.

## 13. Account popover
Opens from the avatar. Shows: header (64 pt avatar, name, handle), the row of
34 pt avatars of the session's accounts (active one ringed; click switches),
**Add account**, **History**, **Settings…** (⌘,), **Sign out**. Behaviour of
the existing pieces is 1.1–1.3; moving them into the popover is 4.1.

## 14. Cross-cutting behaviour

### 14.1. States
| State | Rule |
|---|---|
| Loading | skeletons in the final layout (no layout shift); a spinner only for actions under 1 s |
| Empty | a short sentence that says what will appear and how; no illustrations |
| Error | page error → full-page message + **Retry**; part error → inline message + **Retry**; action error → toast; 401 → session expired flow of 2.1 |
| Offline | banner under the top bar "You're offline", pages keep what they loaded, retries resume automatically when the network returns (`NWPathMonitor`) |

### 14.2. Toasts
Short confirmations of mutating actions with **Undo** where the action can be
reverted (queue changes, playlist edits, history removal, library changes).
One at a time; a new one replaces the old.

### 14.3. Keyboard map **[decision]**
| Keys | Action |
|---|---|
| Space | play / pause (not while typing) |
| ⌘← / ⌘→ | previous / next track |
| ⇧⌘← / ⇧⌘→ | seek −10 / +10 s |
| ⌘↑ / ⌘↓, ⌘⌥↓ | volume up / down, mute |
| ⌘R, ⌘S | repeat mode, shuffle |
| ⌘F, ⌘L | search |
| ⌘[ / ⌘] | back / forward |
| ⌘1 / ⌘2 / ⌘3 | Home / Explore / Library |
| ⌘P | open / close the player page |
| ⌥⌘L / ⌥⌘D | like / dislike the current track |
| ⌘N | new playlist |
| ⌘, | settings |
| ⌃⌘S | toggle sidebar |
| Return | play the focused row / open the focused card |
| ⌫ | remove selected rows (queue, own playlist) |
| Esc | close dropdown / player page / selection |

All shortcuts appear in the app menu (stage 5.2) so they are discoverable.

### 14.4. Accessibility
- Every control has a VoiceOver label; icon buttons also have a tooltip.
- Rows read as "Title, Artist, Album, duration"; the now-playing row adds
  "Now playing"; ratings expose `.isSelected`.
- Shelves are containers with the shelf title as the label; arrows are
  hidden from VoiceOver because the shelf is scrollable by VoiceOver itself.
- Tab order: top bar → sidebar → content → player bar; the player page traps
  focus until it is closed.
- Hover-only controls (row actions, card play buttons) are also in the context
  menu and reachable with the keyboard.

### 14.5. What is remembered between launches
Sidebar collapsed state, last section and stacks, Library section and sort,
chart country, volume, repeat and shuffle, player page open
state; playback position per `resumeOnStart`.

## 15. Where the backlog covers these parts

Parts that had no backlog row when this specification was written, and the
rows that now cover them (added 2026-11-18):

| Part | Backlog row |
|---|---|
| Player page: Lyrics, Related, Comments tabs | 4.8 |
| Explore subpages (New releases, Charts with country, Moods & genres) | 4.2 |
| Search history in the dropdown with delete (`feedback`) | 4.3 (+ `feedback` in 2.4) |
| History page and removal from history | 4.5 (+ `feedback` in 2.4) |
| Artist Subscribe (`subscription/*`) | 2.4 (endpoint), 4.4 (button) |
| Multi-select, selection bar, drag and drop | 4.6 |
| Offline banner and retry on reconnect | 4.7 |
| Podcasts | not planned (decided no, #7) |
| Music video mode (Song/Video toggle, CC, picture-in-picture) | later ([#12](https://github.com/AratKruglik/yt-music-mac/issues/12)) |
| Artwork colour theme (look of the reference) | S7 `album-color-theme` (stage 7); can be pulled into 4.7 |
