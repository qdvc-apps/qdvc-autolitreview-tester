#!/usr/bin/env python3
"""Generate the app icon: Resources/AppIcon.svg (vector master) and
Resources/AppIcon.icns (every macOS size, rendered natively from the vector).

The design is a frosted-glass report page with a bookmark ribbon, under a
magnifying glass whose lens holds a check mark: a literature review, being
checked. The "Sea Glass" palette (pale mint to deep teal) sets it apart from
the butter-yellow QDVC Nice Mail while keeping the family's Liquid Glass
style: soft gradients, translucent layers and bright specular rims.

Geometry follows Apple's macOS icon template: a 1024x1024 canvas holding an
824x824 tile (100 px transparent margin) with a 185.4 px continuous-curvature
("squircle") corner, plus a soft drop shadow. The corner is the curve UIKit
draws for continuous corners, as reverse-engineered and published by PaintCode
(https://www.paintcodeapp.com/blogpost/code-for-ios-7-rounded-rectangles).

Usage:

    python3 tools/make_icon.py            # writes Resources/AppIcon.{svg,icns}
    python3 tools/make_icon.py --preview  # also writes build/icon-preview.png

Requires rsvg-convert (macOS: `brew install librsvg`; Debian/Ubuntu:
`apt install librsvg2-bin`). No other dependencies; the .icns is written
directly, so Apple's iconutil is not needed.
"""

import argparse
import struct
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
RESOURCES = ROOT / "Resources"

# ---------------------------------------------------------------------------
# Palette ("Sea Glass").

BG_TOP = "#E3FAF4"
BG_DEEP = "#1F8F87"
INK = "#0E5C5A"         # text lines, ribbon shadow, the lens rim
RIBBON = "#F2795B"      # the bookmark: a warm accent against the teal
CHECK = "#13A36B"

# ---------------------------------------------------------------------------
# Apple's template geometry.

TILE_ORIGIN, TILE_SIZE, CORNER_RADIUS = 100, 824, 185.4
SHADOW_BLUR_RADIUS, SHADOW_OFFSET_Y, SHADOW_OPACITY = 28, 12, 0.5

# Continuous-corner segments around the top-right corner, in units of the
# radius: (distance from the right edge, distance from the top edge).
_CORNER = [
    ("L", (1.52866471, 0.0)),
    ("C", (1.08849323, 0.0), (0.86840689, 0.0), (0.66993427, 0.06549600)),
    ("L", (0.63149399, 0.07491100)),
    ("C", (0.37282392, 0.16905899), (0.16906013, 0.37282401), (0.07491176, 0.63149399)),
    ("C", (0.0, 0.86840701), (0.0, 1.08849299), (0.0, 1.52866483)),
]


def continuous_rounded_rect(x, y, w, h, r):
    """SVG path of a rounded rectangle with Apple's continuous corners."""
    r = min(r, min(w, h) / 2 / 1.52866483)
    corners = [
        lambda u, v: (x + w - u * r, y + v * r),        # top-right
        lambda u, v: (x + w - v * r, y + h - u * r),    # bottom-right
        lambda u, v: (x + u * r, y + h - v * r),        # bottom-left
        lambda u, v: (x + v * r, y + u * r),            # top-left
    ]

    def fmt(p):
        return f"{p[0]:.2f},{p[1]:.2f}"

    d = [f"M{fmt((x + 1.52866483 * r, y))}"]
    for corner in corners:
        for seg in _CORNER:
            if seg[0] == "L":
                d.append("L" + fmt(corner(*seg[1])))
            else:
                d.append("C" + " ".join(fmt(corner(*p)) for p in seg[1:]))
    d.append("Z")
    return " ".join(d)


TILE = continuous_rounded_rect(TILE_ORIGIN, TILE_ORIGIN, TILE_SIZE, TILE_SIZE, CORNER_RADIUS)

PAGE = (262, 196, 430, 560)     # x, y, width, height
LENS_CENTRE, LENS_RADIUS = (616, 600), 150


def _page():
    x, y, w, h = PAGE
    parts = [
        f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="44" fill="url(#glass)"/>',
        f'<rect x="{x + 2}" y="{y + 2}" width="{w - 4}" height="{h - 4}" rx="42" fill="none" '
        'stroke="url(#rim)" stroke-width="4"/>',
    ]
    # The bookmark ribbon hanging from the top edge.
    rx = x + w - 112
    parts.append(f'<path d="M{rx},{y - 2} h56 v126 l-28,-24 l-28,24 Z" fill="{RIBBON}"/>')
    parts.append(f'<path d="M{rx},{y - 2} h56 v14 h-56 Z" fill="{INK}" opacity="0.25"/>')
    # Lines of text: a title, then body lines of varying length.
    lines = [(70, 0.50, 18), (130, 0.80, 12), (166, 0.74, 12), (202, 0.82, 12), (238, 0.58, 12),
             (290, 0.78, 12), (326, 0.66, 12), (362, 0.80, 12), (398, 0.44, 12)]
    for dy, frac, thick in lines:
        parts.append(f'<rect x="{x + 54}" y="{y + dy}" width="{(w - 108) * frac:.1f}" height="{thick}" '
                     f'rx="{thick / 2}" fill="{INK}" opacity="{0.55 if thick > 12 else 0.30}"/>')
    return parts


