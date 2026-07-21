"""Fisheye lens projection models: ray (lens-local frame) -> source pixel coords.

Two models are supported:
  - "equidistant": r = f * theta, the common action-camera fisheye model
    (matches ffmpeg's v360 dfisheye input and is what most reverse-engineering
    notes on the X5 fall back to; used as the default here).
  - "ucm": Unified Camera Model (Mei) with mirror parameter xi, used by
    Insta360's own calibration once it's decoded from the file (phase 2).
"""
from __future__ import annotations

import numpy as np


def project_equidistant(rays_lens: np.ndarray, fov_deg: float, cx: float, cy: float, radius_px: float):
    """Project unit rays (already in lens-local frame, +Z = lens forward) to
    source pixel coordinates under the equidistant fisheye model.

    fov_deg is the *total* angular diameter of the fisheye circle (e.g. ~200
    degrees for the X5), so the maximum usable half-angle is fov_deg / 2.
    Returns (px, py, valid_mask).
    """
    half_fov_rad = np.deg2rad(fov_deg / 2.0)

    x, y, z = rays_lens[..., 0], rays_lens[..., 1], rays_lens[..., 2]
    theta = np.arccos(np.clip(z, -1.0, 1.0))
    phi = np.arctan2(y, x)

    f = radius_px / half_fov_rad
    r = f * theta

    px = cx + r * np.cos(phi)
    py = cy + r * np.sin(phi)

    valid = (theta <= half_fov_rad) & (z > -0.2)
    return px, py, valid


def project_ucm(
    rays_lens: np.ndarray,
    xi: float,
    fx: float,
    fy: float,
    cx: float,
    cy: float,
    dist_coeffs: tuple[float, ...] = (0.0, 0.0, 0.0, 0.0),
):
    """Unified Camera Model projection with radial distortion (k1..k4)."""
    x, y, z = rays_lens[..., 0], rays_lens[..., 1], rays_lens[..., 2]
    denom = z + xi
    valid_denom = denom > 1e-6

    xu = np.divide(x, denom, out=np.zeros_like(x), where=valid_denom)
    yu = np.divide(y, denom, out=np.zeros_like(y), where=valid_denom)

    k1, k2, k3, k4 = (list(dist_coeffs) + [0.0, 0.0, 0.0, 0.0])[:4]
    r2 = xu * xu + yu * yu
    r4, r6, r8 = r2 * r2, r2 * r2 * r2, r2 * r2 * r2 * r2
    radial = 1.0 + k1 * r2 + k2 * r4 + k3 * r6 + k4 * r8

    xd = xu * radial
    yd = yu * radial

    px = fx * xd + cx
    py = fy * yd + cy

    valid = valid_denom & (z > -xi + 0.05)
    return px, py, valid
