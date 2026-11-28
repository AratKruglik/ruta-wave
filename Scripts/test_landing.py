import tempfile
import unittest
import xml.etree.ElementTree as ElementTree
from pathlib import Path

import landing

ROOT = Path(__file__).parent.parent


def release(tag, *, prerelease=False, draft=False, published="2026-12-01T10:00:00Z", dmg=True):
    short = tag.removeprefix("v")
    assets = [{"name": f"RutaWave-{short}.zip", "browser_download_url": f"https://dl/{short}.zip"}]
    if dmg:
        assets.append({"name": f"RutaWave-{short}.dmg", "browser_download_url": f"https://dl/{short}.dmg"})
    return {"tag_name": tag, "prerelease": prerelease, "draft": draft,
            "published_at": None if draft else published, "assets": assets}


STABLE = release("v0.2.0", published="2026-12-01T10:00:00Z")
OLD_BETA = release("v0.2.0-beta.3", prerelease=True, published="2026-11-30T10:00:00Z")
NEW_BETA = release("v0.3.0-beta.1", prerelease=True, published="2026-12-02T10:00:00Z")


class PickDownloadsTests(unittest.TestCase):
    def test_stable_is_primary_and_a_beta_published_later_is_secondary(self):
        picked = landing.pick_downloads([OLD_BETA, STABLE, NEW_BETA])
        self.assertEqual(picked["primary"], {"version": "0.2.0", "url": "https://dl/0.2.0.dmg", "beta": False})
        self.assertEqual(picked["secondary"], {"version": "0.3.0-beta.1", "url": "https://dl/0.3.0-beta.1.dmg", "beta": True})

    def test_a_beta_published_before_the_stable_is_not_offered(self):
        picked = landing.pick_downloads([OLD_BETA, STABLE])
        self.assertEqual(picked["primary"]["version"], "0.2.0")
        self.assertIsNone(picked["secondary"])

    def test_without_a_stable_release_the_newest_beta_is_primary(self):
        picked = landing.pick_downloads([OLD_BETA, NEW_BETA])
        self.assertEqual(picked["primary"]["version"], "0.3.0-beta.1")
        self.assertTrue(picked["primary"]["beta"])
        self.assertIsNone(picked["secondary"])

    def test_drafts_and_releases_without_a_dmg_are_ignored(self):
        picked = landing.pick_downloads([
            OLD_BETA,
            release("v0.3.0-beta.2", prerelease=True, draft=True),
            release("v0.3.0", published="2026-12-03T10:00:00Z", dmg=False),
        ])
        self.assertEqual(picked["primary"]["version"], "0.2.0-beta.3")

    def test_no_releases_leave_nothing_to_offer(self):
        self.assertEqual(landing.pick_downloads([]), {"primary": None, "secondary": None})


class RenderTests(unittest.TestCase):
    def test_links_point_at_the_dmgs(self):
        html = landing.render_downloads(landing.pick_downloads([STABLE, NEW_BETA]))
        self.assertIn('href="https://dl/0.2.0.dmg"', html)
        self.assertIn('href="https://dl/0.3.0-beta.1.dmg"', html)

    def test_release_values_are_escaped(self):
        html = landing.render_downloads({"primary": {"version": "1<b>", "url": 'https://x/"a', "beta": False}, "secondary": None})
        self.assertIn("1&lt;b&gt;", html)
        self.assertIn('href="https://x/&quot;a"', html)

    def test_without_a_release_the_button_opens_the_releases_page(self):
        html = landing.render_downloads({"primary": None, "secondary": None})
        self.assertIn(f'href="{landing.RELEASES_PAGE}"', html)

    def test_icon_stacks_the_rings_under_the_play_glyph(self):
        svg = landing.compose_icon(ROOT / "App/AppIcon.icon")
        paths = ElementTree.fromstring(svg).findall(".//{http://www.w3.org/2000/svg}path")
        self.assertEqual(len(paths), 4)
        self.assertEqual(paths[-1].get("fill"), "#fff")

    def test_backdrop_rings_drop_the_play_glyph(self):
        svg = landing.compose_icon(ROOT / "App/AppIcon.icon", rings_only=True)
        paths = ElementTree.fromstring(svg).findall(".//{http://www.w3.org/2000/svg}path")
        self.assertEqual(len(paths), 3)
        self.assertNotIn("#fff", svg)


class BuildSiteTests(unittest.TestCase):
    def test_the_feed_survives_and_every_download_marker_is_filled(self):
        with tempfile.TemporaryDirectory() as directory:
            site = Path(directory)
            feed = b'<?xml version="1.0"?><rss/>\n'
            (site / "appcast.xml").write_bytes(feed)
            landing.build_site(site, [STABLE])
            self.assertEqual((site / "appcast.xml").read_bytes(), feed)
            index = (site / "index.html").read_text(encoding="utf-8")
            self.assertNotIn(landing.MARKER, index)
            self.assertIn('href="https://dl/0.2.0.dmg"', index)
            self.assertTrue((site / "icon.svg").exists())
            self.assertTrue((site / "rings.svg").exists())
            self.assertTrue((site / "screenshots/home.jpg").exists())


if __name__ == "__main__":
    unittest.main()
