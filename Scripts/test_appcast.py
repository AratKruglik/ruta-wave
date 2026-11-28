import unittest
import xml.etree.ElementTree as ElementTree
from pathlib import Path

import appcast

SPARKLE = "{http://www.andymatuschak.org/xml-namespaces/sparkle}"
SIGNATURE = "U53vUEriZ1VOV5GdncL+SRV/H8DDwOArFJiALVpokGtUb/DrhTPB5IXfD0akTL9W3KSIDxda9Rcrb+6U4lt9Dg=="

NOTES = """## What's new
- Update channels in Settings
## Fixed
- …
## Known issues
-
<!-- github-only -->
Run `xattr -dr com.apple.quarantine /Applications/RutaWave.app`
<!-- /github-only -->"""


def release(tag, *, prerelease=False, draft=False, published="2026-12-01T10:00:00Z", item=True, body=NOTES):
    short = tag.removeprefix("v")
    assets = [{"name": f"RutaWave-{short}.dmg", "browser_download_url": f"https://dl/{short}.dmg"},
              {"name": f"RutaWave-{short}.zip", "browser_download_url": f"https://dl/{short}.zip"}]
    if item:
        assets.append({"name": "appcast-item.json", "browser_download_url": f"https://dl/{short}.json"})
    return {"tag_name": tag, "prerelease": prerelease, "draft": draft,
            "published_at": None if draft else published, "body": body, "assets": assets}


def meta(short, version):
    return {"version": version, "shortVersion": short, "edSignature": SIGNATURE,
            "length": 5631253, "minimumSystemVersion": "14.0"}


METAS = {
    "https://dl/0.2.0.json": meta("0.2.0", "20"),
    "https://dl/0.3.0-beta.1.json": meta("0.3.0-beta.1", "21"),
    "https://dl/0.3.0-beta.2.json": meta("0.3.0-beta.2", "22"),
    "https://dl/0.2.1.json": meta("0.9.9", "23"),
}


class AppcastTests(unittest.TestCase):
    def feed(self, releases):
        rendered = []
        xml = appcast.build_feed(releases, METAS.get, lambda text: rendered.append(text) or f"<p>{text}</p>")
        return ElementTree.fromstring(xml), rendered

    def test_stable_has_no_channel_and_beta_has_beta(self):
        root, _ = self.feed([release("v0.2.0"), release("v0.3.0-beta.1", prerelease=True, published="2026-12-02T10:00:00Z")])
        items = root.findall("channel/item")
        self.assertEqual([i.findtext(SPARKLE + "version") for i in items], ["21", "20"])
        self.assertEqual(items[0].findtext(SPARKLE + "channel"), "beta")
        self.assertIsNone(items[1].find(SPARKLE + "channel"))

    def test_enclosure_points_at_the_zip_with_signature_and_length(self):
        root, _ = self.feed([release("v0.2.0")])
        enclosure = root.find("channel/item/enclosure")
        self.assertEqual(enclosure.get("url"), "https://dl/0.2.0.zip")
        self.assertEqual(enclosure.get("length"), "5631253")
        self.assertEqual(enclosure.get(SPARKLE + "edSignature"), SIGNATURE)
        self.assertEqual(root.findtext("channel/item/" + SPARKLE + "minimumSystemVersion"), "14.0")

    def test_drafts_and_releases_without_an_item_are_skipped(self):
        root, _ = self.feed([release("v0.3.0-beta.2", prerelease=True, draft=True), release("v0.1.0-beta.5", item=False)])
        self.assertEqual(root.findall("channel/item"), [])

    def test_an_item_whose_version_does_not_match_its_tag_is_skipped(self):
        skipped = []
        xml = appcast.build_feed([release("v0.2.1")], METAS.get, str, log=skipped.append)
        self.assertNotIn("<item>", xml)
        self.assertEqual(len(skipped), 1)

    def test_unreadable_or_tampered_items_are_skipped(self):
        bad = dict(meta("0.2.0", "20"), edSignature='x" onload="')
        for loaded in (None, bad, dict(meta("0.2.0", "20"), length="5")):
            xml = appcast.build_feed([release("v0.2.0")], lambda url, loaded=loaded: loaded, str)
            self.assertNotIn("<item>", xml)

    def test_notes_drop_github_only_blocks_and_empty_sections(self):
        _, rendered = self.feed([release("v0.2.0")])
        self.assertEqual(rendered, ["## What's new\n- Update channels in Settings"])

    def test_the_untouched_template_leaves_no_notes(self):
        with open(Path(__file__).parent.parent / ".github/release-notes-template.md", encoding="utf-8") as file:
            self.assertEqual(appcast.clean_notes(file.read()), "")

    def test_empty_notes_leave_no_description(self):
        root, rendered = self.feed([release("v0.2.0", body="## Fixed\n- …\n")])
        self.assertEqual(rendered, [])
        self.assertIsNone(root.find("channel/item/description"))

    def test_cdata_terminator_in_notes_is_split(self):
        xml = appcast.build_feed([release("v0.2.0", body="a ]]> b")], METAS.get, lambda text: text)
        description = ElementTree.fromstring(xml).findtext("channel/item/description")
        self.assertEqual(description, "a ]]> b")


if __name__ == "__main__":
    unittest.main()
