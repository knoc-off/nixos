"""Phase 2 (not yet implemented): parse the embedded Insta360 calibration
blob from the .insp file's EOF trailer, to replace align.py's image-content
search with the camera's actual factory calibration.

Known from community reverse-engineering (see insv-stitch's FINDINGS.md):
  - .insp files have an "Insta360" magic marker and `8888`-delimited records
    near EOF, similar in spirit to the documented .insv footer format.
  - .insv calibration (in the sidecar .pb) is a base64-encoded, `_`-delimited
    string per lens: fx, fy, cx, cy, yaw, pitch, half_fov, Rodrigues rotation,
    k1-k4, p1-p2, s1-s4, tauX/Y, ref_width/height. Photos don't get a .pb
    sidecar, so if this data exists for .insp it must live in the trailer
    itself; the exact record layout for photos is not yet confirmed here.

This module intentionally raises until that layout is confirmed against a
real file, so pipeline.py's fallback to align.py's auto-search is explicit
rather than silently wrong.
"""
from __future__ import annotations

from .calibration import LensCalib


class TrailerNotSupported(NotImplementedError):
    pass


def parse_trailer(path: str) -> tuple[LensCalib, LensCalib]:
    raise TrailerNotSupported(
        "embedded .insp calibration parsing is not implemented yet; use auto-search (default)"
    )
