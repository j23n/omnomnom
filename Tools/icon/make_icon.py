#!/usr/bin/env python3
"""Render the app icon: the bite mark, white on the tangerine accent colour.

The geometry is the one `BiteMark` (Omnomnom/Support/Brand/BiteMark.swift) draws in
the app and `docs/design/icon/mark.svg` holds for Icon Composer: a disc with one round
bite taken out of its upper right and two crumbs, every value relative to the square.
Change it there first and mirror it here.

Standard library only. Each pixel gets a signed distance to every circle; the edges
are blended over about one and a half pixels so the disc stays smooth at 1024 px.

    python3 Tools/icon/make_icon.py            # writes the 1024 px icon into the asset catalog
    python3 Tools/icon/make_icon.py --size 256 --out /tmp/preview.png
"""

from __future__ import annotations

import argparse
import math
import struct
import sys
import zlib
from pathlib import Path
from typing import List, Sequence, Tuple

Circle = Tuple[float, float, float]  # centre x, centre y, radius; all relative to the square

BACKGROUND = (0xE8, 0x64, 0x1C)  # the light accent colour, full bleed; iOS masks the corners
MARK = (0xFF, 0xFF, 0xFF)

DISC: Circle = (0.50, 0.53, 0.30)
BITE: Circle = (0.695, 0.325, 0.135)
CRUMBS: Sequence[Circle] = ((0.80, 0.235, 0.024), (0.855, 0.31, 0.016))

EDGE_PIXELS = 1.5

DEFAULT_OUTPUT = (
    Path(__file__).resolve().parents[2]
    / "Omnomnom"
    / "Assets.xcassets"
    / "AppIcon.appiconset"
    / "AppIcon.png"
)


def coverage(distance: float, edge: float) -> float:
    """How much of a pixel a circle covers, from its signed distance in pixels.

    Negative distances are inside. The transition is a smoothstep across `edge`
    pixels centred on the outline.
    """
    t = 0.5 - distance / edge
    if t <= 0.0:
        return 0.0
    if t >= 1.0:
        return 1.0
    return t * t * (3.0 - 2.0 * t)


def mark_coverage(x: float, y: float, size: int, edge: float) -> float:
    """Coverage of the mark at pixel centre (x, y): disc minus bite, plus crumbs."""

    def circle(c: Circle) -> float:
        cx, cy, r = c
        d = math.hypot(x - cx * size, y - cy * size) - r * size
        return coverage(d, edge)

    inside = min(circle(DISC), 1.0 - circle(BITE))
    for crumb in CRUMBS:
        inside = max(inside, circle(crumb))
    return inside


def render(size: int, edge: float = EDGE_PIXELS) -> List[bytes]:
    """Rows of packed RGB bytes for a `size` by `size` icon."""
    circles = (DISC, BITE, *CRUMBS)
    # Rows and columns no circle reaches are plain background; skipping them keeps the
    # per-pixel loop to the part of the square that can change.
    reach = edge
    top = min((cy - r) * size for _, cy, r in circles) - reach
    bottom = max((cy + r) * size for _, cy, r in circles) + reach
    left = min((cx - r) * size for cx, _, r in circles) - reach
    right = max((cx + r) * size for cx, _, r in circles) + reach

    background_row = bytes(BACKGROUND) * size
    background = bytes(BACKGROUND)
    rows: List[bytes] = []
    for j in range(size):
        y = j + 0.5
        if y < top or y > bottom:
            rows.append(background_row)
            continue
        row = bytearray(background_row)
        for i in range(size):
            x = i + 0.5
            if x < left or x > right:
                continue
            a = mark_coverage(x, y, size, edge)
            if a <= 0.0:
                continue
            offset = i * 3
            if a >= 1.0:
                row[offset : offset + 3] = MARK
                continue
            for k in range(3):
                row[offset + k] = round(background[k] + (MARK[k] - background[k]) * a)
        rows.append(bytes(row))
    return rows


def png_chunk(kind: bytes, data: bytes) -> bytes:
    body = kind + data
    return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body) & 0xFFFFFFFF)


def encode_png(rows: Sequence[bytes], width: int, height: int) -> bytes:
    """An 8-bit RGB PNG without alpha, which is what an app icon has to be."""
    header = struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)
    raw = b"".join(b"\x00" + row for row in rows)  # filter type 0 on every scanline
    return b"".join(
        (
            b"\x89PNG\r\n\x1a\n",
            png_chunk(b"IHDR", header),
            png_chunk(b"IDAT", zlib.compress(raw, 9)),
            png_chunk(b"IEND", b""),
        )
    )


def main(argv: Sequence[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--size", type=int, default=1024, help="side length in pixels (default 1024)")
    parser.add_argument("--out", type=Path, default=DEFAULT_OUTPUT, help=f"output PNG (default {DEFAULT_OUTPUT})")
    args = parser.parse_args(argv)
    if args.size < 16:
        parser.error("--size must be at least 16")

    rows = render(args.size)
    data = encode_png(rows, args.size, args.size)
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_bytes(data)
    print(f"wrote {args.out} ({args.size}x{args.size}, {len(data)} bytes)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
