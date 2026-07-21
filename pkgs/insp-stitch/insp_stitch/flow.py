"""DIS optical-flow based parallax correction in the two seam bands.

A single geometric calibration can only align the lenses at one depth
("infinity"). Objects closer than a few metres sit at a different apparent
angle in each lens because of the ~30mm inter-lens baseline. This module
locally warps each lens halfway toward the other within a narrow band around
each seam, absorbing that residual, depth-dependent parallax.

Each of the two seams (longitude +90 and -90 degrees) is corrected
independently with its own tight crop, so DIS flow never has to reconcile
content from both seams (and the invalid middle region between them) inside
a single smoothness-regularized field. The applied warp is feathered to zero
at the edges of its band so there's no hard boundary where the correction
stops.

Everything that governs correction quality (DIS config, clamp) is passed in,
and every seam reports objective before/after metrics so the effect of a
setting can be measured rather than guessed at.
"""
from __future__ import annotations

from dataclasses import dataclass

import cv2
import numpy as np

from .dis import DISConfig
from .profiling import NullProfiler
from .viz import DebugSink, magnitude_heatmap, side_by_side

# Correction magnitude (in degrees of arc) the clamp allows by default. Real
# near-field parallax for the X5 baseline is ~1 deg at 2 m, ~1.7 deg at 1 m, so
# a few degrees of headroom covers close objects without letting spurious flow
# at coverage edges run away. Converted to pixels against the output width.
_DEFAULT_MAX_FLOW_DEG = 3.0


def default_max_flow_px(width: int, deg: float = _DEFAULT_MAX_FLOW_DEG) -> float:
    """Clamp headroom in output pixels for a given equirect width (360 deg)."""
    return width * deg / 360.0


@dataclass
class SeamMetrics:
    name: str
    overlap_px: int
    mag_mean: float = 0.0
    mag_median: float = 0.0
    mag_p95: float = 0.0
    mag_max: float = 0.0
    clamp_frac: float = 0.0
    resid_before: float = 0.0
    resid_after: float = 0.0
    ncc_before: float = 0.0
    ncc_after: float = 0.0

    @property
    def resid_drop(self) -> float:
        """Fraction the mean photometric residual dropped (1.0 = perfect)."""
        if self.resid_before <= 1e-6:
            return 0.0
        return 1.0 - self.resid_after / self.resid_before


def _fill_invalid(image: np.ndarray, mask: np.ndarray) -> np.ndarray:
    """Fill pixels where mask==0 via inpainting so optical flow doesn't see
    hard black borders."""
    if np.all(mask > 0):
        return image
    inv = (mask == 0).astype(np.uint8) * 255
    return cv2.inpaint(image, inv, 3, cv2.INPAINT_TELEA)


def _feather_weight(diff_deg: np.ndarray, band_deg: float) -> np.ndarray:
    """Raised-cosine window: 1.0 at the seam center (diff_deg=0), 0.0 at the
    band edge (diff_deg=band_deg)."""
    t = np.clip(diff_deg / band_deg, 0.0, 1.0)
    return 0.5 * (1.0 + np.cos(np.pi * t))


def _ncc(a: np.ndarray, b: np.ndarray) -> float:
    a = a.astype(np.float64)
    b = b.astype(np.float64)
    a = a - a.mean()
    b = b - b.mean()
    denom = np.sqrt((a * a).sum() * (b * b).sum())
    if denom < 1e-6:
        return 0.0
    return float((a * b).sum() / denom)