def _magnifier():
    cx, cy = LENS_CENTRE
    r = LENS_RADIUS
    # Handle, down and to the right at 45 degrees.
    hx0, hy0 = cx + r * 0.72, cy + r * 0.72
    hx1, hy1 = cx + r * 1.50, cy + r * 1.50
    return [
        f'<line x1="{hx0:.1f}" y1="{hy0:.1f}" x2="{hx1:.1f}" y2="{hy1:.1f}" stroke="{INK}" '
        'stroke-width="62" stroke-linecap="round"/>',
        f'<line x1="{hx0:.1f}" y1="{hy0:.1f}" x2="{hx1:.1f}" y2="{hy1:.1f}" stroke="#FFFFFF" '
        'stroke-opacity="0.22" stroke-width="18" stroke-linecap="round" transform="translate(-10,-10)"/>',
        f'<circle cx="{cx}" cy="{cy}" r="{r}" fill="url(#lens)"/>',
        f'<circle cx="{cx}" cy="{cy}" r="{r}" fill="none" stroke="{INK}" stroke-width="34"/>',
        f'<circle cx="{cx}" cy="{cy}" r="{r - 15}" fill="none" stroke="#FFFFFF" stroke-opacity="0.55" stroke-width="5"/>',
        # The check mark.
        f'<path d="M{cx - r * 0.46:.1f},{cy + r * 0.02:.1f} L{cx - r * 0.12:.1f},{cy + r * 0.36:.1f} '
        f'L{cx + r * 0.50:.1f},{cy - r * 0.34:.1f}" fill="none" stroke="{CHECK}" stroke-width="40" '
        'stroke-linecap="round" stroke-linejoin="round"/>',
        # Specular highlight on the glass.
        f'<ellipse cx="{cx - r * 0.34:.1f}" cy="{cy - r * 0.48:.1f}" rx="{r * 0.36:.1f}" ry="{r * 0.16:.1f}" '
        'fill="#FFFFFF" opacity="0.55" transform="rotate(-28 {cx} {cy})"/>'.replace("{cx}", str(cx)).replace("{cy}", str(cy)),
    ]


