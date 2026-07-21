"""Seam-debug visualization helpers: written to disk only when the user asks
for `--debug-flow`, so quality can be judged by eye (the pixels are the user's
call, not the pipeline's)."""
from __future__ import annotations

import os
import time

import cv2
import numpy as np


class DebugSink:
    """Writes named debug images into a per-run directory. Inert if dir is None."""

    def __init__(self, base_dir: str | None):
        if base_dir is None:
            self.dir = None
            return
        stamp = time.strftime("%Y%m%d_%H%M%S")
        self.dir = os.path.join(base_dir, stamp)
        os.makedirs(self.dir, exist_ok=True)

    @property
    def enabled(self) -> bool:
        return self.dir is not None

    def write(self, name: str, image: np.ndarray) -> str | None:
        if self.dir is None:
            return None
        path = os.path.join(self.dir, name)
        cv2.imwrite(path, image)
        return path


def magnitude_heatmap(mag: np.ndarray, max_px: float) -> np.ndarray:
    """Colorize a flow-magnitude field (0..max_px -> JET) for inspection."""
    norm = np.clip(mag / max(max_px, 1e-6), 0.0, 1.0)
    u8 = (norm * 255).astype(np.uint8)
    return cv2.applyColorMap(u8, cv2.COLORMAP_JET)


def side_by_side(a: np.ndarray, b: np.ndarray, gap: int = 8) -> np.ndarray:
    """[a | b | |a-b|] stacked horizontally, for before/after seam inspection."""
    diff = cv2.absdiff(a, b)
    sep = np.full((a.shape[0], gap, 3), 255, dtype=np.uint8)
    return np.hstack([a, sep, b, sep, diff])
