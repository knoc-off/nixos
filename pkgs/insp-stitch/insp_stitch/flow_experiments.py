"""Flow tuning lab: measure seam-parallax correction scientifically instead of
eyeballing full renders.

Two harnesses:

  synthetic  Inject a *known* displacement field into one rendered hemisphere,
             run DIS, and report endpoint error (EPE) per config. Because the
             ground truth is known exactly, this isolates DIS accuracy from
             real-scene ambiguity -- ideal for tuning patch size / iterations /
             finest-scale. It reports EPE separately inside a thin "post-like"
             bar, which is the structure that ghosts worst in practice.

  sweep      Run the real photo's seam correction across a grid of configs,
             recording the objective overlap residual (mean |front-back| before
             vs after warp) + runtime, and dumping a before/after seam crop per
             config so the numeric winner can be confirmed by eye.

Usage:
  python -m insp_stitch.flow_experiments synthetic INPUT.insp [-w 7680]
  python -m insp_stitch.flow_experiments sweep INPUT.insp -o OUTDIR [-w 7680]
"""
from __future__ import annotations

import argparse
import copy
import os
import time

import cv2
import numpy as np

from . import align, blend, flow, io, remap
from .calibration import default_x5_calib
from .dis import PRESETS, DISConfig, resolve_config
from .viz import side_by_side


# --- shared setup -----------------------------------------------------------

def _prepare(input_path: str, width: int, backend: str = "auto"):
    """Load + align + render both hemispheres once (the expensive part)."""
    height = width // 2
    back_img, front_img = io.load_insp(input_path)
    lens_size = back_img.shape[0]
    back_calib, front_calib = default_x5_calib(lens_size)
    back_calib, front_calib, _ = align.optimize(back_calib, front_calib, back_img, front_img, backend=backend)

    map_x_b, map_y_b, valid_b, lon = remap.build_lens_maps(back_calib, width, height, backend=backend)
    map_x_f, map_y_f, valid_f, _ = remap.build_lens_maps(front_calib, width, height, backend=backend)
    rendered_back, coverage_back = remap.render_lens(back_img, map_x_b, map_y_b, valid_b)
    rendered_front, coverage_front = remap.render_lens(front_img, map_x_f, map_y_f, valid_f)
    return dict(
        rendered_back=rendered_back,
        coverage_back=coverage_back,
        rendered_front=rendered_front,
        coverage_front=coverage_front,
        lon=lon,
        width=width,
    )


def _configs_to_test() -> dict[str, DISConfig]:
    """The default grid: the three presets plus targeted variations of the
    knobs most likely to fix thin-feature under-flow."""
    return {
        "fast": PRESETS["fast"],
        "balanced": PRESETS["balanced"],
        "accurate": PRESETS["accurate"],
        "balanced+finest0": resolve_config("balanced", finest_scale=0),
        "balanced+var15": resolve_config("balanced", var_iters=15),
        "balanced+patch6": resolve_config("balanced", patch_size=6, patch_stride=3),
        "accurate+patch6": resolve_config("accurate", patch_size=6),
    }


# --- synthetic ground-truth harness ----------------------------------------

def _textured_crop(scene: dict, size: int = 640) -> np.ndarray:
    """Grab a well-covered, textured window from the front hemisphere near the
    equator (front lens is fully valid and well-exposed around lon=0)."""
    front = scene["rendered_front"]
    h, w = front.shape[:2]
    cy, cx = h // 2, w // 2
    half = size // 2
    return front[cy - half : cy + half, cx - half : cx + half].copy()


def _warp_by(image: np.ndarray, fx: np.ndarray, fy: np.ndarray) -> np.ndarray:
    """Build B[q] = A[q - F] so that DIS(A, B) should recover F exactly."""
    h, w = image.shape[:2]
    gx, gy = np.meshgrid(np.arange(w, dtype=np.float32), np.arange(h, dtype=np.float32))
    return cv2.remap(image, gx - fx, gy - fy, interpolation=cv2.INTER_LINEAR, borderMode=cv2.BORDER_REFLECT)


def _epe(est: np.ndarray, gt_fx: np.ndarray, gt_fy: np.ndarray, mask: np.ndarray | None = None) -> float:
    err = np.sqrt((est[..., 0] - gt_fx) ** 2 + (est[..., 1] - gt_fy) ** 2)
    if mask is not None:
        err = err[mask]
    return float(err.mean())


