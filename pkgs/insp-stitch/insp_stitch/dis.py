"""DIS optical-flow configuration and quality presets.

OpenCV's DISOpticalFlow has a handful of knobs that materially change how well
it recovers seam parallax, especially on thin / low-texture structures (a lone
post against a plain background is the classic under-flow case). We expose them
through one dataclass + named presets so the pipeline, the CLI and the tuning
harness all build DIS the same way.

Preset baseline behaviour (OpenCV defaults for reference):
  PRESET_MEDIUM => finestScale=1, patchSize=8, patchStride=4,
                   gradientDescentIterations=25, variationalRefinementIterations=5,
                   useMeanNormalization=1, useSpatialPropagation=1
"""
from __future__ import annotations

from dataclasses import dataclass, replace

import cv2


@dataclass(frozen=True)
class DISConfig:
    finest_scale: int = 1
    patch_size: int = 8
    patch_stride: int = 4
    grad_iters: int = 25
    var_iters: int = 5
    use_spatial_propagation: bool = True
    use_mean_normalization: bool = True

    def build(self) -> "cv2.DISOpticalFlow":
        dis = cv2.DISOpticalFlow_create(cv2.DISOPTICAL_FLOW_PRESET_MEDIUM)
        dis.setFinestScale(self.finest_scale)
        dis.setPatchSize(self.patch_size)
        dis.setPatchStride(self.patch_stride)
        dis.setGradientDescentIterations(self.grad_iters)
        dis.setVariationalRefinementIterations(self.var_iters)
        dis.setUseSpatialPropagation(self.use_spatial_propagation)
        dis.setUseMeanNormalization(self.use_mean_normalization)
        return dis


# Named presets. "balanced" mirrors OpenCV PRESET_MEDIUM (the previous
# behaviour); "accurate" spends more on variational refinement + a finer scale
# to commit thin-feature displacements; "fast" trades accuracy for speed.
PRESETS: dict[str, DISConfig] = {
    "fast": DISConfig(finest_scale=2, grad_iters=12, var_iters=0, use_spatial_propagation=False),
    "balanced": DISConfig(finest_scale=1, grad_iters=25, var_iters=5),
    "accurate": DISConfig(finest_scale=0, patch_stride=3, grad_iters=50, var_iters=15),
}


def resolve_config(
    quality: str = "balanced",
    *,
    finest_scale: int | None = None,
    patch_size: int | None = None,
    patch_stride: int | None = None,
    grad_iters: int | None = None,
    var_iters: int | None = None,
    use_spatial_propagation: bool | None = None,
) -> DISConfig:
    """Start from a named preset, then apply any explicit per-field overrides."""
    cfg = PRESETS.get(quality)
    if cfg is None:
        raise ValueError(f"unknown quality preset: {quality!r} (choose from {sorted(PRESETS)})")
    overrides = {
        k: v
        for k, v in dict(
            finest_scale=finest_scale,
            patch_size=patch_size,
            patch_stride=patch_stride,
            grad_iters=grad_iters,
            var_iters=var_iters,
            use_spatial_propagation=use_spatial_propagation,
        ).items()
        if v is not None
    }
    return replace(cfg, **overrides) if overrides else cfg
