#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Christopher Conley
# SPDX-License-Identifier: MIT
"""Regenerate assets/logo_subtitle.svg -- the UNKONGTROLLED title-screen subtitle.

    pip install svgelements
    python3 tools/logo/build_logo_subtitle.py assets/logo_subtitle.svg

The subtitle is rebuilt from the original REKONGPILED artwork, preserved beside this
script, rather than redrawn, so every letter keeps its traced, hand-drawn edge.

How the original is built, and so how this rebuilds it
------------------------------------------------------
The original is potrace output in three layers, but only one of them carries the
design. The red letter fills (layer 1) are the letters; the yellow outline, the thin
red rim and the dark drop shadow are uniform expansions of those fills, by about 9 and
15 px. So only the fills are rearranged here, and the other three are regenerated from
them as rounded strokes. Rebuilding REKONGPILED this way and diffing it against the
original differs on 2.24% of pixels, nearly all of it antialiasing.

KONG (with its star O) and LED are lifted intact, since both words contain them. The
two letters REKONGPILED lacks are made from its L:

    U  = L + L mirrored, stems at the outer edges
    T  = L flipped vertically + that mirrored, stems overlapping

Everything worth adjusting is a named constant below.
"""
import math
import re
import sys
from pathlib import Path as FsPath

from svgelements import Matrix, Path

HERE = FsPath(__file__).resolve().parent
SOURCE = HERE / "logo_subtitle_rekongpiled.svg"

# --- tunables --------------------------------------------------------------------------
GAP = -4.0              # default space between letters; negative overlaps, as the original does
EXTRA = {"U": 0.0}      # extra space AFTER the named unit. 0 fuses U and N like the N and K
R_YELLOW = 9.0          # yellow outline reach beyond the letter edge, source px
R_RIM = 15.0            # red rim reach; the rim is the band between R_YELLOW and R_RIM
SHADOW = (0.0, 16.0)    # drop-shadow offset
FIT = 1100.0            # letter span to scale into; 13 letters need ~80% of the original size
CENTRE_X = 669.5        # horizontal centre of the original word, so it sits under DK64
U_STRAIGHTEN = 0.045    # measured: the L's stem drifts +5.0 px right over 111 px going up
U_OUTWARD_DEG = 2.5     # after straightening, tilt the U's left post outward by this much
U_WIDTH = 110.0         # outer width of the constructed U
T_STEM = 32.0           # measured stem width of the L, used to overlap the two halves of the T

# --- the source artwork ----------------------------------------------------------------
_src = SOURCE.read_text()
_red = re.findall(r'<path[^>]*\sd="([^"]*)"', _src)[0]          # layer 1: the red fills
SUBS = [Path(sp) for sp in (Path(_red) * Matrix("translate(0,747) scale(0.1,-0.1)")).as_subpaths()]

# Layer-1 subpaths per letter, identified by bounding box. The first index of each is the
# letter's outer contour; the rest are its counters. #0 and #1 are the rim and are unused.
LETTERS = {
    "R": [11, 12, 13], "E1": [19, 24, 27], "K": [14], "O": [2, 3], "N": [6],
    "G": [4, 21, 22, 23], "P": [15, 16, 17], "I": [18], "L": [5], "E2": [20, 25, 26],
    "D": [7, 8, 9, 10],
}

IDENTITY = Matrix()
_Lx0, _Ly0, _Lx1, _Ly1 = SUBS[5].bbox()
_Lcx, _Lcy = (_Lx0 + _Lx1) / 2, (_Ly0 + _Ly1) / 2
FLIP_H = Matrix(f"translate({2 * _Lcx},0) scale(-1,1)")
FLIP_V = Matrix(f"translate(0,{2 * _Lcy}) scale(1,-1)")

# x' = x + k*(y - bottom). y grows downward, so the stem's top moves left for k > 0,
# while the foot at the bottom stays put.
_k = U_STRAIGHTEN + math.tan(math.radians(U_OUTWARD_DEG))
U_LEFT_SKEW = Matrix(1, 0, _k, 1, -_k * _Ly1, 0)