def correct_seam(
    rendered_a: np.ndarray,
    coverage_a: np.ndarray,
    rendered_b: np.ndarray,
    coverage_b: np.ndarray,
    lon: np.ndarray,
    seam_lon_rad: float,
    band_deg: float = 15.0,
    dis_config: DISConfig | None = None,
    max_flow_px: float = 64.0,
    seam_name: str = "seam",
    debug: DebugSink | None = None,
) -> tuple[np.ndarray, np.ndarray, SeamMetrics | None]:
    """Warp rendered_a/rendered_b toward each other within band_deg of a
    single seam at seam_lon_rad. Mutates and returns (rendered_a, rendered_b,
    metrics) with that band's region flow-corrected. metrics is None when the
    seam is skipped for lack of overlap."""
    dis_config = dis_config or DISConfig()

    diff_rad = np.abs(lon - seam_lon_rad)
    # Longitude wraps at +-pi; also check the wrapped distance.
    diff_rad = np.minimum(diff_rad, 2 * np.pi - diff_rad)
    band = np.deg2rad(band_deg)
    in_band = diff_rad < band
    both_valid = in_band & (coverage_a > 0) & (coverage_b > 0)
    overlap_px = int(both_valid.sum())
    if overlap_px < 200:
        return rendered_a, rendered_b, None

    ys, xs = np.where(in_band)
    y0, y1 = ys.min(), ys.max() + 1
    x0, x1 = xs.min(), xs.max() + 1

    crop_a = rendered_a[y0:y1, x0:x1]
    crop_b = rendered_b[y0:y1, x0:x1]
    cov_a = coverage_a[y0:y1, x0:x1]
    cov_b = coverage_b[y0:y1, x0:x1]
    diff_deg_crop = np.rad2deg(diff_rad[y0:y1, x0:x1])
    both_valid_crop = both_valid[y0:y1, x0:x1]

    filled_a = _fill_invalid(crop_a, cov_a)
    filled_b = _fill_invalid(crop_b, cov_b)

    gray_a = cv2.cvtColor(filled_a, cv2.COLOR_BGR2GRAY)
    gray_b = cv2.cvtColor(filled_b, cv2.COLOR_BGR2GRAY)

    dis = dis_config.build()
    flow = dis.calc(gray_a, gray_b, None)  # displacement a -> b, shape (h, w, 2)

    h, w = flow.shape[:2]
    grid_x, grid_y = np.meshgrid(np.arange(w, dtype=np.float32), np.arange(h, dtype=np.float32))

    # Clamp flow magnitude to suppress spurious warps from inpainted coverage
    # edges. max_flow_px sets how much genuine near-field parallax we allow to
    # be corrected before assuming the flow is spurious.
    mag = np.sqrt(flow[..., 0] ** 2 + flow[..., 1] ** 2)
    clamp_scale = np.minimum(1.0, max_flow_px / np.maximum(mag, 1e-6))

    # Feather the correction to zero at the band edges so the warped region
    # blends smoothly into the untouched single-lens content beyond it.
    feather = _feather_weight(diff_deg_crop, band_deg).astype(np.float32)
    total_scale = clamp_scale * feather

    fx = flow[..., 0] * total_scale
    fy = flow[..., 1] * total_scale

    half_flow_x = 0.5 * fx
    half_flow_y = 0.5 * fy

    # Backward maps (cv2.remap): pull A and B toward the midpoint so matching
    # features converge. A[p] ~ B[p+flow], so A samples at grid-half*flow, B at grid+half*flow.
    map_a_x = grid_x - half_flow_x
    map_a_y = grid_y - half_flow_y
    map_b_x = grid_x + half_flow_x
    map_b_y = grid_y + half_flow_y

    warped_a = cv2.remap(filled_a, map_a_x, map_a_y, interpolation=cv2.INTER_LINEAR, borderMode=cv2.BORDER_REPLICATE)
    warped_b = cv2.remap(filled_b, map_b_x, map_b_y, interpolation=cv2.INTER_LINEAR, borderMode=cv2.BORDER_REPLICATE)

    # -- objective metrics: how much did the warp actually reduce mismatch? ---
    ov = both_valid_crop
    mag_ov = mag[ov]
    metrics = SeamMetrics(
        name=seam_name,
        overlap_px=overlap_px,
        mag_mean=float(mag_ov.mean()),
        mag_median=float(np.median(mag_ov)),
        mag_p95=float(np.percentile(mag_ov, 95)),
        mag_max=float(mag_ov.max()),
        clamp_frac=float((mag_ov > max_flow_px).mean()),
    )
    warped_gray_a = cv2.cvtColor(warped_a, cv2.COLOR_BGR2GRAY)
    warped_gray_b = cv2.cvtColor(warped_b, cv2.COLOR_BGR2GRAY)
    ga, gb = gray_a[ov].astype(np.float64), gray_b[ov].astype(np.float64)
    wa, wb = warped_gray_a[ov].astype(np.float64), warped_gray_b[ov].astype(np.float64)
    metrics.resid_before = float(np.abs(ga - gb).mean())
    metrics.resid_after = float(np.abs(wa - wb).mean())
    metrics.ncc_before = _ncc(gray_a[ov], gray_b[ov])
    metrics.ncc_after = _ncc(warped_gray_a[ov], warped_gray_b[ov])

    if debug is not None and debug.enabled:
        debug.write(f"{seam_name}_mag.png", magnitude_heatmap(mag, max_flow_px))
        debug.write(f"{seam_name}_before.png", side_by_side(filled_a, filled_b))
        debug.write(f"{seam_name}_after.png", side_by_side(warped_a, warped_b))

    crop_a[both_valid_crop] = warped_a[both_valid_crop]
    crop_b[both_valid_crop] = warped_b[both_valid_crop]

    rendered_a[y0:y1, x0:x1] = crop_a
    rendered_b[y0:y1, x0:x1] = crop_b
    return rendered_a, rendered_b, metrics


def correct_seams(
    rendered_back,
    coverage_back,
    rendered_front,
    coverage_front,
    lon,
    band_deg: float = 15.0,
    dis_config: DISConfig | None = None,
    max_flow_px: float = 64.0,
    debug: DebugSink | None = None,
    profiler=None,
):
    """Apply optical-flow correction independently at both seams (longitude
    +90 and -90 degrees). Returns (rendered_back, rendered_front, [SeamMetrics])."""
    prof = profiler or NullProfiler()
    metrics: list[SeamMetrics] = []
    for name, seam_lon_rad in (("seam_pos90", np.pi / 2.0), ("seam_neg90", -np.pi / 2.0)):
        with prof.span(name):
            _, _, m = correct_seam(
                rendered_back,
                coverage_back,
                rendered_front,
                coverage_front,
                lon,
                seam_lon_rad,
                band_deg,
                dis_config=dis_config,
                max_flow_px=max_flow_px,
                seam_name=name,
                debug=debug,
            )
        if m is not None:
            prof.metric("overlap_px", m.overlap_px)
            prof.metric("mag_mean/median/p95/max", f"{m.mag_mean:.1f}/{m.mag_median:.1f}/{m.mag_p95:.1f}/{m.mag_max:.1f}", " px")
            prof.metric("clamp_frac", 100.0 * m.clamp_frac, "%")
            prof.metric("resid before->after", f"{m.resid_before:.2f}->{m.resid_after:.2f} ({100.0 * m.resid_drop:.0f}% drop)")
            prof.metric("ncc before->after", f"{m.ncc_before:.3f}->{m.ncc_after:.3f}")
            metrics.append(m)
    return rendered_back, rendered_front, metrics
