#!/usr/bin/env python3
"""Self-test of scrub-fixture.py. Run: python3 -I Scripts/test_scrub_fixture.py

It lives outside Tests/.../Fixtures because its raw inputs would fail the privacy guard.
"""
import argparse
import importlib.util
import os
import sys
import unittest

sys.dont_write_bytecode = True

spec = importlib.util.spec_from_file_location("scrub", os.path.join(os.path.dirname(os.path.abspath(__file__)), "scrub-fixture.py"))
scrub = importlib.util.module_from_spec(spec)
spec.loader.exec_module(scrub)


def scrubber(items=2):
    return scrub.Scrubber(argparse.Namespace(sections=3, items=items, one_per_kind=False, distinct_trend=False, mask=[], mask_id=[]))


def service(icon, token):
    return {"menuServiceItemRenderer": {"icon": {"iconType": icon}, "serviceEndpoint": {"feedbackEndpoint": {"feedbackToken": token}}}}


class ScrubFixtureTests(unittest.TestCase):
    def test_history_menu_keeps_only_the_removal_item_with_a_placeholder_token(self):
        row = {"menu": {"menuRenderer": {"items": [service("FAVORITE", "real-like"), service("REMOVE_FROM_HISTORY", "real-remove")]}}}
        out = scrubber().clean(row)
        items = out["menu"]["menuRenderer"]["items"]
        self.assertEqual(len(items), 1)
        self.assertEqual(items[0]["menuServiceItemRenderer"]["icon"]["iconType"], "REMOVE_FROM_HISTORY")
        self.assertEqual(items[0]["menuServiceItemRenderer"]["serviceEndpoint"]["feedbackEndpoint"]["feedbackToken"], "PLACEHOLDER_FEEDBACK_1")

    def test_menu_without_a_removal_item_is_dropped(self):
        row = {"menu": {"menuRenderer": {"items": [service("FAVORITE", "real-like")]}}}
        self.assertEqual(scrubber().clean(row), {})

    def test_email_is_replaced_before_the_handle_rule(self):
        self.assertEqual(scrubber().clean("write to jane.doe@example.com now"), "write to placeholder email now")

    def test_trailing_continuation_and_automix_survive_item_trimming(self):
        rows = [{"musicResponsiveListItemRenderer": {"n": n}} for n in range(5)]
        for trailing in ("continuationItemRenderer", "automixPreviewVideoRenderer"):
            for key in ("contents", "continuationItems"):
                out = scrubber().trim({key: rows + [{trailing: {}}]})
                self.assertEqual(len(out[key]), 3)
                self.assertIn(trailing, out[key][-1])


if __name__ == "__main__":
    unittest.main()
