#!/usr/bin/env python3
"""Topology-aware simplification + per-country split of geoBoundaries CGAZ.

CGAZ ships three global FeatureCollections (ADM0/1/2) whose adjacent
polygons share *identical* border vertices (it is clipped to a common
international boundary with gaps filled). That shared topology is exactly
what lets us draw a single divider between two countries.

The catch: ordinary per-feature Douglas-Peucker (what `ogr2ogr -simplify`
and the renderer's `simplify_px` do) decimates each polygon independently,
so a shared border becomes two slightly different polylines -> the dreaded
double line / sliver. GEOS *coverage* simplification (`shapely.coverage_
simplify`) instead simplifies each shared edge once, keeping neighbours
coincident. Validated: zero sliver area on every border tested.

We run it here, at package time, then split the result back into the
per-country `<ISO>_ADM<n>.geojson` layout the marki-map loader already
expects, so the Rust side barely changes.

  * ADM0 is simplified as one *global* coverage: inter-country borders
    must stay coincident for the continent/subregion/neighbours composites.
  * ADM1/ADM2 are simplified per country (grouped by shapeGroup): they are
    only ever drawn as single-country drill-downs, so a per-country
    coverage preserves every divider we care about at a fraction of the
    memory.

Env: SRC = raw CGAZ dir, out = destination dir.
"""

import json
import os
import shutil
import sys
from collections import defaultdict

import numpy as np
import shapely
from shapely.geometry import mapping, shape

SRC = os.environ["SRC"]
OUT = os.environ["out"]

# Per-level Douglas-Peucker tolerance in degrees. ADM0 is viewed zoomed
# out (continents), so it can be coarser; deeper levels keep more detail.
TOLERANCE = {0: 0.01, 1: 0.007, 2: 0.005}


def simplify_coverage(features, tol):
    """Coverage-simplify a list of GeoJSON features, preserving shared
    edges. Falls back to per-feature simplify if GEOS rejects the
    coverage (rare; keeps the build deterministic and total)."""
    geoms = np.array([shape(f["geometry"]) for f in features], dtype=object)
    try:
        simp = shapely.coverage_simplify(geoms, tolerance=tol, simplify_boundary=True)
    except Exception as e:  # noqa: BLE001 - degrade gracefully, never fail the build
        print(f"  coverage_simplify failed ({e}); per-feature fallback", file=sys.stderr)
        simp = [g.simplify(tol) for g in geoms]
    return [
        {"type": "Feature", "properties": f["properties"], "geometry": mapping(g)}
        for f, g in zip(features, simp)
    ]


def write_country(iso, lvl, features):
    with open(os.path.join(OUT, f"{iso}_ADM{lvl}.geojson"), "w") as fh:
        json.dump({"type": "FeatureCollection", "features": features}, fh)


def load(lvl):
    path = os.path.join(SRC, f"geoBoundariesCGAZ_ADM{lvl}.geojson")
    with open(path) as fh:
        return json.load(fh)["features"]


os.makedirs(OUT, exist_ok=True)

# ADM0 — one global coverage, then split per country.
print("ADM0: global coverage simplify")
adm0 = simplify_coverage(load(0), TOLERANCE[0])
for f in adm0:
    write_country(f["properties"]["shapeGroup"], 0, [f])
print(f"ADM0: wrote {len(adm0)} countries")

# ADM1 / ADM2 — per-country coverage.
for lvl in (1, 2):
    by_iso = defaultdict(list)
    for f in load(lvl):
        by_iso[f["properties"]["shapeGroup"]].append(f)
    print(f"ADM{lvl}: {len(by_iso)} countries")
    for iso, feats in by_iso.items():
        write_country(iso, lvl, simplify_coverage(feats, TOLERANCE[lvl]))

shutil.copy(os.path.join(SRC, "meta.csv"), os.path.join(OUT, "meta.csv"))
print("done")
