"""CLI: python -m insp_stitch <input.insp> -o output.jpg [options]"""
from __future__ import annotations

import argparse
import logging
import os
import sys

from .dis import PRESETS, resolve_config
from .pipeline import stitch


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(
        prog="insp-stitch",
        description="Parallax-aware dual-fisheye stitcher for Insta360 X5 .insp photos.",
    )
    parser.add_argument("input", help="input .insp file")
    parser.add_argument("-o", "--output", required=True, help="output equirectangular JPEG path")
    parser.add_argument("-w", "--width", type=int, default=7680, help="output width (default: 7680)")
    parser.add_argument("--height", type=int, default=None, help="output height (default: width/2)")

    align_group = parser.add_mutually_exclusive_group()
    align_group.add_argument("--auto", dest="auto_align", action="store_true", default=True, help="auto-search FOV + orientation (default)")
    align_group.add_argument("--no-auto", dest="auto_align", action="store_false", help="skip auto-search, use --fov (or the default) as-is")
    parser.add_argument("--fov", type=float, default=None, help="manual total FOV in degrees, e.g. 198 (used as-is with --no-auto, or as search init otherwise)")
    parser.add_argument("--search-res", type=int, default=960, help="width used for the low-res auto-align search (default: 960)")
    parser.add_argument(
        "--refine-orientation",
        action="store_true",
        default=False,
        help="also coordinate-descend small per-lens yaw/pitch/roll after the FOV search (default: off; adds ~35 low-res render pairs and, in practice, rarely finds an improving step once FOV is aligned)",
    )

    flow_group = parser.add_mutually_exclusive_group()
    flow_group.add_argument("--flow", dest="use_flow", action="store_true", default=True, help="DIS optical-flow parallax correction at the seams (default)")
    flow_group.add_argument("--no-flow", dest="use_flow", action="store_false", help="skip optical-flow correction")
    parser.add_argument("--band", type=float, default=15.0, help="optical-flow band half-width in degrees around each seam (default: 15)")
    parser.add_argument(
        "--quality",
        choices=sorted(PRESETS),
        default="balanced",
        help="DIS flow quality preset: fast | balanced | accurate (default: balanced)",
    )
    parser.add_argument(
        "--flow-max-px",
        type=float,
        default=None,
        help="clamp on per-pixel flow correction, in output pixels (default: auto, ~3 deg of arc scaled to width)",
    )

    # Fine-grained DIS overrides on top of --quality (for the tuning harness /
    # manual experiments). Each defaults to the preset's value when omitted.
    dis_group = parser.add_argument_group("DIS flow overrides (override --quality)")
    dis_group.add_argument("--flow-finest-scale", type=int, default=None, help="DIS finestScale: 0 = most accurate/slowest, higher = coarser/faster")
    dis_group.add_argument("--flow-patch-size", type=int, default=None, help="DIS patch size (smaller tracks thin features, noisier)")
    dis_group.add_argument("--flow-patch-stride", type=int, default=None, help="DIS patch stride (smaller = denser sampling, slower)")
    dis_group.add_argument("--flow-grad-iters", type=int, default=None, help="DIS gradient-descent iterations")
    dis_group.add_argument("--flow-var-iters", type=int, default=None, help="DIS variational-refinement iterations (helps commit thin-feature displacement)")
    dis_group.add_argument("--flow-no-spatial-prop", dest="flow_spatial_prop", action="store_const", const=False, default=None, help="disable DIS spatial propagation")

    seam_group = parser.add_argument_group("seam / blend")
    seam_group.add_argument(
        "--seam",
        choices=["feather", "graphcut", "dp"],
        default="feather",
        help="overlap compositing: feather (smooth distance-transform blend) | graphcut (optimal min-cut seam, avoids ghosting) | dp (dynamic-programming seam) (default: feather)",
    )
    seam_group.add_argument("--seam-cost", choices=["color", "color_grad"], default="color", help="seam cost: color (|A-B|, routes through agreement -- default) or color_grad (prefer cutting along edges; on this rig those edges are often the parallax-disparate content, so it tends to cut through disagreement)")
    seam_group.add_argument("--seam-scale", type=int, default=1, help="run seam finding at 1/N resolution and upsample the label (default: 1 = full res)")

    parser.add_argument(
        "--backend",
        choices=["auto", "numba", "numpy"],
        default="auto",
        help="remap map-building backend: numba (fused kernel, fast) or numpy (fallback). auto picks numba if available (default: auto)",
    )

    parser.add_argument("--profile", action="store_true", help="print a nested per-stage timing + flow-metric table")
    parser.add_argument("--debug-flow", nargs="?", const="~/.cache/insp-stitch/debug", default=None, metavar="DIR", help="dump per-seam flow heatmaps + before/after overlap crops (default dir: ~/.cache/insp-stitch/debug)")
    parser.add_argument("-v", "--verbose", action="store_true", help="verbose logging (also prints per-stage timing)")

    args = parser.parse_args(argv)

    logging.basicConfig(level=logging.INFO if (args.verbose or args.profile) else logging.WARNING, format="%(message)s")

    dis_config = resolve_config(
        args.quality,
        finest_scale=args.flow_finest_scale,
        patch_size=args.flow_patch_size,
        patch_stride=args.flow_patch_stride,
        grad_iters=args.flow_grad_iters,
        var_iters=args.flow_var_iters,
        use_spatial_propagation=args.flow_spatial_prop,
    )

    debug_dir = os.path.expanduser(args.debug_flow) if args.debug_flow else None

    stitch(
        input_path=args.input,
        output_path=args.output,
        width=args.width,
        height=args.height,
        auto_align=args.auto_align,
        manual_fov=args.fov,
        refine_orientation=args.refine_orientation,
        use_flow=args.use_flow,
        flow_band_deg=args.band,
        dis_config=dis_config,
        flow_max_px=args.flow_max_px,
        seam=args.seam,
        seam_cost=args.seam_cost,
        seam_scale=args.seam_scale,
        search_res=args.search_res,
        backend=args.backend,
        profile=args.profile,
        debug_dir=debug_dir,
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
