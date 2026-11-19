#!/usr/bin/env python3
"""Scrub and trim a raw InnerTube capture into a committable test fixture.

Usage: scrub-fixture.py RAW.json OUT.json [--sections N] [--items N]
                                          [--one-per-kind] [--distinct-trend] [--charts] [--mask NAME]... [--mask-id ID]...

Standard library only. The raw capture must never be committed; only the output.
It deletes privacy and tracking keys, replaces continuation and feedback tokens,
masks third-party profile data and trims lists. Read the result by eye afterwards.
"""
import argparse
import json
import re
import sys

DROP_KEYS = {
    "responseContext", "visitorData", "VISITOR_DATA", "trackingParams", "clickTrackingParams",
    "serviceTrackingParams", "loggingContext", "accessibility", "accessibilityData",
    "accessibilityPlayButtonData", "maxAgeStoreSeconds", "frameworkUpdates",
}
TOKEN_KEYS = {"continuation", "token", "feedbackToken"}
SECTION_KEYS = {
    "musicCarouselShelfRenderer", "gridRenderer", "musicShelfRenderer", "itemSectionRenderer",
    "musicCardShelfRenderer", "musicTastebuilderShelfRenderer", "musicDescriptionShelfRenderer",
}
# A fixed subset, so the capturer's own (IP based) country does not leak into the fixture.
KEEP_COUNTRIES = {"ZZ", "AR", "DE"}
EMAIL = re.compile(r"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}")
HANDLE = re.compile(r"@[A-Za-z0-9._-]+")
# Rows that end a list and must survive trimming: the paging token and the automix preview.
TRAILING_KEYS = {"continuationItemRenderer", "automixPreviewVideoRenderer"}


