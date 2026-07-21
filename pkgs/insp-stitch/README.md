# insp-stitch

Parallax-aware dual-fisheye stitcher for Insta360 X5 `.insp` photos
(11904x5952 JPEG, back lens left half / front lens right half). Produces an
equirectangular JPEG without relying on a single fixed FOV.

Currently a dev-shell-only tool (plain modular Python scripts, no installed
CLI yet — see `default.nix`).

## Why not just pick a good ffmpeg `ih_fov`/`iv_fov`?

The two lenses are ~30mm apart. A single global FOV can only make the two
hemispheres agree at one distance: tune it for a far wall and near objects
ghost at the seam; tune it for near objects and the far wall misaligns. This
tool separates the two problems:

1. **Geometry search** (`align.py`) finds the FOV + small per-lens
   yaw/pitch/roll that best aligns the *far-field* content in the two overlap
   bands (maximizes NCC) — an automated replacement for manually guessing
   `ih_fov`/`iv_fov`.
2. **Optical flow** (`flow.py`) then locally warps each lens halfway toward
   the other within a band around each seam, absorbing the *remaining*,
   depth-dependent parallax that no single global geometry can fix.
3. **Blending** (`blend.py`) composites with distance-transform coverage
   weighting and symmetric gain harmonization so any leftover mismatch is
   feathered rather than a hard seam.

## Usage

```
nix develop .#insp-stitch
python -m insp_stitch input.insp -o stitched.jpg -w 7680

# reproduce a fixed-FOV baseline (e.g. to compare against ffmpeg's v360):
python -m insp_stitch input.insp -o baseline.jpg --no-auto --fov 198 --no-flow

# skip optical flow (faster iteration on geometry only):
python -m insp_stitch input.insp -o stitched.jpg --no-flow
```

## Modules

| File | Responsibility |
|---|---|
| `io.py` | Load `.insp`, split into back/front fisheye crops; save output |
| `geometry.py` | Equirect pixel <-> 3D ray, lens orientation rotations |
| `projection.py` | Fisheye projection models (equidistant, UCM) |
| `calibration.py` | Per-lens parameters, X5 defaults |
| `remap.py` | Backward-remap tables + rendering a lens onto the equirect canvas |
| `align.py` | Auto-search FOV + orientation from image content |
| `flow.py` | DIS optical-flow parallax correction at the seams |
| `blend.py` | Coverage-weighted blend + gain harmonization |
| `trailer.py` | **Stub.** Phase 2: parse embedded Insta360 calibration instead of auto-search |
| `pipeline.py` | Orchestrates the stages above |
| `cli.py` / `__main__.py` | Command-line entry point |

## Phase 2: real calibration

`.insp` files carry an embedded Insta360 calibration trailer (`Insta360`
magic + `8888`-delimited records near EOF), but the exact record layout for
photos isn't confirmed yet (`.insv` video calibration lives in a separate
`.pb` sidecar; photos don't get one). `trailer.py` is a placeholder for
decoding it. Once implemented, it replaces `align.py`'s search for the static
geometry — `flow.py` and `blend.py` are unaffected, since they handle
parallax and compositing regardless of how the base geometry was obtained.

## Credit

Algorithm design (backward remap, UCM model, longitude x coverage-depth
blending, DIS flow in seam bands) follows the approach documented in
[BenjaminHenriksson/insv-stitch](https://github.com/BenjaminHenriksson/insv-stitch).
