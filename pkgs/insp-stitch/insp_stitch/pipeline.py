"""Orchestrate the full stitch: load -> geometry -> align -> render -> flow ->
blend -> save."""
from __future__ import annotations

import logging

from . import align, blend, flow, io, remap
from .calibration import default_x5_calib
from .dis import DISConfig, resolve_config
from .profiling import NullProfiler, Profiler
from .viz import DebugSink

log = logging.getLogger(__name__)


def stitch(
    input_path: str,
    output_path: str,
    width: int = 7680,
    height: int | None = None,
    auto_align: bool = True,
    manual_fov: float | None = None,
    refine_orientation: bool = False,
    use_flow: bool = True,
    flow_band_deg: float = 15.0,
    dis_config: DISConfig | None = None,
    flow_max_px: float | None = None,
    seam: str = "feather",
    seam_cost: str = "color_grad",
    seam_scale: int = 1,
    search_res: int = 960,
    backend: str = "auto",
    profile: bool = False,
    debug_dir: str | None = None,
) -> None:
    height = height or width // 2
    dis_config = dis_config or resolve_config("balanced")
    max_flow_px = flow_max_px if flow_max_px is not None else flow.default_max_flow_px(width)
    prof: Profiler = Profiler() if (profile or log.isEnabledFor(logging.INFO)) else NullProfiler()
    debug = DebugSink(debug_dir)

    with prof.span("load"):
        back_img, front_img = io.load_insp(input_path)
    lens_size = back_img.shape[0]

    back_calib, front_calib = default_x5_calib(lens_size)
    if manual_fov is not None:
        back_calib.fov_deg = manual_fov
        front_calib.fov_deg = manual_fov

    if auto_align:
        with prof.span("auto-align"):
            back_calib, front_calib, score = align.optimize(
                back_calib,
                front_calib,
                back_img,
                front_img,
                search_res=search_res,
                refine_orientation=refine_orientation,
                backend=backend,
            )
        log.info(
            "auto-align result: fov=%.2f back=(%.2f,%.2f,%.2f) front=(%.2f,%.2f,%.2f) ncc=%.4f",
            back_calib.fov_deg,
            back_calib.yaw_deg,
            back_calib.pitch_deg,
            back_calib.roll_deg,
            front_calib.yaw_deg,
            front_calib.pitch_deg,
            front_calib.roll_deg,
            score,
        )

    with prof.span("render"):
        with prof.span("build_maps"):
            map_x_b, map_y_b, valid_b, lon = remap.build_lens_maps(back_calib, width, height, backend=backend)
            map_x_f, map_y_f, valid_f, _ = remap.build_lens_maps(front_calib, width, height, backend=backend)
        with prof.span("remap"):
            rendered_back, coverage_back = remap.render_lens(back_img, map_x_b, map_y_b, valid_b)
            rendered_front, coverage_front = remap.render_lens(front_img, map_x_f, map_y_f, valid_f)

    if use_flow:
        with prof.span("flow"):
            rendered_back, rendered_front, _ = flow.correct_seams(
                rendered_back,
                coverage_back,
                rendered_front,
                coverage_front,
                lon,
                band_deg=flow_band_deg,
                dis_config=dis_config,
                max_flow_px=max_flow_px,
                debug=debug,
                profiler=prof,
            )

    with prof.span("blend"):
        result = blend.compose(
            rendered_front,
            coverage_front,
            rendered_back,
            coverage_back,
            lon,
            seam=seam,
            seam_cost=seam_cost,
            seam_scale=seam_scale,
            profiler=prof,
        )

    with prof.span("save"):
        io.save_equirect(output_path, result)

    log.info("wrote %s", output_path)
    if debug.enabled:
        log.info("debug images -> %s", debug.dir)
    if not isinstance(prof, NullProfiler):
        log.info("profile:\n%s", prof.report())
