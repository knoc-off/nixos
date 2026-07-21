"""Numba-JIT fused remap kernel: ray -> rotate -> project -> pixel, computed
in a single pass per output pixel instead of the several large intermediate
float32 arrays (rays, rotated rays, px, py, valid) the NumPy path
(projection.py) allocates. This is the one stage in the pipeline where a
compiled kernel meaningfully beats vectorized NumPy, since it's memory
bandwidth bound rather than compute bound.

Falls back gracefully: remap.py only imports this module if numba is
importable, and build_lens_maps() uses the plain-NumPy path otherwise.
"""
from __future__ import annotations

import numpy as np
from numba import njit, prange

_TWO_PI = np.float32(2.0 * np.pi)
_HALF_PI = np.float32(np.pi / 2.0)


@njit(parallel=True, fastmath=True, cache=True)
def build_equidistant_maps(width, height, R, fov_deg, cx, cy, radius_px):
    """Fused equirect-pixel -> ray -> lens-frame -> equidistant-fisheye-pixel
    map builder. R maps lens-local rays into world space (row-vector
    convention: ray_lens = ray_world @ R)."""
    half_fov_rad = np.float32(np.deg2rad(fov_deg / 2.0))
    f = np.float32(radius_px) / half_fov_rad

    map_x = np.empty((height, width), dtype=np.float32)
    map_y = np.empty((height, width), dtype=np.float32)
    valid = np.empty((height, width), dtype=np.bool_)

    r00, r01, r02 = R[0, 0], R[0, 1], R[0, 2]
    r10, r11, r12 = R[1, 0], R[1, 1], R[1, 2]
    r20, r21, r22 = R[2, 0], R[2, 1], R[2, 2]

    for row in prange(height):
        v = (np.float32(row) + np.float32(0.5)) / np.float32(height)
        lat = (np.float32(0.5) - v) * np.float32(np.pi)
        cos_lat = np.cos(lat)
        y_world = -np.sin(lat)

        for col in range(width):
            u = (np.float32(col) + np.float32(0.5)) / np.float32(width)
            lon = (u - np.float32(0.5)) * _TWO_PI
            x_world = cos_lat * np.sin(lon)
            z_world = cos_lat * np.cos(lon)

            xl = x_world * r00 + y_world * r10 + z_world * r20
            yl = x_world * r01 + y_world * r11 + z_world * r21
            zl = x_world * r02 + y_world * r12 + z_world * r22

            zl_clamped = min(np.float32(1.0), max(np.float32(-1.0), zl))
            theta = np.arccos(zl_clamped)
            phi = np.arctan2(yl, xl)

            r = f * theta
            map_x[row, col] = cx + r * np.cos(phi)
            map_y[row, col] = cy + r * np.sin(phi)
            valid[row, col] = theta <= half_fov_rad and zl > np.float32(-0.2)

    return map_x, map_y, valid


@njit(parallel=True, fastmath=True, cache=True)
def build_ucm_maps(width, height, R, xi, fx, fy, cx, cy, k1, k2, k3, k4):
    """Fused equirect-pixel -> ray -> lens-frame -> UCM-fisheye-pixel map
    builder (radial distortion only, no tangential/thin-prism terms)."""
    map_x = np.empty((height, width), dtype=np.float32)
    map_y = np.empty((height, width), dtype=np.float32)
    valid = np.empty((height, width), dtype=np.bool_)

    r00, r01, r02 = R[0, 0], R[0, 1], R[0, 2]
    r10, r11, r12 = R[1, 0], R[1, 1], R[1, 2]
    r20, r21, r22 = R[2, 0], R[2, 1], R[2, 2]
    xi32 = np.float32(xi)

    for row in prange(height):
        v = (np.float32(row) + np.float32(0.5)) / np.float32(height)
        lat = (np.float32(0.5) - v) * np.float32(np.pi)
        cos_lat = np.cos(lat)
        y_world = -np.sin(lat)

        for col in range(width):
            u = (np.float32(col) + np.float32(0.5)) / np.float32(width)
            lon = (u - np.float32(0.5)) * _TWO_PI
            x_world = cos_lat * np.sin(lon)
            z_world = cos_lat * np.cos(lon)

            xl = x_world * r00 + y_world * r10 + z_world * r20
            yl = x_world * r01 + y_world * r11 + z_world * r21
            zl = x_world * r02 + y_world * r12 + z_world * r22

            denom = zl + xi32
            if denom > np.float32(1e-6):
                xu = xl / denom
                yu = yl / denom
                valid_denom = True
            else:
                xu = np.float32(0.0)
                yu = np.float32(0.0)
                valid_denom = False

            r2 = xu * xu + yu * yu
            r4 = r2 * r2
            r6 = r4 * r2
            r8 = r4 * r4
            radial = np.float32(1.0) + k1 * r2 + k2 * r4 + k3 * r6 + k4 * r8

            map_x[row, col] = fx * (xu * radial) + cx
            map_y[row, col] = fy * (yu * radial) + cy
            valid[row, col] = valid_denom and zl > (np.float32(-xi) + np.float32(0.05))

    return map_x, map_y, valid
