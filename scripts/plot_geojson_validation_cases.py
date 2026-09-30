"""Render the saved GeoJSON validation fixtures as a reviewable contact sheet."""

import json
import math
from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt


ROOT = Path(__file__).resolve().parents[1]
FIXTURES = ROOT / "test" / "fixtures" / "geojson_validation"
OUTPUT = ROOT / "docs" / "images" / "geojson_validation_cases.png"

# These outcomes are asserted by test/geo/geojson_validator_test.dart.
CASES = [
    ("valid-square", "phone OK / Garmin OK", "#16805d"),
    ("vertices-3", "phone OK / Garmin OK", "#16805d"),
    ("vertices-100", "phone OK / Garmin OK", "#16805d"),
    ("vertices-101", "phone OK / Garmin NG", "#b57900"),
    ("hole", "hole: phone NG", "#bb4040"),
    ("empty-inner-ring", "empty hole: phone NG", "#bb4040"),
    ("bow-tie", "crossing: phone NG", "#bb4040"),
    ("vertex-touch", "touch: phone NG", "#bb4040"),
    ("overlapping-edge", "overlap: phone NG", "#bb4040"),
    ("duplicate-consecutive", "duplicate: phone NG", "#bb4040"),
    ("open-ring", "open: phone NG", "#bb4040"),
    ("collinear", "area 0: phone NG", "#bb4040"),
    ("multi-polygon", "single Polygon required: phone NG", "#bb4040"),
    ("tiny-area", "area warning", "#16805d"),
    ("long-edge", "edge warning", "#16805d"),
    ("qr-precision-loss", "QR rounding: NG", "#b57900"),
    ("invalid-coordinate", "coordinate: phone NG", "#bb4040"),
]


def rings_for(document):
    for feature in document["features"]:
        geometry = feature["geometry"]
        if geometry["type"] == "Polygon":
            yield from geometry["coordinates"]
        elif geometry["type"] == "MultiPolygon":
            for polygon in geometry["coordinates"]:
                yield from polygon


def draw_case(ax, name, status, color):
    document = json.loads((FIXTURES / f"{name}.geojson").read_text(encoding="utf-8"))
    rings = list(rings_for(document))
    if name == "invalid-coordinate":
        # Keep the invalid original in the fixture; compress its 181° point
        # only for this schematic so the three corners remain visible.
        rings = [[[139.004 if p[0] == 181 else p[0], p[1]] for p in ring]
                 for ring in rings]
    points = [point for ring in rings for point in ring if len(point) >= 2]
    lon0 = sum(point[0] for point in points) / len(points)
    lat0 = sum(point[1] for point in points) / len(points)

    def xy(point):
        return ((point[0] - lon0) * 111320 * math.cos(math.radians(lat0)),
                (point[1] - lat0) * 110540)

    for index, ring in enumerate(rings):
        if not ring:
            ax.text(0.5, 0.53, "empty inner ring", transform=ax.transAxes,
                    ha="center", va="center", color="#bb4040", fontsize=8)
            continue
        local = [xy(point) for point in ring]
        xs, ys = zip(*local)
        ax.plot(xs, ys, color="#4268a1" if index == 0 else "#bb4040",
                linewidth=1.7, linestyle="--" if index > 0 else "-",
                marker="o" if len(local) <= 9 else None,
                markersize=3)
        if name == "open-ring" and index == 0:
            ax.scatter([xs[0]], [ys[0]], color="#16805d", s=35, zorder=4)
            ax.scatter([xs[-1]], [ys[-1]], color="#bb4040", s=35, zorder=4)
        if name == "invalid-coordinate" and index == 0:
            ax.scatter([xs[1]], [ys[1]], marker="x", color="#bb4040",
                       s=80, linewidth=2.5, zorder=5)
            ax.annotate("181° lon", (xs[1], ys[1]), xytext=(5, 7),
                        textcoords="offset points", fontsize=8,
                        color="#bb4040")
        if name == "qr-precision-loss" and index == 0:
            ax.text(0.5, 0.08, "~2 cm → 0 at 6 decimals",
                    transform=ax.transAxes, ha="center", fontsize=8,
                    color="#b57900")
    ax.set_aspect("equal", adjustable="datalim")
    ax.margins(0.25)
    ax.set_xticks([])
    ax.set_yticks([])
    for spine in ax.spines.values():
        spine.set_color("#d4dce7")
    ax.set_title(name, loc="left", fontsize=10, fontweight="bold", pad=14)
    ax.text(0, 1.01, status, color=color, transform=ax.transAxes,
            fontsize=8, va="bottom")


def main():
    fig, axes = plt.subplots(5, 4, figsize=(14, 16), facecolor="white")
    for ax, (name, status, color) in zip(axes.flat, CASES):
        draw_case(ax, name, status, color)
    for ax in list(axes.flat)[len(CASES):]:
        ax.axis("off")
    fig.suptitle("GeoJSON validation cases (schematic, each panel scaled separately)",
                 fontsize=16, fontweight="bold", y=0.995)
    fig.subplots_adjust(top=0.955, bottom=0.035, left=0.045, right=0.98,
                        hspace=0.58, wspace=0.2)
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(OUTPUT, dpi=170)
    plt.close(fig)
    print(OUTPUT)


if __name__ == "__main__":
    main()
