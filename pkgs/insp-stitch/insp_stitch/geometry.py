"""Ray <-> equirectangular pixel mapping and lens-orientation rotations.

World/camera convention (matches the reference insv-stitch notes):
  X = right, Y = down, Z = forward.
Longitude 0 = forward (front lens optical axis), longitude +-180 = backward
(back lens optical axis). Latitude +90 = straight up, -90 = straight down.
"""
from __future__ import annotations

import functools

import numpy as np
from scipy.spatial.transform import Rotation


def equirect_rays(width: int, height: int) -> np.ndarray:
    """Return a (height, width, 3) array of unit world-space rays, one per
    output equirectangular pixel."""
    xs = (np.arange(width, dtype=np.float32) + 0.5) / width
    ys = (np.arange(height, dtype=np.float32) + 0.5) / height

    lon = (xs - 0.5) * np.float32(2.0 * np.pi)  # [-pi, pi), 0 = forward
    lat = (np.float32(0.5) - ys) * np.float32(np.pi)  # [-pi/2, pi/2], +pi/2 = up

    lon_grid, lat_grid = np.meshgrid(lon, lat)

    cos_lat = np.cos(lat_grid)
    x = cos_lat * np.sin(lon_grid)
    y = -np.sin(lat_grid)
    z = cos_lat * np.cos(lon_grid)

    return np.stack([x, y, z], axis=-1).astype(np.float32)


def longitude_of_rays(rays: np.ndarray) -> np.ndarray:
    """Longitude (radians, [-pi, pi]) of world rays shaped (..., 3)."""
    return np.arctan2(rays[..., 0], rays[..., 2])


def longitude_grid(width: int, height: int) -> np.ndarray:
    """Cheap (height, width) longitude array as a broadcast read-only view
    (longitude only depends on column), avoiding building the full 3D rays
    array just to derive it."""
    xs = (np.arange(width, dtype=np.float32) + 0.5) / width
    lon = (xs - np.float32(0.5)) * np.float32(2.0 * np.pi)
    view = np.broadcast_to(lon, (height, width))
    return view


@functools.lru_cache(maxsize=8)
def cached_rays_and_longitude(width: int, height: int):
    """Cached (rays, longitude) for a given output resolution. Reused heavily
    during align.py's low-res search and again at full-res render, instead of
    recomputing the same grid dozens of times. Callers must not mutate the
    returned arrays in place."""
    rays = equirect_rays(width, height)
    lon = longitude_of_rays(rays)
    lon.setflags(write=False)
    rays.setflags(write=False)
    return rays, lon


def lens_rotation_matrix(yaw_deg: float, pitch_deg: float, roll_deg: float) -> np.ndarray:
    """Rotation that maps a lens-local forward-axis ray into world space.

    yaw: rotation about the vertical (Y) axis, 0 = forward, 180 = backward.
    pitch: rotation about the lens's local X (left-right) axis.
    roll: rotation about the lens's local Z (forward) axis.
    """
    r = Rotation.from_euler("YXZ", [yaw_deg, pitch_deg, roll_deg], degrees=True).as_matrix()
    return r.astype(np.float32)


def world_rays_to_lens_frame(rays: np.ndarray, lens_rotation: np.ndarray) -> np.ndarray:
    """Rotate (..., 3) world rays into a lens's local frame."""
    return rays @ lens_rotation
