"""Auto-search lens geometry (FOV + fine per-lens orientation) by maximizing
agreement between the two lenses in their overlap bands.

This directly replaces manual FOV tuning (e.g. ffmpeg's ih_fov/iv_fov): a
single global FOV cannot be correct at every distance because of parallax
between the two lenses, but it *can* be made correct at "infinity", which is
what this search optimizes for. Residual near-field parallax is handled later
by flow.py.
"""
from __future__ import annotations

import copy
from dataclasses import replace

import cv2
import numpy as np

from . import remap
from .calibration import LensCalib

# Longitude bands (radians) around the two seams (+90, -90 degrees) used to
# score alignment.
_BAND_DEG = 8.0


def _overlap_score(back: LensCalib, front: LensCalib, out_w: int, out_h: int, back_img, front_img, backend: str = "auto") -> float:
    map_x_b, map_y_b, valid_b, lon = remap.build_lens_maps(back, out_w, out_h, backend=backend)
    map_x_f, map_y_f, valid_f, _ = remap.build_lens_maps(front, out_w, out_h, backend=backend)

    rendered_b, cov_b = remap.render_lens(back_img, map_x_b, map_y_b, valid_b)
    rendered_f, cov_f = remap.render_lens(front_img, map_x_f, map_y_f, valid_f)

    band = np.deg2rad(_BAND_DEG)
    near_seam = (np.abs(np.abs(lon) - np.pi / 2.0) < band)
    both_valid = near_seam & (cov_b > 0) & (cov_f > 0)

    if both_valid.sum() < 100:
        return -1.0

    gb = cv2.cvtColor(rendered_b, cv2.COLOR_BGR2GRAY).astype(np.float64)
    gf = cv2.cvtColor(rendered_f, cv2.COLOR_BGR2GRAY).astype(np.float64)

    a = gb[both_valid]
    b = gf[both_valid]
    a = a - a.mean()
    b = b - b.mean()
    denom = np.sqrt((a * a).sum() * (b * b).sum())
    if denom < 1e-6:
        return -1.0
    return float((a * b).sum() / denom)


def _search_fov(back: LensCalib, front: LensCalib, out_w: int, out_h: int, back_img, front_img, lo: float, hi: float, iters: int = 12, backend: str = "auto") -> float:
    """1-D golden-section search over total FOV degrees."""
    gr = (np.sqrt(5) - 1) / 2
    a, b = lo, hi
    c = b - gr * (b - a)
    d = a + gr * (b - a)

    def score_at(fov):
        bb = replace(back, fov_deg=fov)
        ff = replace(front, fov_deg=fov)
        return _overlap_score(bb, ff, out_w, out_h, back_img, front_img, backend=backend)

    fc, fd = score_at(c), score_at(d)
    for _ in range(iters):
        if fc > fd:
            b, d, fd = d, c, fc
            c = b - gr * (b - a)
            fc = score_at(c)
        else:
            a, c, fc = c, d, fd
            d = a + gr * (b - a)
            fd = score_at(d)
    return (a + b) / 2.0


def _refine_orientation(back: LensCalib, front: LensCalib, out_w: int, out_h: int, back_img, front_img, step_deg: float = 2.0, rounds: int = 3, backend: str = "auto"):
    """Coordinate-descent refinement of small per-lens yaw/pitch/roll offsets."""
    back, front = copy.copy(back), copy.copy(front)
    best_score = _overlap_score(back, front, out_w, out_h, back_img, front_img, backend=backend)

    for _ in range(rounds):
        improved = False
        for lens_name, lens in (("back", back), ("front", front)):
            for attr in ("yaw_deg", "pitch_deg", "roll_deg"):
                for sign in (+1, -1):
                    trial = copy.copy(lens)
                    setattr(trial, attr, getattr(trial, attr) + sign * step_deg)
                    trial_back, trial_front = (trial, front) if lens_name == "back" else (back, trial)
                    score = _overlap_score(trial_back, trial_front, out_w, out_h, back_img, front_img, backend=backend)
                    if score > best_score:
                        best_score = score
                        if lens_name == "back":
                            back = trial
                        else:
                            front = trial
                        improved = True
        step_deg /= 2.0
        if not improved:
            break

    return back, front, best_score


def optimize(
    back: LensCalib,
    front: LensCalib,
    back_img: np.ndarray,
    front_img: np.ndarray,
    search_res: int = 960,
    fov_range: tuple[float, float] = (188.0, 212.0),
    refine_orientation: bool = False,
    backend: str = "auto",
):
    """Search global FOV, then optionally refine per-lens orientation, at low
    resolution. Returns (back_calib, front_calib, score) with tuned
    parameters.

    refine_orientation is off by default: on top of the FOV search, the
    coordinate-descent orientation refinement costs ~35 extra low-res render
    pairs and, in practice, tends to find no improving step once the FOV is
    well-aligned (the lenses' physical mounting has little orientation error
    to correct). Enable it if the seam still looks geometrically off after
    the FOV search alone.
    """
    out_w, out_h = search_res, search_res // 2

    best_fov = _search_fov(back, front, out_w, out_h, back_img, front_img, *fov_range, backend=backend)
    back = replace(back, fov_deg=best_fov)
    front = replace(front, fov_deg=best_fov)

    if refine_orientation:
        back, front, score = _refine_orientation(back, front, out_w, out_h, back_img, front_img, backend=backend)
    else:
        score = _overlap_score(back, front, out_w, out_h, back_img, front_img, backend=backend)

    return back, front, score
