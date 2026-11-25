#!/usr/bin/env python3
"""Generates App/AppIcon.icon (Icon Composer format) from the geometry in
docs/superpowers/specs/2026-11-25-app-icon-design.md.

    python3 Scripts/generate-app-icon.py          write the icon
    python3 Scripts/generate-app-icon.py --check  verify the committed icon
"""
import json
import math
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import NamedTuple

ICON_DIR = Path(__file__).resolve().parent.parent / "App" / "AppIcon.icon"
LAYERS = ["play", "ring-inner", "ring-middle", "ring-outer"]
CENTER = 512.0
# The spec's numbers come from a mockup whose icon shape spanned 824 of 1024; an .icon layer fills the whole shape.
SCALE = 1024 / 824
TOP = "srgb:0.90980,0.14510,0.24706,1.00000"  # #E8253F
BOTTOM = "srgb:0.61961,0.05490,0.14118,1.00000"  # #9E0E24


class Ring(NamedTuple):
    name: str
    R: float
    a: float
    m: float
    stroke: float
    opacity: float


RINGS = [
    Ring("ring-outer", 300 * SCALE, 0.16, 0.0, 36 * SCALE, 0.70),
    Ring("ring-middle", 225 * SCALE, 0.20, 0.5, 40 * SCALE, 0.85),
    Ring("ring-inner", 150 * SCALE, 0.22, 1.0, 44 * SCALE, 1.00),
]


def ring_points(R: float, a: float, m: float, n: int = 720) -> list[tuple[float, float]]:
    """r(φ) = R·(1 + a·((1−m)·cos 5(φ+π/2) + m·cos 3φ)): 5 petals up blended into 3 lobes pointing right."""
    points = []
    for i in range(n + 1):
        phi = 2 * math.pi * i / n
        r = R * (1 + a * ((1 - m) * math.cos(5 * (phi + math.pi / 2)) + m * math.cos(3 * phi)))
        points.append((CENTER + r * math.cos(phi), CENTER + r * math.sin(phi)))
    return points


def play_points(r: float = 66 * SCALE, bulge: float = 0.05, per_side: int = 40) -> list[tuple[float, float]]:
    h = r * math.sqrt(3) / 2
    vertices = [(CENTER - r / 2, CENTER - h), (CENTER + r, CENTER), (CENTER - r / 2, CENTER + h)]
    points = []
    for i in range(3):
        (x1, y1), (x2, y2) = vertices[i], vertices[(i + 1) % 3]
        dx, dy = x2 - x1, y2 - y1
        length = math.hypot(dx, dy)
        nx, ny = dy / length, -dx / length
        for k in range(per_side):
            t = k / per_side
            d = length * bulge * math.sin(math.pi * t)
            points.append((x1 + dx * t + nx * d, y1 + dy * t + ny * d))
    return points


def centroid(points: list[tuple[float, float]]) -> tuple[float, float]:
    return sum(x for x, _ in points) / len(points), sum(y for _, y in points) / len(points)


def svg(polygon_attrs: str, points: list[tuple[float, float]]) -> str:
    coords = " ".join(f"{x:.1f},{y:.1f}" for x, y in points)
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" width="1024" height="1024">'
            f'<polygon points="{coords}" {polygon_attrs}/></svg>\n')


def write_icon(dest: Path) -> None:
    assets = dest / "Assets"
    assets.mkdir(parents=True, exist_ok=True)
    (assets / "play.svg").write_text(
        svg(f'fill="#fff" stroke="#fff" stroke-width="{30 * SCALE:.1f}" stroke-linejoin="round"', play_points()))
    for ring in RINGS:
        attrs = (f'fill="none" stroke="#fff" stroke-width="{ring.stroke:.1f}" '
                 f'stroke-opacity="{ring.opacity:g}" stroke-linejoin="round"')
        (assets / f"{ring.name}.svg").write_text(svg(attrs, ring_points(ring.R, ring.a, ring.m)))
    layer = lambda name: {"image-name": f"{name}.svg", "name": name}
    manifest = {
        "fill": {"linear-gradient": [TOP, BOTTOM]},
        "groups": [
            {"layers": [layer("play")]},
            {"layers": [layer(n) for n in ("ring-inner", "ring-middle", "ring-outer")]},
        ],
        "supported-platforms": {"squares": ["macOS"]},
    }
    (dest / "icon.json").write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")


def check() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        out = Path(tmp) / "AppIcon.icon"
        write_icon(out)
        cx, cy = centroid(play_points())
        assert abs(cx - 512) < 0.5 and abs(cy - 512) < 0.5, (cx, cy)
        for ring in RINGS:
            pts = ring_points(ring.R, ring.a, ring.m)
            assert all(40 <= c <= 984 for p in pts for c in p), ring
        for f in ["icon.json", *(f"Assets/{n}.svg" for n in LAYERS)]:
            assert (out / f).read_bytes() == (ICON_DIR / f).read_bytes(), f"{f} is stale: rerun the generator"
        subprocess.run(["xcrun", "actool", str(out), "--compile", tmp, "--platform", "macosx",
                        "--minimum-deployment-target", "14.0", "--app-icon", "AppIcon",
                        "--output-partial-info-plist", f"{tmp}/p.plist"], check=True, capture_output=True)
        assert (Path(tmp) / "AppIcon.icns").exists() and (Path(tmp) / "Assets.car").exists()


if __name__ == "__main__":
    if sys.argv[1:] == ["--check"]:
        check()
    else:
        write_icon(ICON_DIR)
