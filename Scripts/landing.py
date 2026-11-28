#!/usr/bin/env python3
"""Builds the landing page into the Pages site, next to the appcast.xml that appcast.py wrote.

Run it after appcast.py: it adds files to the site directory and never removes any.
Download links are fixed at build time, because every release so far is a pre-release
and GitHub's releases/latest URL skips those.

    GITHUB_REPOSITORY=owner/repo GITHUB_TOKEN=… Scripts/landing.py site
"""

import json
import os
import re
import shutil
import sys
from html import escape
from pathlib import Path

import appcast

ROOT = Path(__file__).resolve().parent.parent
MARKER = "<!--downloads-->"
RELEASES_PAGE = "https://github.com/AratKruglik/ruta-wave/releases"
SVG_BODY = re.compile(r"<svg[^>]*>(.*)</svg>", re.S)
DOWNLOAD_ICON = ('<svg aria-hidden="true" viewBox="0 0 24 24" width="20" height="20"><path d="M12 4v11m0 0-4.5-4.5M12 15l4.5-4.5'
                 'M5 19h14" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"/></svg>')


def pick_downloads(releases):
    """Stable vs beta follows the release's pre-release flag, as the appcast's channels do; newest by publish date."""
    published = [r for r in releases if not r.get("draft") and r.get("published_at")]
    newest_first = sorted(published, key=lambda r: r["published_at"], reverse=True)

    def newest(beta):
        for release in newest_first:
            if bool(release.get("prerelease")) != beta:
                continue
            version = release.get("tag_name", "").removeprefix("v")
            dmg = next((a for a in release.get("assets", []) if a["name"] == f"RutaWave-{version}.dmg"), None)
            if dmg:
                return {"version": version, "url": dmg["browser_download_url"], "size": dmg.get("size"), "beta": beta,
                        "published_at": release["published_at"]}
        return None

    stable, beta = newest(False), newest(True)
    if stable and beta and beta["published_at"] < stable["published_at"]:
        beta = None
    primary, secondary = (stable, beta) if stable else (beta, None)
    strip = lambda d: d and {k: d[k] for k in ("version", "url", "size", "beta")}
    return {"primary": strip(primary), "secondary": strip(secondary)}


def render_downloads(downloads):
    primary, secondary = downloads["primary"], downloads["secondary"]
    href = escape(primary["url"] if primary else RELEASES_PAGE)
    lines = [
        '<div class="download">',
        f'  <a class="button button-primary" href="{href}">{DOWNLOAD_ICON}<span data-i18n="download.button">Download for Mac</span></a>',
    ]
    if primary:
        channel = '<span data-i18n="download.beta">beta</span>' if primary["beta"] else '<span data-i18n="download.stable">stable</span>'
        size = primary.get("size")
        # main.js reformats data-bytes for the page language ("6,2 МБ").
        size_html = f'<span class="size" data-bytes="{size}">{size / 1e6:.1f} MB</span> · ' if isinstance(size, int) and size > 0 else ""
        lines.append(f'  <p class="download-meta"><span class="version">{escape(primary["version"])}</span> · {channel} · {size_html}'
                     '<span data-i18n="download.requirements">macOS 14+ · Apple Silicon</span></p>')
    if secondary:
        lines.append(f'  <p class="download-alt"><a href="{escape(secondary["url"])}"><span data-i18n="download.tryBeta">Or try the beta</span> '
                     f'<span class="version">{escape(secondary["version"])}</span></a></p>')
    lines.append("</div>")
    return "\n".join(lines)


def compose_icon(icon_dir, rings_only=False):
    """Flattens the Icon Composer bundle into one SVG; its groups and layers are listed top-first.

    `rings_only` drops the top group (the play glyph) and the fill, and tints the strokes red, for the hero backdrop.
    """
    spec = json.loads((icon_dir / "icon.json").read_text(encoding="utf-8"))

    def hex_color(srgb):
        return "#" + "".join(f"{round(float(c) * 255):02x}" for c in srgb.removeprefix("srgb:").split(",")[:3])

    top, bottom = (hex_color(c) for c in spec["fill"]["linear-gradient"])
    groups = spec["groups"][1:] if rings_only else spec["groups"]
    layers = [layer for group in reversed(groups) for layer in reversed(group["layers"])]
    bodies = [SVG_BODY.search((icon_dir / "Assets" / layer["image-name"]).read_text(encoding="utf-8")).group(1) for layer in layers]
    if rings_only:
        return f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024">{"".join(bodies).replace("#fff", top)}</svg>\n'
    return "".join([
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024">',
        f'<defs><linearGradient id="fill" x2="0" y2="1"><stop offset="0" stop-color="{top}"/><stop offset="1" stop-color="{bottom}"/></linearGradient>',
        '<clipPath id="shape"><rect width="1024" height="1024" rx="228"/></clipPath></defs>',
        '<g clip-path="url(#shape)"><rect width="1024" height="1024" fill="url(#fill)"/>',
        *bodies,
        "</g></svg>\n",
    ])


def build_site(site, releases, root=ROOT):
    source = root / "landing"
    if (source / "appcast.xml").exists():
        sys.exit("landing/ must not contain appcast.xml: it would replace the Sparkle feed")
    shutil.copytree(source, site, dirs_exist_ok=True)
    shutil.copytree(root / "docs/assets/screenshots", site / "screenshots", dirs_exist_ok=True)
    shutil.copy2(root / "docs/assets/banner.png", site / "banner.png")
    (site / "icon.svg").write_text(compose_icon(root / "App/AppIcon.icon"), encoding="utf-8")
    (site / "rings.svg").write_text(compose_icon(root / "App/AppIcon.icon", rings_only=True), encoding="utf-8")

    index = site / "index.html"
    page = index.read_text(encoding="utf-8")
    if MARKER not in page:
        sys.exit(f"landing/index.html has no {MARKER} marker")
    index.write_text(page.replace(MARKER, render_downloads(pick_downloads(releases))), encoding="utf-8")


def main(argv):
    if len(argv) != 2:
        sys.exit("usage: landing.py <site-dir>")
    site = Path(argv[1])
    releases = appcast.fetch_releases(os.environ["GITHUB_REPOSITORY"], os.environ.get("GITHUB_TOKEN"))
    build_site(site, releases)
    print(f"{site / 'index.html'}: {pick_downloads(releases)}")


if __name__ == "__main__":
    main(sys.argv)
