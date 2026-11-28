#!/usr/bin/env python3
"""Builds Sparkle's appcast.xml from the repository's published GitHub releases.

The feed is rebuilt from scratch every time, so an edited release changes its notes
and a deleted one drops out. Releases without an `appcast-item.json` asset (drafts,
builds made before Sparkle, forks without the signing key) are skipped.

    GITHUB_REPOSITORY=owner/repo GITHUB_TOKEN=… Scripts/appcast.py site/appcast.xml
"""

import json
import os
import re
import sys
import urllib.request
from email.utils import format_datetime
from datetime import datetime
from xml.sax.saxutils import escape, quoteattr

API = "https://api.github.com"
ITEM_ASSET = "appcast-item.json"
GITHUB_ONLY = re.compile(r"<!--\s*github-only\s*-->.*?<!--\s*/github-only\s*-->", re.S)
COMMENT = re.compile(r"<!--.*?-->", re.S)
PLACEHOLDER_ITEM = re.compile(r"^\s*[-*]\s*(…|\.\.\.)?\s*$")
VERSION = re.compile(r"^[0-9]+$")
SHORT_VERSION = re.compile(r"^[0-9]+(\.[0-9]+)*(-[0-9A-Za-z.]+)?$")
SIGNATURE = re.compile(r"^[A-Za-z0-9+/]+={0,2}$")


def clean_notes(markdown):
    """Drops the GitHub-only blocks, comments and the template sections nobody filled in."""
    text = COMMENT.sub("", GITHUB_ONLY.sub("", markdown or "")).replace("\r\n", "\n")
    sections, current = [], []
    for line in text.split("\n"):
        if line.startswith("## ") and current:
            sections.append(current)
            current = []
        current.append(line)
    sections.append(current)

    def is_empty(section):
        body = section[1:] if section and section[0].startswith("## ") else section
        return all(not line.strip() or PLACEHOLDER_ITEM.match(line) for line in body)

    return "\n".join(line for section in sections if not is_empty(section) for line in section).strip()


def valid_item(meta, tag):
    """The asset comes from a release anyone with write access can edit, so every field is checked."""
    return (
        isinstance(meta, dict)
        and VERSION.match(str(meta.get("version", "")))
        and SHORT_VERSION.match(str(meta.get("shortVersion", "")))
        and tag == "v" + str(meta["shortVersion"])
        and SIGNATURE.match(str(meta.get("edSignature", "")))
        and isinstance(meta.get("length"), int) and meta["length"] > 0
        and SHORT_VERSION.match(str(meta.get("minimumSystemVersion", "")))
    )


def cdata(html):
    return "<![CDATA[" + html.replace("]]>", "]]]]><![CDATA[>") + "]]>"


def build_item(release, meta, zip_url, notes_html):
    published = datetime.fromisoformat(release["published_at"].replace("Z", "+00:00"))
    lines = [
        "    <item>",
        f"      <title>{escape('RutaWave ' + meta['shortVersion'])}</title>",
        f"      <pubDate>{format_datetime(published)}</pubDate>",
        f"      <sparkle:version>{meta['version']}</sparkle:version>",
        f"      <sparkle:shortVersionString>{escape(meta['shortVersion'])}</sparkle:shortVersionString>",
        f"      <sparkle:minimumSystemVersion>{escape(meta['minimumSystemVersion'])}</sparkle:minimumSystemVersion>",
    ]
    if release.get("prerelease"):
        lines.append("      <sparkle:channel>beta</sparkle:channel>")
    if notes_html:
        lines.append(f"      <description>{cdata(notes_html)}</description>")
    lines.append(
        f"      <enclosure url={quoteattr(zip_url)} length=\"{meta['length']}\" type=\"application/octet-stream\""
        f" sparkle:edSignature={quoteattr(meta['edSignature'])}/>"
    )
    lines.append("    </item>")
    return "\n".join(lines)


def build_feed(releases, load_json, render_markdown, log=lambda message: None):
    """`load_json(url)` and `render_markdown(text)` are the network edges, injected so tests stay offline."""
    items = []
    published = [r for r in releases if not r.get("draft") and r.get("published_at")]
    for release in sorted(published, key=lambda r: r["published_at"], reverse=True):
        assets = {asset["name"]: asset["browser_download_url"] for asset in release.get("assets", [])}
        if ITEM_ASSET not in assets:
            continue
        tag = release.get("tag_name", "")
        meta = load_json(assets[ITEM_ASSET])
        zip_name = f"RutaWave-{meta.get('shortVersion')}.zip" if isinstance(meta, dict) else None
        if not valid_item(meta, tag) or zip_name not in assets:
            log(f"skipping {tag}: invalid {ITEM_ASSET} or missing {zip_name}")
            continue
        notes = clean_notes(release.get("body"))
        items.append(build_item(release, meta, assets[zip_name], render_markdown(notes) if notes else ""))
    return "\n".join([
        '<?xml version="1.0" encoding="utf-8"?>',
        '<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">',
        "  <channel>",
        "    <title>RutaWave</title>",
        *items,
        "  </channel>",
        "</rss>",
        "",
    ])


def request(url, token=None, data=None, accept="application/vnd.github+json"):
    headers = {"Accept": accept, "User-Agent": "rutawave-appcast", "X-GitHub-Api-Version": "2022-11-28"}
    if token:
        headers["Authorization"] = f"Bearer {token}"
    body = json.dumps(data).encode() if data is not None else None
    with urllib.request.urlopen(urllib.request.Request(url, data=body, headers=headers), timeout=30) as response:
        return response.read()


def fetch_releases(repo, token):
    releases, page = [], 1
    while True:
        batch = json.loads(request(f"{API}/repos/{repo}/releases?per_page=100&page={page}", token))
        releases.extend(batch)
        if len(batch) < 100:
            return releases
        page += 1


def main(argv):
    if len(argv) != 2:
        sys.exit("usage: appcast.py <output.xml>")
    repo, token = os.environ["GITHUB_REPOSITORY"], os.environ.get("GITHUB_TOKEN")

    def load_json(url):
        # A release download redirects to storage that rejects an Authorization header, so none is sent.
        try:
            return json.loads(request(url, accept="application/octet-stream"))
        except (OSError, ValueError) as error:
            print(f"cannot read {url}: {error}", file=sys.stderr)
            return None

    def render_markdown(text):
        return request(f"{API}/markdown", token, {"text": text, "mode": "gfm", "context": repo}).decode()

    feed = build_feed(fetch_releases(repo, token), load_json, render_markdown, log=lambda m: print(m, file=sys.stderr))
    os.makedirs(os.path.dirname(os.path.abspath(argv[1])), exist_ok=True)
    with open(argv[1], "w", encoding="utf-8") as file:
        file.write(feed)
    print(f"{argv[1]}: {feed.count('<item>')} item(s)")


if __name__ == "__main__":
    main(sys.argv)