class Scrubber:
    def __init__(self, args):
        self.args = args
        self.counter = {}

    def placeholder(self, key):
        kind = "FEEDBACK" if key == "feedbackToken" else "CONTINUATION"
        self.counter[kind] = self.counter.get(kind, 0) + 1
        return f"PLACEHOLDER_{kind}_{self.counter[kind]}"

    def clean(self, node, parent_key=None):
        if isinstance(node, dict):
            out = {}
            for key, value in node.items():
                if key in DROP_KEYS or key.startswith("accessibility"):
                    continue
                if key == "menu" and "musicMultiSelectMenuRenderer" not in json.dumps(value)[:200]:
                    removal = self.removal_menu(value)
                    if removal:
                        out[key] = self.clean(removal, key)
                    continue
                if key in TOKEN_KEYS and isinstance(value, str):
                    out[key] = self.placeholder(key)
                else:
                    out[key] = self.clean(value, key)
            return out
        if isinstance(node, list):
            return [self.clean(item, parent_key) for item in node]
        if isinstance(node, str):
            for name in self.args.mask:
                node = node.replace(name, "Placeholder Name")
            for browse_id in self.args.mask_id:
                node = node.replace(browse_id, "placeholder0000000000000000")
            return HANDLE.sub("@placeholder", EMAIL.sub("placeholder email", node))
        return node

    @staticmethod
    def removal_menu(menu):
        """Only the "remove from history" item is kept: it carries the token the 2.4 mutation needs."""
        items = menu.get("menuRenderer", {}).get("items", []) if isinstance(menu, dict) else []
        kept = [i for i in items if i.get("menuServiceItemRenderer", {}).get("icon", {}).get("iconType") == "REMOVE_FROM_HISTORY"]
        return {"menuRenderer": {"items": kept}} if kept else None

    def mask_profile_items(self, node):
        if isinstance(node, dict):
            if self.kind(node) == ("MUSIC_PAGE_TYPE_USER_CHANNEL", None):
                return self.blank_profile(node)
            return {k: self.mask_profile_items(v) for k, v in node.items()}
        if isinstance(node, list):
            return [self.mask_profile_items(v) for v in node]
        return node

    def mask_name_links(self, node):
        if isinstance(node, dict):
            endpoint = node.get("navigationEndpoint", {}).get("browseEndpoint")
            if node.get("text") == "Placeholder Name" and isinstance(endpoint, dict) and "browseId" in endpoint:
                endpoint["browseId"] = "UCplaceholder0000000000000"
            for value in node.values():
                self.mask_name_links(value)
        elif isinstance(node, list):
            for value in node:
                self.mask_name_links(value)
        return node

    def blank_profile(self, node):
        def walk(value, key=None):
            if isinstance(value, dict):
                return {k: walk(v, k) for k, v in value.items()}
            if isinstance(value, list):
                return [walk(v, key) for v in value]
            if isinstance(value, str):
                if key == "text":
                    return "Placeholder Profile"
                if key == "browseId":
                    return "UCplaceholder0000000000000"
                if key == "url":
                    return "https://yt3.googleusercontent.com/placeholder=w60-h60"
            return value
        return walk(node)

    def kind(self, item):
        body = item.get("musicResponsiveListItemRenderer") or item.get("musicTwoRowItemRenderer") or {}

        def dig(node, *path):
            for step in path:
                node = node.get(step) if isinstance(node, dict) else node[step] if isinstance(node, list) and len(node) > step else None
                if node is None:
                    return None
            return node

        browse = dig(body, "navigationEndpoint", "browseEndpoint", "browseEndpointContextSupportedConfigs",
                     "browseEndpointContextMusicConfig", "pageType")
        if browse:
            return (browse, None)
        watch = (dig(body, "flexColumns", 0, "musicResponsiveListItemFlexColumnRenderer", "text", "runs", 0,
                     "navigationEndpoint", "watchEndpoint")
                 or dig(body, "overlay", "musicItemThumbnailOverlayRenderer", "content", "musicPlayButtonRenderer",
                        "playNavigationEndpoint", "watchEndpoint") or {})
        return (None, dig(watch, "watchEndpointMusicSupportedConfigs", "watchEndpointMusicConfig", "musicVideoType"))

    def trend(self, item):
        match = re.search(r'"iconType": "(ARROW_[A-Z_]+)"', json.dumps(item))
        return match.group(1) if match else None

    def trim_list(self, items, key, parent):
        if not items or not all(isinstance(i, dict) for i in items):
            return items
        if key == "thumbnails":
            return [items[0], items[-1]] if len(items) > 2 else items
        first = next(iter(items[0]), "")
        if first in SECTION_KEYS:
            if self.args.one_per_kind and any("itemSectionRenderer" in i for i in items):
                return self.one_per_kind(items)
            return items[: self.args.sections]
        if key not in ("contents", "items", "continuationItems"):
            return items
        kept = items[: self.args.items]
        if items[-1] not in kept and next(iter(items[-1]), "") in TRAILING_KEYS:
            kept.append(items[-1])
        if self.args.distinct_trend:
            seen = {self.trend(i) for i in kept}
            for item in items[self.args.items:]:
                if self.trend(item) not in seen:
                    seen.add(self.trend(item))
                    kept.append(item)
        return kept

    def one_per_kind(self, items):
        seen, kept = set(), []
        for section in items:
            if "itemSectionRenderer" not in section:
                kept.append(section)
                continue
            inner = section["itemSectionRenderer"].get("contents", [])
            signature = self.kind(inner[0]) if inner else None
            if signature is None or "showingResultsForRenderer" in json.dumps(inner[:1]) or signature not in seen:
                seen.add(signature)
                kept.append(section)
        return kept

    def trim(self, node, key=None, parent=None):
        if isinstance(node, dict):
            return {k: self.trim(self.trim_list(v, k, node) if isinstance(v, list) else v, k, node) for k, v in node.items()}
        if isinstance(node, list):
            return [self.trim(v, key, parent) for v in node]
        return node

    def trim_charts(self, raw_mutations, document):
        selected = {}
        for mutation in raw_mutations:
            choice = mutation.get("payload", {}).get("musicFormBooleanChoice")
            if choice:
                selected[choice["id"]] = choice
        codes = {key: choice["opaqueToken"] for key, choice in selected.items()}
        def walk(node):
            if isinstance(node, dict):
                if "musicMultiSelectMenuRenderer" in node:
                    options = [o for o in node["musicMultiSelectMenuRenderer"]["options"] if "musicMultiSelectMenuItemRenderer" in o]
                    chosen = [o for o in options if selected.get(o["musicMultiSelectMenuItemRenderer"]["formItemEntityKey"], {}).get("selected")]
                    fixed = [o for o in options if o not in chosen and codes.get(o["musicMultiSelectMenuItemRenderer"]["formItemEntityKey"]) in KEEP_COUNTRIES]
                    node["musicMultiSelectMenuRenderer"]["options"] = fixed + chosen
                    self.kept_options = {o["musicMultiSelectMenuItemRenderer"]["formItemEntityKey"] for o in node["musicMultiSelectMenuRenderer"]["options"]}
                for v in node.values():
                    walk(v)
            elif isinstance(node, list):
                for v in node:
                    walk(v)
        walk(document)
        document["frameworkUpdates"] = {"entityBatchUpdate": {"mutations": [
            {"payload": {"musicFormBooleanChoice": {
                "id": c["id"], "selected": c["selected"], "opaqueToken": c["opaqueToken"]}}}
            for c in selected.values() if c["id"] in self.kept_options]}}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("raw")
    parser.add_argument("out")
    parser.add_argument("--sections", type=int, default=3)
    parser.add_argument("--items", type=int, default=3)
    parser.add_argument("--one-per-kind", action="store_true")
    parser.add_argument("--distinct-trend", action="store_true")
    parser.add_argument("--charts", action="store_true")
    parser.add_argument("--mask", action="append", default=[], help="private individual's name to replace")
    parser.add_argument("--mask-id", action="append", default=[], help="ID (without VL/MPSP prefix) to replace")
    args = parser.parse_args()
    raw = json.load(open(args.raw))
    mutations = raw.get("frameworkUpdates", {}).get("entityBatchUpdate", {}).get("mutations", [])
    scrubber = Scrubber(args)
    document = scrubber.mask_name_links(scrubber.mask_profile_items(scrubber.trim(scrubber.clean(raw))))
    if args.charts:
        scrubber.trim_charts(mutations, document)
    json.dump(document, open(args.out, "w"), indent=1, ensure_ascii=False, sort_keys=True)
    open(args.out, "a").write("\n")


if __name__ == "__main__":
    sys.exit(main())