# The N's left edge is concave (x 549 at the top, 562 mid-height, 552 at the bottom): it was
# cut to wrap around the O it follows in KONG. Beside the U's flat post that curve leaves a
# lens of yellow. A straight-edged strip from its top-left to its bottom-left corner fills
# the dip; it paints as a union with the N, so no boolean geometry is needed.
SUBS.append(Path("M 549,487 L 570,487 L 570,620 L 552.5,620 Z"))
N_FILL = len(SUBS) - 1


def source(*keys):
    return [(LETTERS[k], IDENTITY) for k in keys]


# Each unit is a list of (subpath indices, transform). A unit may be several letters kept
# together at their original spacing (KONG, LED) or one constructed letter (U, T).
UNITS = [
    ("U", [([5], U_LEFT_SKEW),
           ([5], FLIP_H * Matrix(f"translate({(_Lx0 + U_WIDTH) - _Lx1},0)"))]),
    ("N", [([6], IDENTITY), ([N_FILL], IDENTITY)]),
    ("KONG", source("K", "O", "N", "G")),
    ("T", [([5], FLIP_V),
           ([5], FLIP_V * FLIP_H * Matrix(f"translate({-((_Lx1 - T_STEM) - _Lx0)},0)"))]),
    ("R", source("R")),
    ("O", source("O")),
    ("L", source("L")),
    ("LED", source("L", "E2", "D")),
]


def _bbox(pieces):
    xs, ys = [], []
    for idxs, m in pieces:
        x0, y0, x1, y1 = (SUBS[idxs[0]] * m).bbox()
        xs += [x0, x1]
        ys += [y0, y1]
    return min(xs), min(ys), max(xs), max(ys)


def build():
    placed, cursor = [], None
    for name, pieces in UNITS:
        x0, _, x1, _ = _bbox(pieces)
        move = Matrix(f"translate({0.0 if cursor is None else cursor - x0},0)")
        placed.append([(ix, m * move) for ix, m in pieces])
        cursor = x1 + (0.0 if cursor is None else cursor - x0) + GAP + EXTRA.get(name, 0.0)

    every = [p for unit in placed for p in unit]
    X0, Y0, X1, Y1 = _bbox(every)
    scale = min(1.0, FIT / (X1 - X0))
    cy = (Y0 + Y1) / 2
    # A transform string applies its rightmost operation first.
    G = Matrix(f"translate({CENTRE_X},{cy}) scale({scale}) translate({-(X0 + X1) / 2},{-cy})")

    def d(idxs, m):
        # Absolute coordinates: a relative 'm' would be offset by the previous subpath.
        return " ".join((SUBS[i] * (m * G)).d(relative=False) for i in idxs)

    outer = " ".join(d([ix[0]], m) for ix, m in every)
    rim, yellow = 2 * R_RIM * scale, 2 * R_YELLOW * scale
    rnd = 'stroke-linejoin="round" stroke-linecap="round"'
    layers = [
        f'<path d="{outer}" transform="translate({SHADOW[0] * scale},{SHADOW[1] * scale})" '
        f'fill="#8b0101" stroke="#8b0101" stroke-width="{rim}" {rnd}/>',
        f'<path d="{outer}" fill="url(#g)" stroke="url(#g)" stroke-width="{rim}" {rnd}/>',
        f'<path d="{outer}" fill="#eed629" stroke="#eed629" stroke-width="{yellow}" {rnd}/>',
    ]
    # One path per piece, so evenodd only ever cuts counters WITHIN a letter.
    layers += [f'<path d="{d(ix, m)}" fill="url(#g)" fill-rule="evenodd"/>' for ix, m in every]
    grad = ('<defs><linearGradient id="g" x1="0%" y1="0%" x2="0%" y2="100%">'
            '<stop offset="0%" stop-color="#be0401"/><stop offset="100%" stop-color="#e20411"/>'
            '</linearGradient></defs>')
    svg = ('<?xml version="1.0" encoding="UTF-8"?>\n<svg xmlns="http://www.w3.org/2000/svg" '
           'width="1280" height="747" viewBox="0 0 1280 747">' + grad + "".join(layers) + "</svg>")
    return svg, scale


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit(f"usage: {sys.argv[0]} OUTPUT.svg")
    svg, scale = build()
    FsPath(sys.argv[1]).write_text(svg)
    print(f"wrote {sys.argv[1]}  (scale {scale:.3f})", file=sys.stderr)
