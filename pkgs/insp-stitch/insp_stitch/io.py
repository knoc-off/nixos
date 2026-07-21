"""Load .insp dual-fisheye photos and save equirectangular output."""
from __future__ import annotations

import cv2
import numpy as np


def load_insp(path: str) -> tuple[np.ndarray, np.ndarray]:
    """Load an Insta360 X5 .insp file and split it into (back, front) fisheye
    crops. Layout is a single JPEG, left half = back lens, right half = front
    lens, each a square crop."""
    img = cv2.imread(path, cv2.IMREAD_COLOR)
    if img is None:
        raise ValueError(f"could not read image: {path}")

    h, w = img.shape[:2]
    if w != 2 * h:
        raise ValueError(f"unexpected .insp layout: {w}x{h}, expected width == 2*height")

    back = img[:, : w // 2]
    front = img[:, w // 2 :]
    return back, front


def save_equirect(path: str, image: np.ndarray, quality: int = 95) -> None:
    ok = cv2.imwrite(path, image, [cv2.IMWRITE_JPEG_QUALITY, quality])
    if not ok:
        raise IOError(f"failed to write output image: {path}")
