"""Build backward-remap tables from equirectangular output pixels to a lens's
source fisheye pixels, and render a lens onto the full equirect canvas.

Two backends:
  - numba (default, if available): remap_kernel.py's fused per-pixel kernel,
    avoiding the several large intermediate float32 arrays the NumPy path
    allocates.
  - numpy: geometry.py + projection.py, vectorized but with more
    intermediate allocations. Always available; used as a fallback.
"""
from __future__ import annotations

import cv2
import numpy as np

from . import geometry, projection
from .calibration import LensCalib

try:
    from . import remap_kernel

    _HAVE_NUMBA = True
except ImportError:
    remap_kernel = None
    _HAVE_NUMBA = False


def _build_lens_maps_numpy(calib: LensCalib, out_w: int, out_h: int):
    rays_world, lon = geometry.cached_rays_and_longitude(out_w, out_h)

    R = geometry.lens_rotation_matrix(calib.yaw_deg, calib.pitch_deg, calib.roll_deg)
    rays_lens = geometry.world_rays_to_lens_frame(rays_world, R)

    if calib.model == "equidistant":
        px, py, valid = projection.project_equidistant(
            rays_lens, calib.fov_deg, calib.cx, calib.cy, calib.radius_px
        )
    elif calib.model == "ucm":
        px, py, valid = projection.project_ucm(
            rays_lens, calib.xi, calib.fx, calib.fy, calib.cx, calib.cy, calib.dist_coeffs
        )
    else:
        raise ValueError(f"unknown projection model: {calib.model}")

    map_x = px.astype(np.float32)
    map_y = py.astype(np.float32)
    return map_x, map_y, valid, lon


def _build_lens_maps_numba(calib: LensCalib, out_w: int, out_h: int):
    R = geometry.lens_rotation_matrix(calib.yaw_deg, calib.pitch_deg, calib.roll_deg)
    lon = geometry.longitude_grid(out_w, out_h)

    if calib.model == "equidistant":
        map_x, map_y, valid = remap_kernel.build_equidistant_maps(
            out_w, out_h, R, calib.fov_deg, calib.cx, calib.cy, calib.radius_px
        )
    elif calib.model == "ucm":
        k1, k2, k3, k4 = (list(calib.dist_coeffs) + [0.0, 0.0, 0.0, 0.0])[:4]
        map_x, map_y, valid = remap_kernel.build_ucm_maps(
            out_w, out_h, R, calib.xi, calib.fx, calib.fy, calib.cx, calib.cy, k1, k2, k3, k4
        )
    else:
        raise ValueError(f"unknown projection model: {calib.model}")

    return map_x, map_y, valid, lon


def build_lens_maps(calib: LensCalib, out_w: int, out_h: int, backend: str = "auto"):
    """Return (map_x, map_y, valid_mask, longitude) for a lens at a given
    output resolution. backend: "auto" (numba if available, else numpy),
    "numba", or "numpy"."""
    use_numba = backend == "numba" or (backend == "auto" and _HAVE_NUMBA)
    if use_numba:
        return _build_lens_maps_numba(calib, out_w, out_h)
    return _build_lens_maps_numpy(calib, out_w, out_h)


def render_lens(source: np.ndarray, map_x: np.ndarray, map_y: np.ndarray, valid: np.ndarray):
    """Remap a source fisheye image onto the equirect canvas defined by
    map_x/map_y. Returns (rendered_bgr, coverage_mask_uint8)."""
    rendered = cv2.remap(
        source,
        map_x,
        map_y,
        interpolation=cv2.INTER_LINEAR,
        borderMode=cv2.BORDER_CONSTANT,
        borderValue=(0, 0, 0),
    )
    h, w = source.shape[:2]
    in_bounds = (map_x >= 0) & (map_x < w - 1) & (map_y >= 0) & (map_y < h - 1)
    coverage = (valid & in_bounds).astype(np.uint8) * 255

    rendered = rendered * (coverage[..., None] > 0)
    return rendered, coverage
