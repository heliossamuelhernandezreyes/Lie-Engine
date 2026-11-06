"""CPU-only, reproducible source/representation/projection sufficiency probe.

The source oracle is an analytical surface. The representation oracle intersects
finite captured tangent patches by ray (pull). The independent consumer projects
those patches to pixels (push). This is NOT a run of LIE's GPU shader and does not
measure phone performance. Captures are deliberately controlled fixtures, not
real Blender/Android assets; their purpose is to distinguish causes of error.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import numpy as np

SIDE = 160
STEP = 0.25
HALF = STEP / 2
TOLERANCE_M = 0.005


def grid(side: int = SIDE):
    coords = (np.arange(side, dtype=np.float64) + .5) * 2 / side - 1
    return np.meshgrid(coords, coords)


def source(kind: str, x, y):
    """Independent front-surface ray oracle, +Z orthographic camera."""
    if kind == "wall_hole":
        visible = (np.abs(x) <= 1) & (np.abs(y) <= 1) & ~((np.abs(x) < .15) & (np.abs(y) < .15))
        return visible, np.zeros_like(x, dtype=np.float64)
    if kind in ("flat", "hidden_bump"):
        visible = (np.abs(x) <= 1) & (np.abs(y) <= 1)
        z = np.zeros_like(x, dtype=np.float64)
        if kind == "hidden_bump":
            # Smooth C2 bump whose support contains no capture lattice node.
            radial = ((x - .125) ** 2 + (y - .125) ** 2) / .1**2
            z = .3 * np.maximum(1 - radial, 0)**3
        return visible, z
    if kind == "cylinder":
        radius = .65
        visible = (np.abs(x) <= radius) & (np.abs(y) <= .75)
        return visible, np.sqrt(np.maximum(radius**2 - x**2, 0))
    raise ValueError(kind)


def samples(kind: str):
    """Capture positions/normal-derived plane slopes on a coarse fixed grid.

    No source mesh is consulted at reconstruction time. Each record is
    (center_x, center_y, center_z, dz/dx, dz/dy, sample_id).
    """
    entries = []
    for j, y in enumerate(np.arange(-1., 1.0001, STEP)):
        for i, x in enumerate(np.arange(-1., 1.0001, STEP)):
            if kind == "cylinder" and abs(y) > .75: continue
            hit, zs = source(kind, np.array(x), np.array(y))
            if not bool(hit): continue
            if kind == "cylinder":
                # avoid degenerate tangent at silhouette (grid doesn't hit it)
                slope_x = -x / max(float(zs), 1e-10)
            else:
                # hidden bump has exactly zero height and slope at EVERY sample
                slope_x = 0.
            entries.append((x, y, float(zs), slope_x, 0., j*9+i))
    return np.array(entries, dtype=np.float64).reshape(-1, 6)


def representation_rays(bank, x, y):
    """Pull oracle: find first ray hit against EVERY finite planar patch.

    Independent of the reconstruction's pixel-bounding-box enumeration.
    The camera is above the surface, so maximum z is the first hit.
    """
    highest = np.full(x.shape, -np.inf, dtype=np.float64)
    owner = np.full(x.shape, -1, dtype=np.int64)
    for cx,cy,cz,sx,sy,idx in bank:
        inside = (np.abs(x - cx) <= HALF) & (np.abs(y - cy) <= HALF)
        depth = cz + sx * (x - cx) + sy * (y - cy)
        choose = inside & (depth > highest)
        highest[choose] = depth[choose]
        owner[choose] = int(idx)
    return owner >= 0, np.where(owner >= 0, highest, 0.), owner


def projected_consumer(bank, side: int = SIDE):
    """Independent CPU push raster of the same tangent-patch contract.

    Deliberately uses pixel ranges instead of the per-pixel ray enumeration.
    This is an *emulator*, NOT LIE's Vulkan implementation.
    """
    x,y = grid(side)
    highest = np.full((side, side), -np.inf, dtype=np.float64)
    owner = np.full((side, side), -1, dtype=np.int64)
    for cx,cy,cz,sx,sy,idx in bank:
        candidates_x = np.flatnonzero((x[0] >= cx-HALF) & (x[0] <= cx+HALF))
        candidates_y = np.flatnonzero((y[:,0] >= cy-HALF) & (y[:,0] <= cy+HALF))
        if not len(candidates_x) or not len(candidates_y): continue
        region = np.ix_(candidates_y, candidates_x)
        z = cz + sx*(x[region]-cx) + sy*(y[region]-cy)
        current = highest[region]
        choose = z > current
        highest[region] = np.where(choose, z, current)
        owner[region] = np.where(choose, int(idx), owner[region])
    return owner >= 0, np.where(owner >= 0, highest, 0.), owner


def errors(truth_mask, truth_z, actual_mask, actual_z, truth_ids=None, actual_ids=None):
    same = truth_mask & actual_mask
    diff = np.abs(actual_z[same] - truth_z[same])
    out = {
        "reference_hits": int(truth_mask.sum()),
        "predicted_hits": int(actual_mask.sum()),
        "missing": int((truth_mask & ~actual_mask).sum()),
        "extra": int((~truth_mask & actual_mask).sum()),
        "depth_gt_5mm": int((diff > TOLERANCE_M).sum()),
        "depth_max_m": float(diff.max()) if diff.size else 0.,
        "depth_p95_m": float(np.percentile(diff, 95)) if diff.size else 0.,
    }
    if truth_ids is not None and actual_ids is not None:
        out["owner_mismatch_on_overlap"] = int((truth_ids[same] != actual_ids[same]).sum())
    return out


def assess(kind: str, side: int = SIDE):
    x,y = grid(side)
    sm, sz = source(kind, x, y)
    bank = samples(kind)
    rm, rz, rid = representation_rays(bank, x, y)
    cm, cz, cid = projected_consumer(bank, side)
    return {
        "fixture": kind, "samples": len(bank),
        "sample_sha256": hashlib.sha256(bank.astype('<f8').tobytes()).hexdigest(),
        "source_to_representation": errors(sm, sz, rm, rz),
        "representation_to_cpu_consumer": errors(rm, rz, cm, cz, rid, cid),
    }


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--output', type=Path)
    args = parser.parse_args()
    cases = [assess(kind) for kind in ('flat','wall_hole','cylinder','hidden_bump')]
    report = {
        "schema": "lie-geometric-sufficiency-cpu-fixture/1",
        "status": "CPU analytic fixtures and independent pull/push consumers, NOT LIE GPU",
        "resolution": [SIDE,SIDE], "capture_step_m": STEP,
        "patch_half_width_m": HALF, "depth_alert_threshold_m": TOLERANCE_M,
        "source": "analytic shape/ray", "representation": "finite planar tangent patches",
        "consumer": "CPU forward projection emulator, not production LIE",
        "cases": cases,
    }
    data = json.dumps(report, indent=2, sort_keys=True, allow_nan=False) + '\n'
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(data)
    print(data)


if __name__ == '__main__': main()
