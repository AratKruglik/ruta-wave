# Landing Page Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a static, bilingual landing page at `rutawave.kruhlyk.pro/` and deploy it in the same Pages artifact as the unchanged `appcast.xml`.

**Architecture:** Hand-written HTML, CSS and JS live in `landing/`. `Scripts/landing.py` copies them into `site/` and adds the screenshots and a composed `icon.svg`. It fills in the download links from the GitHub releases that `appcast.fetch_releases` returns. The `appcast.yml` build job runs both scripts and also triggers on landing pushes to `develop`.

**Tech Stack:** Python 3 stdlib (`unittest`), plain HTML/CSS/JS, GitHub Actions.

**Spec:** `docs/superpowers/specs/2026-11-28-landing-page-design.md`

## Global Constraints

- `appcast.xml`: same path, and it is produced by the same unchanged `Scripts/appcast.py site/appcast.xml` call.
- No third-party requests from the page: no web fonts, CDNs or analytics. Use the system font stack.
- No YouTube or Google logos. The disclaimer reads "RutaWave is an independent project and is not affiliated with, endorsed or sponsored by Google or YouTube."
- Brand red is `#E8253F → #9E0E24`. Text contrast is ≥ 4.5:1 in both themes, focus is visible, and `prefers-reduced-motion` stops the motion.
- DMG asset name: `RutaWave-<shortVersion>.dmg`, where the tag is `v<shortVersion>`.

## Review Focus

- A stable release that is newer than every beta: no secondary beta link.
- A release whose DMG asset is missing, for example a release still uploading: skipped, not linked.
- No release with a DMG at all: the button links to `https://github.com/AratKruglik/ruta-wave/releases`.
- A version string or URL with HTML-special characters: escaped in the rendered block.
- JS disabled: the English page still works, and the download links are plain `<a href>`.

---

### Task 1: `Scripts/landing.py` with tests

**Files:** Create `Scripts/landing.py` and `Scripts/test_landing.py`.

**Interfaces:**
- `pick_downloads(releases: list[dict]) -> dict` returns `{"primary": {"version", "url", "beta": bool} | None, "secondary": same | None}`.
- `render_downloads(downloads: dict) -> str` returns HTML that replaces each `<!--downloads-->` marker.
- `compose_icon(icon_dir: Path) -> str` returns SVG text.
- `main(argv)` handles `landing.py <site-dir>`.

- [ ] Test `pick_downloads`: stable 0.2.0 plus a newer beta 0.3.0-beta.1 gives primary 0.2.0 and secondary the beta. A stable newer than the beta gives `secondary is None`. Betas only gives a primary beta and no secondary. Drafts and releases without a DMG are ignored. Empty input gives `primary is None`.
- [ ] Test `render_downloads`: the URL appears in the `href`, `<` in a version is escaped, and with `primary None` it links to the releases page.
- [ ] Test `compose_icon`: the output parses as XML and contains four paths.
- [ ] Implement, then run `python3 -m unittest discover -s Scripts -p 'test_*.py'` and see it pass.

### Task 2: `landing/` page

**Files:** Create `landing/index.html`, `landing/style.css` and `landing/main.js`. Add `/site/` to `.gitignore`.

- [ ] Sections as in the spec. `data-i18n` keys on text, plus `data-i18n-alt` and `data-i18n-label` for attributes. `main.js` holds the `uk` dictionary, the theme toggle and the language toggle (both stored in `localStorage`) and a scroll reveal through `IntersectionObserver`.
- [ ] Build locally: `GITHUB_REPOSITORY=AratKruglik/ruta-wave GITHUB_TOKEN=$(gh auth token) python3 Scripts/appcast.py site/appcast.xml && … python3 Scripts/landing.py site`. Serve it with `python3 -m http.server -d site`, then check both themes, both languages, 375 px and 1440 px widths, and keyboard focus.

### Task 3: Workflow

**Files:** Modify `.github/workflows/appcast.yml`.

- [ ] Add a `push` trigger on `develop` with the paths from the spec. `build.if` becomes `github.event_name != 'release'`. Add the step `python3 Scripts/landing.py site` after the appcast step.
- [ ] Check that `site/appcast.xml` from a local build matches `curl https://rutawave.kruhlyk.pro/appcast.xml`.
- [ ] Commit and open a PR to `develop`.
