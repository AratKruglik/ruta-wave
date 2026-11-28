# Landing page at rutawave.kruhlyk.pro

Approved direction: **A, "dark stage"**, with the brand red and the system font, in English and Ukrainian.

## Why

RutaWave needs a home page that explains what the app is and hands out the DMG. Right now that page is the GitHub README. The site already serves the Sparkle feed, so the landing goes next to it.

## Goals

- One static page at `/`. A visitor understands it in one screen and gets a working DMG link.
- The download points at the newest stable release, with the newest beta as a second link if it is newer. While no stable release exists, the beta is the main link.
- Light and dark themes: they follow the system, and a toggle overrides it. Accessible: contrast ≥ 4.5:1, keyboard focus, `prefers-reduced-motion`.
- English and Ukrainian: the browser language picks one, a toggle switches, and the choice is remembered.

## Non-goals

- No framework, bundler, npm, web fonts or analytics. No requests to third parties.
- No release notes page and no blog.

## Anti-goals

- Any deploy that drops `appcast.xml` or changes its content.
- YouTube or Google logos, or a look that imitates them.

## Constraints

- `actions/deploy-pages` replaces the whole site, so the feed and the landing are built into one `site/` artifact by `appcast.yml`.
- The workflow also deploys on pushes to `develop` that touch the landing sources.
- `releases/latest` returns 404 because every release is a pre-release. Download URLs are therefore written into the page at build time from the GitHub releases API.

## Approaches considered

1. **Dark stage (picked).** A near-black background with a red glow, the wordmark from the banner, the hero screenshot in a Mac window, and the icon's rings as a slow background motif. The light theme is warm white with the same red. It continues the banner and the app, which is dark only.
2. Apple-style product page: light, typographic, little colour. Clean, but the brand gets lost.
3. "Chervona Ruta" editorial: serif type and a flower motif. Distinctive, but it risks looking like kitsch.

From `ui-ux-pro-max`: the "feature-rich showcase" structure with the download repeated, the dark style and moderate motion. Its indigo-and-green palette and its Google Fonts were dropped: they are off-brand, and the fonts would add requests to Google. The app's design book uses SF Pro, so the page uses the system font stack.

## Design

- **Sources** live in `landing/`: `index.html` (English text, with a `<!--downloads-->` marker wherever a download block goes), `style.css`, `main.js` (theme, language and the Ukrainian strings).
- **`Scripts/landing.py <site-dir>`** reuses `appcast.fetch_releases` and then:
  - copies `landing/` into the site directory;
  - copies `docs/assets/screenshots/` to `screenshots/` and `docs/assets/banner.png` to `banner.png` (the Open Graph image);
  - composes `icon.svg` from `App/AppIcon.icon` (gradient fill plus the ring and play layers);
  - renders the download block into `index.html`.
- `pick_downloads(releases)` is pure and has unit tests in `Scripts/test_landing.py`. It skips drafts and releases without a `RutaWave-<version>.dmg` asset. With no DMG at all, the button links to the releases page.
- **Sections:**
  1. Header: icon, wordmark, theme and language toggles, GitHub link.
  2. Hero: headline, download block, home screenshot.
  3. Why RutaWave: four cards.
  4. Features: six tiles.
  5. Screenshots: a gallery with captions.
  6. Install: three steps, plus the update channels.
  7. Closing call to action.
  8. Footer: the "not affiliated with Google" disclaimer and "Made in Ukraine".
- **Workflow:** the `build` job runs on `workflow_dispatch` and on `push` to `develop` with paths `landing/**`, `Scripts/landing.py`, `Scripts/appcast.py`, `docs/assets/**`, `App/AppIcon.icon/**` and the workflow file. It runs `appcast.py site/appcast.xml` unchanged, then `landing.py site`.

## Left to the builder

The copy, the exact spacing scale and the motion timing.

## Revision: ideas borrowed from notchalert.propellercrew.com

The user liked how that page lets the product show itself. They picked three of its ideas, plus a mix of screenshots and HTML:

- **One evening with RutaWave.** A scroll-driven story. A sticky Mac window crossfades between six README screenshots (home, search, artist, playlist, player page, explore). A timeline of evening times runs under it. The glow takes each step's artwork colour. This replaces the screenshot gallery.
- **Press it right now.** The menu bar item and the mini player are drawn in HTML. The app's own shortcuts work on the page: Space, ⌘←/⌘→, ⇧⌘←/⇧⌘→, ⌘↑/⌘↓ and ⌥⌘L. They are only handled while the demo is on screen, so ⌘← keeps meaning "back" elsewhere on the page. The keycaps are buttons too. The scene takes its tint from a stand-in cover, as the app does from a real one. ⌘R and ⌘S were left out because browsers reserve them for reload and save.
- **Honesty and details.** A first-person line in "Why", a "What RutaWave does not do" section (from the README, plus "unofficial, can break when the site changes"), and the DMG size next to the version, taken from the release asset.

Not taken: the light beam from the notch, sound (the music is someone else's), and the cookie banner (this site has no analytics).

## Revision: less template, dark only

The user found the icon-card grids generic, and asked for a single dark theme.

- **Dark only.** The theme toggle and the light palette are gone.
- **"Why"** is a short first-person letter: a large headline and prose, with no cards.
- **Features are the app's real menus.** Go, Controls, Window and File, item for item with their shortcuts, as in `App/Shell/AppCommands.swift` and `RutawaveApp.swift`. Whatever the menus do not cover is a plain definition list with hairlines.
- **The tour has no invented evening times.** The bar under the window names the screens and jumps to each one.
- **"What it doesn't do" and "Install"** are typographic lists, not cards.
