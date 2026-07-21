"""Per-lens calibration parameters and X5 defaults."""
from __future__ import annotations

from dataclasses import dataclass


@dataclass
class LensCalib:
    """One lens's orientation + projection parameters."""

    name: str
    model: str  # "equidistant" or "ucm"

    yaw_deg: float
    pitch_deg: float
    roll_deg: float

    fov_deg: float  # total angular diameter of the fisheye circle (equidistant model)

    cx: float  # source-pixel principal point (within this lens's own crop)
    cy: float
    radius_px: float  # inscribed-circle radius, source pixels

    # UCM-only (phase 2 / trailer-derived calibration):
    xi: float = 2.0
    fx: float = 0.0
    fy: float = 0.0
    dist_coeffs: tuple = (0.0, 0.0, 0.0, 0.0)


def default_x5_calib(lens_size: int) -> tuple[LensCalib, LensCalib]:
    """Reasonable starting-point calibration for an Insta360 X5 .insp photo.

    lens_size is the width/height of each (square) fisheye crop, e.g. 5952.
    Orientation refined by align.optimize(); fov_deg is the main free
    parameter align.py searches over (analogous to ffmpeg's ih_fov/iv_fov).
    """
    cx = cy = lens_size / 2.0
    radius_px = lens_size / 2.0 * 0.98  # small margin inside the physical circle

    back = LensCalib(
        name="back",
        model="equidistant",
        yaw_deg=180.0,
        pitch_deg=0.0,
        roll_deg=0.0,
        fov_deg=200.0,
        cx=cx,
        cy=cy,
        radius_px=radius_px,
    )
    front = LensCalib(
        name="front",
        model="equidistant",
        yaw_deg=0.0,
        pitch_deg=0.0,
        roll_deg=0.0,
        fov_deg=200.0,
        cx=cx,
        cy=cy,
        radius_px=radius_px,
    )
    return back, front
