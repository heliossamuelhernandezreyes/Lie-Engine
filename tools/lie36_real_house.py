"""LIE36: assemble an actual scanned masonry house; no synthetic facade textures.

All visual samples originate from the SHA-locked WALL04 brick and photographic
mortar captures. Only subset selection, projected footprint/support sizing
and object instancing are authored. The original source is never modified.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
import zlib
from pathlib import Path
import numpy as np

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "gpu_compute/assets/lie_wall04"
DEST = ROOT / "gpu_compute/captures/liehouse36"
SOURCE_BANK_SHA = "f6f7d9f726e909c7bfba2aff5e416d1b12d2162b07e50844f351ac273682e4da"
PANEL_X = 2.64675009727478
PANEL_Y = .6878780770301819
BUDGETS = (6000, 2300)
CELLS = ((0, 0), (1, 0), (0, 1), (1, 1), (2, 1))
KINDS = ("brick", "window", "door", "slit")

def original_samples(source: Path = SOURCE):
    catalog = json.loads((source / "catalog.json").read_text())
    raw = zlib.decompress((source / "wall_bank.zlib").read_bytes())
    if (catalog["sha256"] != SOURCE_BANK_SHA or
        len(raw) != catalog["bytes"] or
        hashlib.sha256(raw).hexdigest() != SOURCE_BANK_SHA or
        catalog["stride"] != 80 or
        catalog["wall_layout"]["brick_count"] != 96):
        raise ValueError("Source WALL04 authenticity check failed")
    hero = catalog["masters"]["real_scan_wall"]["levels"][0]
    return np.frombuffer(raw, dtype="<f4").reshape(-1, 20)[hero["start"]:hero["start"]+hero["count"]], catalog

def aperture(kind: str, a: np.ndarray) -> np.ndarray:
    # Unchanged sampled points are excluded throughout their full depth;
    # no fake black rectangle, texture transparency or painted openings.
    x, y = a[:, 0], a[:, 1]
    if kind == "brick":
        return np.ones(len(a), dtype=bool)
    if kind == "window":
        return (np.abs(x) > .56) | (np.abs(y) > .275)
    if kind == "door":
        return np.abs(x) > .52
    if kind == "slit":
        return np.abs(x) > .15
    raise ValueError(kind)

def select_strata(candidates: np.ndarray, count: int, seed: int) -> np.ndarray:
    if len(candidates) < count:
        raise ValueError("Insufficient authentic captured records")
    rng = np.random.default_rng(seed)
    x = np.clip(np.floor((candidates[:, 0] + 1.40) / .035), 0, 99).astype(np.int64)
    y = np.clip(np.floor((candidates[:, 1] + .42) / .035), 0, 39).astype(np.int64)
    axis = np.argmax(np.abs(candidates[:, 4:7]), axis=1)
    facing = (np.take_along_axis(candidates[:, 4:7], axis[:, None], axis=1)[:, 0] >= 0).astype(np.int64)
    material = (candidates[:, 9] >= 864).astype(np.int64)
    key = ((((material * 6 + axis * 2 + facing) * 40 + y) * 100) + x)
    order = rng.permutation(len(candidates))
    _, first = np.unique(key[order], return_index=True)
    chosen = order[first]
    rng.shuffle(chosen)
    if len(chosen) >= count:
        return chosen[:count]
    rest = np.setdiff1d(np.arange(len(candidates)), chosen, assume_unique=True)
    return np.concatenate([chosen, rng.choice(rest, count-len(chosen), replace=False)])

def source_face_support(records: np.ndarray) -> None:
    # Enlarged reconstruction splat footprints are explicitly an approximation,
    # not newly generated material or additional scanned geometry.
    n = np.abs(records[:, 4:7])
    axes = np.argmax(n, axis=1)
    coords = np.stack((
        np.where(axes == 0, records[:, 2], records[:, 0]),
        np.where(axes == 1, records[:, 2], records[:, 1])
    ), axis=1)
    r = records[:, 3:4] * 1.06
    records[:, 16:18] = coords - r
    records[:, 18:20] = coords + r

def plan():
    occupied = set(CELLS)
    positions = []
    layout = [
        (0, -1, math.pi, "front"), (0, 1, 0., "back"),
        (-1, 0, -math.pi/2, "left"), (1, 0, math.pi/2, "right")
    ]
    edges = []
    for x, z in CELLS:
        for dx, dz, yaw, side in layout:
            if (x+dx, z+dz) in occupied:
                continue
            edges.append((x, z, dx, dz, yaw, side))
    edges.sort(key=lambda e: (e[1], e[0], e[5]))
    for edge_id, (x, z, dx, dz, yaw, side) in enumerate(edges):
        px = (x-1)*PANEL_X + dx*PANEL_X*.5
        pz = (z-.5)*PANEL_X + dz*PANEL_X*.5
        for tier in range(8):
            kind = "brick"
            if side == "front" and (x, z) == (1, 0) and tier <= 2:
                kind = "door"  # 2.06-m true continuous doorway
            elif tier in (2, 6) and ((edge_id + tier) % 3 != 0):
                kind = "window"
            elif tier == 5 and side == "right" and x == 2:
                kind = "slit"
            positions.append(dict(master=kind, position=[px, (tier+.5)*PANEL_Y, pz],
                                  yaw=yaw, pitch=0, group="walls",
                                  owner=f"{side}:{x},{z}:{tier}"))
        # Roof parapet uses the same photographed wall master, not a fake box.
        positions.append(dict(master="brick", position=[px, 8.5*PANEL_Y, pz],
                              yaw=yaw, pitch=0, group="parapet", owner=f"parapet:{edge_id}"))
    # Five real-scan masonry deck areas, four transverse strips each.
    for x, z in CELLS:
        for strip in range(4):
            positions.append(dict(master="brick",
                                  position=[(x-1)*PANEL_X, 8*PANEL_Y+.055,
                                            (z-.5)*PANEL_X+(strip-1.5)*PANEL_Y*.95],
                                  yaw=0, pitch=-math.pi/2, group="roof",
                                  owner=f"roof:{x},{z}:{strip}"))
    positions.append(dict(master="brick",
                          position=[0, 3.50*PANEL_Y, -1.0*PANEL_X],
                          yaw=0, pitch=-math.pi/2, group="awning",
                          owner="entry-canopy"))
    if len(positions) > 128 or len(positions)*BUDGETS[0] > 750000:
        raise ValueError("House exceeds actual LIE28 GPU instance/work limits")
    if len(edges) != 10 or not any(p["master"]=="door" for p in positions):
        raise ValueError("Invalid L-shaped house architecture")
    return dict(schema="lie36-scan-house/1", footprint_cells=[list(p) for p in CELLS],
                dimensions_m=[3*PANEL_X, 9*PANEL_Y, 2*PANEL_X],
                panel_m=[PANEL_X, PANEL_Y, .12861716479063035],
                stories=2, edges=len(edges), instances=positions,
                purpose="Actual LIE source library demonstration; not an engineering simulation")

def build(destination: Path=DEST):
    src, original = original_samples()
    chunks, masters = [], {}
    cursor=0
    for k, kind in enumerate(KINDS):
        eligible=src[aperture(kind, src)]
        levels=[]
        for lod, count in enumerate(BUDGETS):
            chosen=select_strata(eligible, count, seed=36025+100*k+lod)
            picked=eligible[chosen].copy()
            picked[:, 3]=np.maximum(picked[:, 3], .020 if lod==0 else .029)
            source_face_support(picked)
            if not np.isfinite(picked).all():raise ValueError("Invalid scanned data")
            chunks.append(picked)
            levels.append(dict(start=cursor,count=len(picked)))
            cursor += len(picked)
        masters[kind]=dict(levels=levels,
            bounds_size=[PANEL_X, PANEL_Y, .12861716479063035],
            origin_offset=[0,0,0], capture_views=36, source="verified_wall04")
    raw=np.concatenate(chunks).astype("<f4",copy=False).tobytes()
    c=dict(schema=1,stride=80,sample_count=cursor,bytes=len(raw),
           sha256=hashlib.sha256(raw).hexdigest(), masters=masters,
           original_mesh_drawn=False, source_title=original["source_title"],
           source_author=original["source_author"], source_url=original["source_url"],
           license=original["license"],
           source_bank_sha256=SOURCE_BANK_SHA,
           source_brick_scan_sha256=original["source_scan_sha256"],
           photographed_mortar_source=original["wall04"]["mortar01_cc0_source_maps"],
           authentic_positions_normals_rgb_materials=True,
           derived_fields=["reconstruction splat radius","local face support","aperture omission"],
           source_texture_generated=False, roof_material="same verified scanned masonry",
           note="Finite authentic sampled surfaces; not a full dense photographic replica")
    layout=plan()
    destination=Path(destination)
    destination.mkdir(parents=True,exist_ok=True)
    (destination/"library.bin").write_bytes(raw)
    (destination/"catalog.json").write_text(json.dumps(c,indent=2)+"\n")
    (destination/"house-plan.json").write_text(json.dumps(layout,indent=2)+"\n")
    print("LIE36 REAL HOUSE",json.dumps(dict(samples=cursor,bytes=len(raw),
          source_sha256=SOURCE_BANK_SHA,masters=list(masters),
          instances=len(layout["instances"]),work=len(layout["instances"])*BUDGETS[0])),flush=True)
    return c,layout

if __name__ == "__main__":
    parser=argparse.ArgumentParser()
    parser.add_argument("--dest",type=Path,default=DEST)
    args=parser.parse_args()
    build(args.dest)
