#!/usr/bin/env python3
"""Generate the case list for the color-lib golden fixture.

Kept separate from the oracle binary so that regenerating golden.json never
depends on the oracle's own idea of what should be covered: this script decides
*what* to test, the oracle decides only what the right answer is.

The corpus is the 16 committed theme colors (so any drift that would visibly
change the desktop is caught) plus structural edge cases -- pure black/white,
saturated primaries, mid grey, and colors with alpha.
"""

import json

# The dark theme's base16 palette as currently committed. These are the values
# that actually render, so they are the ones that must not move.
THEME = [
    "1B2429", "323F47", "4B5B64", "667782",
    "83959F", "A4B2BC", "C7D0D6", "ECEFF1",
    "FB7929", "ED7313", "DE7E0F", "CEB335",
    "B9D119", "FB45B5", "FD4D78", "FA6515",
]

# Structural edges: achromatic extremes (hue is undefined/unstable), fully
# saturated primaries and secondaries, and an alpha case.
EDGES = [
    "000000", "FFFFFF", "808080", "7F7F7F",
    "FF0000", "00FF00", "0000FF",
    "FFFF00", "00FFFF", "FF00FF",
    "123456", "ABCDEF", "FF000080",
]

CORPUS = THEME + EDGES

CHANNELS = ["okhsl_h", "okhsl_s", "okhsl_l", "okhsv_h", "okhsv_s", "okhsv_v"]

cases = []


def add(**kw):
    kw["id"] = str(len(cases))
    cases.append(kw)


for hex_ in CORPUS:
    add(op="hexToRgb", hex=hex_)
    for ch in CHANNELS:
        add(op="get", hex=hex_, channel=ch)
        # Endpoints and midpoints; 0.0/1.0 catch clamping bugs.
        for v in (0.0, 0.25, 0.5, 0.75, 1.0):
            add(op="set", hex=hex_, channel=ch, value=v)
        # Negative and >1 deltas exercise both clamp and hue wraparound.
        for a in (-0.5, -0.1, 0.1, 0.5):
            add(op="adjust", hex=hex_, channel=ch, amount=a)
        for f in (0.0, 0.5, 1.5, 2.0):
            add(op="scale", hex=hex_, channel=ch, factor=f)

# Mixing: adjacent theme pairs, plus the extremes, across the full range.
pairs = [(THEME[i], THEME[i + 1]) for i in range(0, len(THEME) - 1, 2)]
pairs += [("000000", "FFFFFF"), ("FF0000", "00FF00"), ("FF0000", "0000FF")]
for a, b in pairs:
    for t in (0.0, 0.25, 0.5, 0.75, 1.0):
        add(op="mix", a=a, b=b, factor=t)

# Contrast ratios against the theme's own background and foreground.
for hex_ in CORPUS:
    add(op="contrast", a=hex_, b="1B2429")
    add(op="contrast", a=hex_, b="ECEFF1")

# ensureContrast: the WCAG AA thresholds that matter in practice.
for hex_ in CORPUS:
    for bg in ("1B2429", "ECEFF1"):
        for ratio in (3.0, 4.5, 7.0):
            add(op="ensureContrast", text=hex_, bg=bg, minRatio=ratio)

# rgbToHex: rounding behaviour at and around 8-bit step boundaries.
for r, g, b in [
    (0.0, 0.0, 0.0),
    (1.0, 1.0, 1.0),
    (0.5, 0.5, 0.5),
    (0.5019607843137255, 0.25, 0.75),
    (0.001, 0.999, 0.5),
    (0.0019607843137, 0.0039215686, 0.0058823529),
]:
    add(op="rgbToHex", r=r, g=g, b=b)

print(json.dumps(cases, indent=2))
