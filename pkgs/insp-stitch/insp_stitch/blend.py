"""Compose the two rendered hemispheres into one seamless equirectangular
image: distance-transform coverage weighting, longitude preference,
symmetric per-channel gain harmonization, and multi-band (Laplacian
pyramid) blending so residual misalignment is hidden rather than exposed as
a hard seam or ghosting."""
from __future__ import annotations

import cv2
import numpy as np

_PRIMARY_DEG = 75.0
_SECONDARY_DEG = 105.0
_PYRAMID_LEVELS = 5


def longitude_preference(lon: np.ndarray) -> np.ndarray:
    """Weight in [0, 1] favoring the front lens, as a function of |longitude|.
    1.0 for |lon| < 75 deg (front-primary), 0.0 for |lon| > 105 deg
    (back-primary), linear ramp between."""
    deg = np.abs(np.rad2deg(lon))
    pref = np.clip((_SECONDARY_DEG - deg) / (_SECONDARY_DEG - _PRIMARY_DEG), 0.0, 1.0)
    return pref


def _coverage_weights(coverage_front: np.ndarray, coverage_back: np.ndarray, lon: np.ndarray):
    dist_front = cv2.distanceTransform((coverage_front > 0).astype(np.uint8), cv2.DIST_L2, 5)
    dist_back = cv2.distanceTransform((coverage_back > 0).astype(np.uint8), cv2.DIST_L2, 5)

    pref = longitude_preference(lon)
    w_front = pref * dist_front
    w_back = (1.0 - pref) * dist_back

    total = w_front + w_back
    safe = total > 1e-6
    w_front = np.where(safe, w_front / np.where(safe, total, 1.0), (dist_front > dist_back).astype(np.float32))
    w_back = 1.0 - w_front
    return w_front, w_back