def synthetic(input_path: str, width: int = 7680, shift_px: float = 20.0, bar_shift_px: float = 20.0, backend: str = "auto") -> None:
    scene = _prepare(input_path, width, backend=backend)
    crop = _textured_crop(scene)
    h, w = crop.shape[:2]
    gray_a = cv2.cvtColor(crop, cv2.COLOR_BGR2GRAY)

    # Ground-truth field 1: uniform horizontal shift (large-displacement / clamp).
    uni_fx = np.full((h, w), shift_px, np.float32)
    uni_fy = np.zeros((h, w), np.float32)
    uni_b = _warp_by(crop, uni_fx, uni_fy)

    # Ground-truth field 2: a thin vertical bar displaced (a "post" at another
    # depth) against an otherwise static background -- the ghosting case.
    bar_fx = np.zeros((h, w), np.float32)
    bw = max(6, w // 40)
    x0 = w // 2 - bw // 2
    bar_mask = np.zeros((h, w), bool)
    bar_mask[:, x0 : x0 + bw] = True
    bar_fx[bar_mask] = bar_shift_px
    bar_b = _warp_by(crop, bar_fx, np.zeros((h, w), np.float32))

    print(f"synthetic ground-truth flow test ({w}x{h} crop, uniform={shift_px}px, bar={bar_shift_px}px)")
    print(f"{'config':<20}{'uniform EPE':>13}{'bar EPE(all)':>14}{'bar EPE(in-bar)':>16}{'time':>8}")
    print("-" * 71)
    for name, cfg in _configs_to_test().items():
        dis = cfg.build()
        t = time.perf_counter()
        est_uni = dis.calc(gray_a, cv2.cvtColor(uni_b, cv2.COLOR_BGR2GRAY), None)
        est_bar = cfg.build().calc(gray_a, cv2.cvtColor(bar_b, cv2.COLOR_BGR2GRAY), None)
        dt = time.perf_counter() - t
        e_uni = _epe(est_uni, uni_fx, uni_fy)
        e_bar_all = _epe(est_bar, bar_fx, np.zeros_like(bar_fx))
        e_bar_in = _epe(est_bar, bar_fx, np.zeros_like(bar_fx), bar_mask)
        print(f"{name:<20}{e_uni:>11.2f}px{e_bar_all:>12.2f}px{e_bar_in:>14.2f}px{dt:>7.2f}s")
    print("\nlower EPE = better. 'in-bar' isolates thin-feature recovery (the ghost case).")
    print(f"a config that leaves in-bar EPE ~= {bar_shift_px} recovered nothing on the bar.")


# --- real-photo parameter sweep --------------------------------------------

def sweep(input_path: str, out_dir: str, width: int = 7680, band_deg: float = 15.0, backend: str = "auto") -> None:
    scene = _prepare(input_path, width, backend=backend)
    os.makedirs(out_dir, exist_ok=True)
    max_flow_px = flow.default_max_flow_px(width)

    rows = []
    print(f"sweep on {os.path.basename(input_path)} @ {width}px (max_flow={max_flow_px:.0f}px)")
    print(f"{'config':<20}{'resid before':>13}{'resid after':>13}{'drop':>7}{'ncc after':>11}{'time':>8}")
    print("-" * 72)
    for name, cfg in _configs_to_test().items():
        rb = scene["rendered_back"].copy()
        rf = scene["rendered_front"].copy()
        t = time.perf_counter()
        _, _, metrics = flow.correct_seams(
            rb,
            scene["coverage_back"],
            rf,
            scene["coverage_front"],
            scene["lon"],
            band_deg=band_deg,
            dis_config=cfg,
            max_flow_px=max_flow_px,
        )
        dt = time.perf_counter() - t
        if not metrics:
            print(f"{name:<20}  (no overlap at seams -- flow skipped)")
            continue
        rb_m = float(np.mean([m.resid_before for m in metrics]))
        ra_m = float(np.mean([m.resid_after for m in metrics]))
        drop = 1.0 - ra_m / rb_m if rb_m > 1e-6 else 0.0
        ncc_a = float(np.mean([m.ncc_after for m in metrics]))
        rows.append((name, rb_m, ra_m, drop, ncc_a, dt))
        print(f"{name:<20}{rb_m:>11.2f}  {ra_m:>11.2f}  {100 * drop:>5.0f}%{ncc_a:>11.3f}{dt:>7.2f}s")

        # Dump a tight before/after crop around the +90 seam for visual check.
        _dump_seam_crop(scene, rf, rb, name, out_dir)

    if rows:
        best = max(rows, key=lambda r: r[3])
        print(f"\nbest residual drop: {best[0]} ({100 * best[3]:.0f}%). crops -> {out_dir}")


def _dump_seam_crop(scene: dict, rendered_front: np.ndarray, rendered_back: np.ndarray, name: str, out_dir: str) -> None:
    """Save an overlap-band crop around the +90 seam: corrected front vs back."""
    lon = scene["lon"]
    both = (scene["coverage_front"] > 0) & (scene["coverage_back"] > 0)
    seam = (np.abs(lon - np.pi / 2.0) < np.deg2rad(6.0)) & both
    if seam.sum() < 200:
        return
    ys, xs = np.where(seam)
    y0, y1, x0, x1 = ys.min(), ys.max() + 1, xs.min(), xs.max() + 1
    crop = side_by_side(rendered_front[y0:y1, x0:x1], rendered_back[y0:y1, x0:x1])
    cv2.imwrite(os.path.join(out_dir, f"seam_pos90_{name}.png"), crop)


# --- seam-method comparison -------------------------------------------------

def _apply_flow(scene: dict, dis_config: DISConfig):
    """Flow-correct copies of the rendered hemispheres (as the pipeline does),
    so seam methods are compared on the same flow-corrected input."""
    rb = scene["rendered_back"].copy()
    rf = scene["rendered_front"].copy()
    flow.correct_seams(
        rb,
        scene["coverage_back"],
        rf,
        scene["coverage_front"],
        scene["lon"],
        dis_config=dis_config,
        max_flow_px=flow.default_max_flow_px(scene["width"]),
    )
    return rf, rb


def _seam_boundary_diff(w_front: np.ndarray, front: np.ndarray, back: np.ndarray, overlap: np.ndarray) -> float:
    """Mean |front-back| exactly on the front/back boundary pixels (a hard
    edge for graphcut/dp; the transition band for feather). This is the
    number that predicts a visible blurred band once multiband-blended: a
    seam routed through disagreement will have this high even if the wider
    ghost-peak metric looks fine."""
    if w_front.max() <= 1.0 and np.unique(w_front).size > 2:
        # feather: no hard boundary: use the transition band as a proxy.
        trans = (cv2.GaussianBlur(w_front.astype(np.float32), (0, 0), 2.0) * 255).astype(np.uint8)
        band = overlap & (trans > 8) & (trans < 247)
    else:
        b = np.zeros_like(w_front, bool)
        b[:, 1:] = w_front[:, 1:] != w_front[:, :-1]
        band = b & overlap
    if band.sum() < 50:
        band = overlap
    return float(np.abs(front[band].astype(np.float64) - back[band].astype(np.float64)).mean())


def _ghost_autocorr(gray: np.ndarray, min_lag: int = 3, max_lag: int = 40) -> float:
    """Secondary-peak ratio of the horizontal gradient autocorrelation. A
    doubled (ghosted) edge injects a bump at lag = disparity, so a higher ratio
    means more edge-doubling. Computed on a seam-band crop of the composite."""
    gx = cv2.Sobel(gray.astype(np.float32), cv2.CV_32F, 1, 0, ksize=3)
    zero = float((gx * gx).mean()) + 1e-6
    peak = 0.0
    for lag in range(min_lag, max_lag + 1):
        c = float((gx[:, :-lag] * gx[:, lag:]).mean())
        peak = max(peak, c)
    return peak / zero


def _seam_band_crop(scene: dict, image: np.ndarray, band_deg: float = 6.0):
    lon = scene["lon"]
    both = (scene["coverage_front"] > 0) & (scene["coverage_back"] > 0)
    seam = (np.abs(lon - np.pi / 2.0) < np.deg2rad(band_deg)) & both
    if seam.sum() < 200:
        return None
    ys, xs = np.where(seam)
    return image[ys.min() : ys.max() + 1, xs.min() : xs.max() + 1]


def seam_compare(input_path: str, out_dir: str, width: int = 7680, scale: int = 1, backend: str = "auto") -> None:
    scene = _prepare(input_path, width, backend=backend)
    os.makedirs(out_dir, exist_ok=True)
    rf, rb = _apply_flow(scene, PRESETS["balanced"])
    overlap = (scene["coverage_front"] > 0) & (scene["coverage_back"] > 0)

    methods = [
        ("feather", "feather", "color"),
        ("graphcut", "graphcut", "color"),
        ("graphcut_grad", "graphcut", "color_grad"),
        ("dp", "dp", "color"),
    ]
    print(f"seam comparison on {os.path.basename(input_path)} @ {width}px (flow=balanced, scale={scale})")
    print(f"{'method':<14}{'boundary diff':>14}{'ghost peak':>12}{'time':>8}")
    print("-" * 48)
    for name, seam, cost in methods:
        t = time.perf_counter()
        result = blend.compose(rf, scene["coverage_front"], rb, scene["coverage_back"], scene["lon"],
                               seam=seam, seam_cost=cost, seam_scale=scale)
        dt = time.perf_counter() - t

        # metrics use the same seam label the composite used (feather => smooth)
        if seam == "feather":
            from .blend import _coverage_weights
            w_front, _ = _coverage_weights(scene["coverage_front"], scene["coverage_back"], scene["lon"])
        else:
            from . import seam as seam_mod
            w_front = seam_mod.seam_wfront(seam, rf, rb, scene["coverage_front"], scene["coverage_back"], cost=cost, scale=scale)
        resid = _seam_boundary_diff(w_front, rf, rb, overlap)

        crop = _seam_band_crop(scene, result)
        ghost = _ghost_autocorr(cv2.cvtColor(crop, cv2.COLOR_BGR2GRAY)) if crop is not None else float("nan")
        if crop is not None:
            cv2.imwrite(os.path.join(out_dir, f"composite_seam_pos90_{name}.png"), crop)
        cv2.imwrite(os.path.join(out_dir, f"full_{name}.jpg"), result, [cv2.IMWRITE_JPEG_QUALITY, 92])
        print(f"{name:<14}{resid:>13.2f} {ghost:>11.3f}{dt:>7.2f}s")
    print(f"\nlower boundary-diff = seam runs through agreement (predicts blur-free cut).")
    print(f"lower ghost-peak = less edge-doubling. crops + full renders -> {out_dir}")


# --- entry point ------------------------------------------------------------

def main(argv=None) -> int:
    p = argparse.ArgumentParser(prog="insp-stitch-flowlab", description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = p.add_subparsers(dest="cmd", required=True)

    ps = sub.add_parser("synthetic", help="known-displacement DIS accuracy test")
    ps.add_argument("input")
    ps.add_argument("-w", "--width", type=int, default=7680)
    ps.add_argument("--shift-px", type=float, default=20.0)
    ps.add_argument("--bar-shift-px", type=float, default=20.0)
    ps.add_argument("--backend", default="auto")

    pw = sub.add_parser("sweep", help="real-photo config sweep with seam crops")
    pw.add_argument("input")
    pw.add_argument("-o", "--out-dir", default="flowlab_sweep")
    pw.add_argument("-w", "--width", type=int, default=7680)
    pw.add_argument("--band", type=float, default=15.0)
    pw.add_argument("--backend", default="auto")

    pc = sub.add_parser("seam", help="compare feather vs graphcut vs dp seams (composites + metrics)")
    pc.add_argument("input")
    pc.add_argument("-o", "--out-dir", default="flowlab_seam")
    pc.add_argument("-w", "--width", type=int, default=7680)
    pc.add_argument("--seam-scale", type=int, default=4)
    pc.add_argument("--backend", default="auto")

    args = p.parse_args(argv)
    if args.cmd == "synthetic":
        synthetic(args.input, width=args.width, shift_px=args.shift_px, bar_shift_px=args.bar_shift_px, backend=args.backend)
    elif args.cmd == "sweep":
        sweep(args.input, args.out_dir, width=args.width, band_deg=args.band, backend=args.backend)
    elif args.cmd == "seam":
        seam_compare(args.input, args.out_dir, width=args.width, scale=args.seam_scale, backend=args.backend)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