def icon_svg():
    sigma = SHADOW_BLUR_RADIUS / 2
    defs = [
        f'<linearGradient id="bg" x1="0" y1="0" x2="0.35" y2="1">'
        f'<stop offset="0" stop-color="{BG_TOP}"/><stop offset="1" stop-color="{BG_DEEP}"/></linearGradient>',
        '<radialGradient id="glow" cx="0.30" cy="0.18" r="0.75">'
        '<stop offset="0" stop-color="#FFFFFF" stop-opacity="0.38"/>'
        '<stop offset="1" stop-color="#FFFFFF" stop-opacity="0"/></radialGradient>',
        '<linearGradient id="sheen" x1="0" y1="0" x2="0" y2="1">'
        '<stop offset="0" stop-color="#FFFFFF" stop-opacity="0.22"/>'
        '<stop offset="0.40" stop-color="#FFFFFF" stop-opacity="0.03"/>'
        '<stop offset="1" stop-color="#FFFFFF" stop-opacity="0"/></linearGradient>',
        '<linearGradient id="rim" x1="0" y1="0" x2="0" y2="1">'
        '<stop offset="0" stop-color="#FFFFFF" stop-opacity="0.95"/>'
        '<stop offset="0.5" stop-color="#FFFFFF" stop-opacity="0.35"/>'
        '<stop offset="1" stop-color="#FFFFFF" stop-opacity="0.6"/></linearGradient>',
        '<linearGradient id="edge" x1="0" y1="0" x2="0" y2="1">'
        '<stop offset="0" stop-color="#FFFFFF" stop-opacity="0.75"/>'
        '<stop offset="0.5" stop-color="#FFFFFF" stop-opacity="0.12"/>'
        '<stop offset="1" stop-color="#FFFFFF" stop-opacity="0.35"/></linearGradient>',
        '<linearGradient id="glass" x1="0" y1="0" x2="0" y2="1">'
        '<stop offset="0" stop-color="#FFFFFF" stop-opacity="0.94"/>'
        '<stop offset="1" stop-color="#E6F6F2" stop-opacity="0.80"/></linearGradient>',
        '<radialGradient id="lens" cx="0.40" cy="0.35" r="0.75">'
        '<stop offset="0" stop-color="#FFFFFF" stop-opacity="0.92"/>'
        '<stop offset="1" stop-color="#CFF1E8" stop-opacity="0.78"/></radialGradient>',
        f'<clipPath id="clip"><path d="{TILE}"/></clipPath>',
        # Apple template shadow: black, 28 px blur radius, 12 px down, 50 %.
        '<filter id="shadow" x="-20%" y="-20%" width="140%" height="140%">'
        f'<feGaussianBlur in="SourceAlpha" stdDeviation="{sigma}"/><feOffset dy="{SHADOW_OFFSET_Y}"/>'
        f'<feComponentTransfer><feFuncA type="linear" slope="{SHADOW_OPACITY}"/></feComponentTransfer>'
        '<feMerge><feMergeNode/><feMergeNode in="SourceGraphic"/></feMerge></filter>',
        '<filter id="objshadow" x="-30%" y="-30%" width="160%" height="160%">'
        '<feGaussianBlur in="SourceAlpha" stdDeviation="14"/><feOffset dx="0" dy="16"/>'
        f'<feFlood flood-color="{INK}" flood-opacity="0.45"/><feComposite operator="in" in2="SourceAlpha"/>'
        '<feMerge><feMergeNode/><feMergeNode in="SourceGraphic"/></feMerge></filter>',
    ]
    parts = [
        f'<g filter="url(#shadow)"><path d="{TILE}" fill="url(#bg)"/></g>',
        '<g clip-path="url(#clip)">',
        '<rect x="100" y="100" width="824" height="824" fill="url(#glow)"/>',
        '<g filter="url(#objshadow)">', *_page(), '</g>',
        '<g filter="url(#objshadow)">', *_magnifier(), '</g>',
        '<rect x="100" y="100" width="824" height="824" fill="url(#sheen)"/>',
        '</g>',
        f'<path d="{TILE}" fill="none" stroke="url(#edge)" stroke-width="6"/>',
    ]
    return ('<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">'
            f'<defs>{"".join(defs)}</defs>{"".join(parts)}</svg>\n')


# ---------------------------------------------------------------------------
# .icns writing. These are the element types `iconutil` emits for a standard
# .iconset; all of them hold PNG data.

ICNS_ELEMENTS = [
    ("icp4", 16), ("ic11", 32), ("icp5", 32), ("ic12", 64),
    ("ic07", 128), ("ic13", 256), ("ic08", 256), ("ic14", 512),
    ("ic09", 512), ("ic10", 1024),
]


def render_png(svg_path, size, out_path):
    subprocess.run(["rsvg-convert", "-w", str(size), "-h", str(size), str(svg_path), "-o", str(out_path)],
                   check=True)


def write_icns(pngs_by_size, out_path):
    chunks = b""
    for code, size in ICNS_ELEMENTS:
        data = pngs_by_size[size]
        chunks += code.encode("ascii") + struct.pack(">I", len(data) + 8) + data
    out_path.write_bytes(b"icns" + struct.pack(">I", len(chunks) + 8) + chunks)


def main():
    parser = argparse.ArgumentParser(description="Generate Resources/AppIcon.svg and AppIcon.icns.")
    parser.add_argument("--preview", action="store_true",
                        help="also write build/icon-preview.png (1024 px)")
    args = parser.parse_args()

    try:
        subprocess.run(["rsvg-convert", "--version"], check=True, capture_output=True)
    except (OSError, subprocess.CalledProcessError):
        sys.exit("error: rsvg-convert not found (macOS: brew install librsvg)")

    RESOURCES.mkdir(exist_ok=True)
    svg_path = RESOURCES / "AppIcon.svg"
    svg_path.write_text(icon_svg())

    with tempfile.TemporaryDirectory() as tmp:
        pngs = {}
        for size in sorted({s for _, s in ICNS_ELEMENTS}):
            png = Path(tmp) / f"icon_{size}.png"
            render_png(svg_path, size, png)
            pngs[size] = png.read_bytes()
        write_icns(pngs, RESOURCES / "AppIcon.icns")

    if args.preview:
        (ROOT / "build").mkdir(exist_ok=True)
        render_png(svg_path, 1024, ROOT / "build" / "icon-preview.png")
    print(f"Wrote {svg_path.relative_to(ROOT)} and Resources/AppIcon.icns")


if __name__ == "__main__":
    main()