def _harmonize_gain(front: np.ndarray, back: np.ndarray, w_front: np.ndarray, overlap: np.ndarray, sigma: float = 80.0, downsample: int = 16):
    """Compute a spatially-varying per-channel gain in the overlap and apply
    it symmetrically so neither lens's exposure dominates at the seam.

    The gain field is blurred at reduced resolution and upsampled back: it's
    a smooth, low-frequency correction by construction, so a full-resolution
    sigma=80 Gaussian (expensive: ~40s at 7680x3840) buys nothing over a
    16x-downsampled blur + linear upsample, which is ~1000x cheaper.

    Runs in float32 throughout (rather than float64): these are 7680x3840x3
    elementwise ops, so halving the per-element width roughly halves the
    memory-bandwidth-bound cost of this stage, with no visible precision
    loss for 8-bit output.
    """
    front_f = front.astype(np.float32)
    back_f = back.astype(np.float32)

    eps = np.float32(1.0)
    ratio = (front_f + eps) / (back_f + eps)
    ratio = np.where(overlap[..., None] > 0, ratio, np.float32(1.0)).astype(np.float32)
    ratio = np.clip(ratio, 0.2, 5.0).astype(np.float32)

    h, w = ratio.shape[:2]
    small_w = max(1, w // downsample)
    small_h = max(1, h // downsample)
    small = cv2.resize(ratio, (small_w, small_h), interpolation=cv2.INTER_AREA)
    small_sigma = max(sigma / downsample, 1.0)
    gain_small = cv2.GaussianBlur(small, (0, 0), small_sigma)
    gain = cv2.resize(gain_small, (w, h), interpolation=cv2.INTER_LINEAR)
    gain = np.clip(gain, 0.2, 5.0).astype(np.float32)

    front_corrected = front_f / np.sqrt(gain)
    back_corrected = back_f * np.sqrt(gain)

    strength = np.clip(2.0 * np.minimum(w_front, 1.0 - w_front), 0.0, 1.0).astype(np.float32)[..., None]
    front_out = front_f * (1 - strength) + front_corrected * strength
    back_out = back_f * (1 - strength) + back_corrected * strength

    return np.clip(front_out, 0, 255), np.clip(back_out, 0, 255)


def _fill_holes(image: np.ndarray, coverage: np.ndarray, other: np.ndarray, other_coverage: np.ndarray) -> np.ndarray:
    """Fill pixels invalid in `image` with `other`'s pixels where available,
    so a Laplacian pyramid doesn't bleed dark/black halos in from outside
    each lens's coverage."""
    filled = image.copy()
    holes = coverage == 0
    fillable = holes & (other_coverage > 0)
    filled[fillable] = other[fillable]

    still_holes = (coverage == 0) & (other_coverage == 0)
    if np.any(still_holes) and not np.all(still_holes):
        filled = cv2.inpaint(filled, still_holes.astype(np.uint8) * 255, 5, cv2.INPAINT_TELEA)
    return filled


def _gaussian_pyramid(image: np.ndarray, levels: int):
    pyr = [image.astype(np.float32)]
    for _ in range(levels):
        pyr.append(cv2.pyrDown(pyr[-1]))
    return pyr


def _laplacian_pyramid(image: np.ndarray, levels: int):
    gauss = _gaussian_pyramid(image, levels)
    lap = []
    for i in range(levels):
        h, w = gauss[i].shape[:2]
        up = cv2.pyrUp(gauss[i + 1], dstsize=(w, h))
        lap.append(gauss[i] - up)
    lap.append(gauss[-1])
    return lap


def _multiband_blend(front: np.ndarray, back: np.ndarray, w_front: np.ndarray, levels: int = _PYRAMID_LEVELS) -> np.ndarray:
    lap_front = _laplacian_pyramid(front.astype(np.float32), levels)
    lap_back = _laplacian_pyramid(back.astype(np.float32), levels)
    mask_pyr = _gaussian_pyramid(w_front.astype(np.float32), levels)

    blended = []
    for lf, lb, m in zip(lap_front, lap_back, mask_pyr):
        m3 = m[..., None] if lf.ndim == 3 else m
        blended.append(lf * m3 + lb * (1.0 - m3))

    result = blended[-1]
    for i in range(levels - 1, -1, -1):
        h, w = blended[i].shape[:2]
        result = cv2.pyrUp(result, dstsize=(w, h))
        result = result + blended[i]

    return np.clip(result, 0, 255).astype(np.uint8)


def compose(
    rendered_front: np.ndarray,
    coverage_front: np.ndarray,
    rendered_back: np.ndarray,
    coverage_back: np.ndarray,
    lon: np.ndarray,
    seam: str = "feather",
    seam_cost: str = "color",
    seam_scale: int = 1,
    profiler=None,
) -> np.ndarray:
    from .profiling import NullProfiler

    prof = profiler or NullProfiler()

    with prof.span("coverage_weights"):
        w_front, w_back = _coverage_weights(coverage_front, coverage_back, lon)
        overlap = (coverage_front > 0) & (coverage_back > 0)

    with prof.span("harmonize_gain"):
        front_h, back_h = _harmonize_gain(rendered_front, rendered_back, w_front, overlap)
        front_h = front_h.astype(np.uint8)
        back_h = back_h.astype(np.uint8)

    # Optimal-seam label (computed on the harmonized images so exposure
    # differences don't dominate the seam cost) replaces the smooth feather
    # weight: away from the cut it's exactly 0/1, so foreground objects come
    # wholly from one lens instead of being averaged (ghosted).
    if seam != "feather":
        from . import seam as seam_mod

        with prof.span("seam_find"):
            w_front = seam_mod.seam_wfront(
                seam, front_h, back_h, coverage_front, coverage_back, cost=seam_cost, scale=seam_scale
            )

    with prof.span("fill_holes"):
        front_filled = _fill_holes(front_h, coverage_front, back_h, coverage_back)
        back_filled = _fill_holes(back_h, coverage_back, front_h, coverage_front)

    with prof.span("multiband"):
        return _multiband_blend(front_filled, back_filled, w_front)
