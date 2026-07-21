"""Optimal-seam label finding for the blend stage.

Multiband/alpha blending *averages* the two lenses across the overlap, so any
residual parallax on a foreground object shows up as a ghost (double image).
An optimal seam instead assigns every overlap pixel to exactly one lens, with
the front/back boundary routed (via min-cut / max-flow) through regions where
the two lenses already agree -- distant background -- and detoured around
foreground objects. Each object then comes wholly from one lens: no averaging,
no ghost. A thin multiband blend across the hard cut still hides the residual
low-frequency exposure step (the enblend recipe).

We use OpenCV's stitching-detail seam finders (GraphCut / Dp), so there's no
extra dependency and the min-cut is the tested Boykov-Kolmogorov solver. The
result is a binary w_front mask fed to the same multiband blender the feather
path uses; away from the cut it's exactly 0 or 1, i.e. a single lens.
"""
from __future__ import annotations

import cv2
import numpy as np

_GRAPHCUT_COST = {"color": "COST_COLOR", "color_grad": "COST_COLOR_GRAD"}
_DP_COST = {"color": "COLOR", "color_grad": "COLOR_GRAD"}


def _run_finder(finder, front_f32, back_f32, cov_front, cov_back):
    """Call an OpenCV detail SeamFinder and return the front label as a
    boolean full-canvas mask. The finder partitions only the overlap; solo
    regions keep their coverage."""
    mask_front = (cov_front > 0).astype(np.uint8) * 255
    mask_back = (cov_back > 0).astype(np.uint8) * 255
    corners = [(0, 0), (0, 0)]
    out = finder.find([front_f32, back_f32], corners, [mask_front, mask_back])
    front_label = out[0]
    if isinstance(front_label, cv2.UMat):
        front_label = front_label.get()
    return np.asarray(front_label) > 0


def _labels(method: str, front_f32, back_f32, cov_front, cov_back, cost: str):
    if method == "graphcut":
        finder = cv2.detail_GraphCutSeamFinder(_GRAPHCUT_COST[cost])
    elif method == "dp":
        finder = cv2.detail_DpSeamFinder(_DP_COST[cost])
    else:
        raise ValueError(f"unknown seam method: {method!r}")
    return _run_finder(finder, front_f32, back_f32, cov_front, cov_back)


def seam_wfront(
    method: str,
    front: np.ndarray,
    back: np.ndarray,
    cov_front: np.ndarray,
    cov_back: np.ndarray,
    cost: str = "color",
    scale: int = 1,
) -> np.ndarray:
    """Return a binary w_front (float32, 1.0 = take front) from an optimal seam.

    scale > 1 runs the finder on a downscaled copy and upsamples the label
    (nearest): the routing survives downscale, so this is a cheap time/memory
    win. cost defaults to "color" (|A-B|), which routes the cut through where
    the two lenses already agree -- exactly what avoids ghosting. "color_grad"
    instead prefers cutting along strong edges; for this rig those edges are
    largely the parallax-disparate content itself, so it tends to route the
    seam through *disagreement*, producing a visible blurred band once
    multiband-blended. Kept available for cases where color_grad genuinely
    helps, but color is the safe default.
    """
    h, w = front.shape[:2]
    front_f = front.astype(np.float32)
    back_f = back.astype(np.float32)

    if scale > 1:
        sw, sh = max(1, w // scale), max(1, h // scale)
        fsmall = cv2.resize(front_f, (sw, sh), interpolation=cv2.INTER_AREA)
        bsmall = cv2.resize(back_f, (sw, sh), interpolation=cv2.INTER_AREA)
        cf = cv2.resize(cov_front, (sw, sh), interpolation=cv2.INTER_NEAREST)
        cb = cv2.resize(cov_back, (sw, sh), interpolation=cv2.INTER_NEAREST)
        label_small = _labels(method, fsmall, bsmall, cf, cb, cost)
        label = cv2.resize(label_small.astype(np.uint8), (w, h), interpolation=cv2.INTER_NEAREST) > 0
    else:
        label = _labels(method, front_f, back_f, cov_front, cov_back, cost)

    # Keep solo-coverage regions with their only valid lens regardless of the
    # finder (guards against the finder assigning a solo pixel to the wrong id).
    front_only = (cov_front > 0) & (cov_back == 0)
    back_only = (cov_back > 0) & (cov_front == 0)
    w_front = label.copy()
    w_front[front_only] = True
    w_front[back_only] = False
    return w_front.astype(np.float32)
