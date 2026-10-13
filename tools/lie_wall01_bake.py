"""LIE-WALL-01: bake a real scanned 96-brick wall into one LIE visual master.

Source: the verified original CC-BY Stratford brick VisualSampleBank.
Appearance is *never* constructed from BoxShape3D faces. Each physical brick
contributes transformed genuine scanned samples. A separately authored recessed
mortar underlayer is documented and distinguishable from the real brick scan.

The node light model follows existing LIE11 schema exactly and is solved by
the existing GPU transport effect, not by an invented ambient shader.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "gpu_compute/captures/liebrick02"
DEST = ROOT / "gpu_compute/captures/liewall01"
COLS = 12
ROWS = 8
BRICKS = COLS * ROWS
NODES_PER_BRICK = 9  # five full faces + four real-scan front quadrants
SEED = 2102
SAMPLES_PER_BRICK = (4000, 1300, 240)
MORTAR_GRID = ((850, 260), (480, 150), (220, 70))
FACE_SIGNS = ((0, 1), (0, -1), (1, 1), (1, -1), (2, 1), (2, -1))
STRIDE = 80


def load_scan(path: Path = SOURCE) -> tuple[dict, np.ndarray]:
    meta = json.loads((path / "catalog.json").read_text(encoding="utf-8"))
    data = (path / "library.bin").read_bytes()
    if not meta.get("source_vertex_colors_used") or meta.get("source_original_triangles") != 500000:
        raise ValueError("Only the verified authentic COLOR_0 scanned brick is allowed")
    if len(data) != meta["sample_count"] * STRIDE or hashlib.sha256(data).hexdigest() != meta["sha256"]:
        raise ValueError("Source VisualSampleBank integrity mismatch")
    if meta["source_mesh_drawn"] or meta["hero_quality_accepted"]:
        raise ValueError("Unexpected source provenance/quality flags")
    return meta, np.frombuffer(data, dtype="<f4").reshape((-1, 20))


def face_indices(normal: np.ndarray) -> np.ndarray:
    axis = np.argmax(np.abs(normal), axis=-1)
    sign = np.take_along_axis(normal, axis[:, None], axis=1).reshape((-1,))
    return axis * 2 + (sign < 0).astype(np.int32)


def micro_patch_indices(original: np.ndarray) -> np.ndarray:
    """Assign real scanned COLOR_0 samples to 9 stable light patches.

    0..3: X+ X- Y+ Y-; 4: rear Z-; 5..8: Z+ quarter patches,
    by ORIGINAL scan coordinates (not by box texture or camera view).
    """
    ids = face_indices(original[:, 4:7])
    result = ids.copy()
    result[ids == 5] = 4
    front = ids == 4
    xpositive = (original[front, 0] >= 0).astype(np.int32)
    ypositive = (original[front, 1] >= 0).astype(np.int32)
    result[front] = 5 + xpositive + 2 * ypositive
    return result


def hash_unit(seed: int, row: int, col: int, channel: int) -> float:
    x = (seed * 0x9E3779B1 ^ row * 0x85EBCA77 ^
         col * 0xC2B2AE3D ^ channel * 0x27D4EB2F) & 0xFFFFFFFF
    x = (x ^ (x >> 16)) * 0x7FEB352D & 0xFFFFFFFF
    x = (x ^ (x >> 15)) * 0x846CA68B & 0xFFFFFFFF
    return ((x ^ (x >> 16)) & 0xFFFFFFFF) / 0xFFFFFFFF


def layout(dims: np.ndarray, mortar: float = .0085) -> tuple[list[dict], np.ndarray]:
    lx, hy, dz = [float(x) for x in dims]
    if not .05 < lx < .4 or not .03 < hy < .2 or not .05 < dz < .3:
        raise ValueError("Unexpected real-brick size")
    px, py = lx + mortar, hy + mortar
    items = []
    for row in range(ROWS):
        for col in range(COLS):
            stagger = px * .5 if row % 2 else 0.
            center = np.asarray(((col - (COLS - 1) * .5) * px + stagger,
                                 (row - (ROWS - 1) * .5) * py, 0.), dtype=np.float32)
            yaw = (hash_unit(SEED, row, col, 1) * 2 - 1) * math.radians(.95)
            tone = .91 + hash_unit(SEED, row, col, 2) * .16
            item = {"row": row, "column": col, "center": center.tolist(),
                    "yaw_rad": yaw, "tone": tone, "node_start": len(items) * NODES_PER_BRICK}
            items.append(item)
    footprint = np.asarray([(COLS*px + px*.5), (ROWS*py), dz], dtype=np.float64)
    return items, footprint


def support_rebuild(values: np.ndarray) -> None:
    dominant = np.argmax(np.abs(values[:, 4:7]), axis=-1)
    for axis, (u, v) in enumerate(((2, 1), (0, 2), (0, 1))):
        selected = dominant == axis
        q = values[selected][:, [u, v]]
        radius = values[selected, 3, None] * 2.
        values[selected, 16:18] = q - radius
        values[selected, 18:20] = q + radius


def transform_real_samples(original: np.ndarray, center: list[float], yaw: float,
                           tone: float, patch_start: int, radius: float) -> np.ndarray:
    values = original.copy()
    angle = float(yaw)
    c, s = math.cos(angle), math.sin(angle)
    px, py, pz = original[:, 0], original[:, 1], original[:, 2]
    values[:, 0] = c * px + s * pz + center[0]
    values[:, 1] = py + center[1]
    values[:, 2] = -s * px + c * pz + center[2]
    nx, nz = original[:, 4], original[:, 6]
    values[:, 4] = c * nx + s * nz
    values[:, 6] = -s * nx + c * nz
    values[:, 3] = np.maximum(values[:, 3], radius)
    values[:, 9] = micro_patch_indices(original) + patch_start
    values[:, 12:15] = np.clip(original[:, 12:15] * tone, 0, 1)
    values[:, 11] = 0.  # Shader obtains dynamic absorption from the *GPU patch codes*.
    support_rebuild(values)
    return values.astype("<f4")


def mortar_samples(bounds: tuple[np.ndarray, np.ndarray], dimensions: tuple[int, int],
                   node_id: int, seed: int, bricks: list[dict],
                   brick_dims: np.ndarray, gap: float = .0085) -> np.ndarray:
    """Fill ONLY physical courses/joints, NEVER overwrite real scan surfaces.

    Earlier v1 used a full recessed plane. A historic brick has strong
    negative-depth relief; a plane inside its bounding box can obscure that
    relief and visually replace whole face regions with flat grey triangles.
    This joint-mask is layout-based and leaves ALL scanned bricks exposed.
    """
    lo, hi = bounds
    w, h = dimensions
    rng = np.random.default_rng(seed)
    x = np.linspace(lo[0], hi[0], w, dtype=np.float32)
    y = np.linspace(lo[1], hi[1], h, dtype=np.float32)
    X, Y = np.meshgrid(x, y)
    flat_x = X.reshape(-1)
    flat_y = Y.reshape(-1)
    occupied = np.zeros(len(flat_x), dtype=bool)
    within_rows = np.zeros(len(flat_x), dtype=bool)
    half_x = float(brick_dims[0]) * .5
    half_y = float(brick_dims[1]) * .5
    for brick in bricks:
        cx, cy = float(brick["center"][0]), float(brick["center"][1])
        dx = np.abs(flat_x-cx)
        dy = np.abs(flat_y-cy)
        # Recessed mortar exists in gaps bordering the scanned blocks.
        within_rows |= (dx <= half_x+gap*.55) & (dy <= half_y+gap*.55)
        # Extra margin ensures mortars NEVER overpaint damaged/chipped geometry
        # that happens to recede in Z, even with grazing sample footprints.
        occupied |= (dx <= half_x+.0010) & (dy <= half_y+.0010)
    mask = within_rows & ~occupied
    n = int(mask.sum())
    if n <= 500:
        raise ValueError("Mortar joint coverage became degenerate")
    out = np.zeros((n, 20), dtype="<f4")
    out[:, 0] = flat_x[mask]
    out[:, 1] = flat_y[mask]
    out[:, 2] = hi[2] - .020 + rng.uniform(-.0007, .0007, n)
    out[:, 3] = max(float((hi[0]-lo[0])/(w-1)),
                    float((hi[1]-lo[1])/(h-1))) * .85
    out[:, 4:7] = np.array((0, 0, 1), dtype=np.float32)
    out[:, 7] = 1.
    out[:, 8] = 3.
    out[:, 9] = node_id
    out[:, 10] = .96
    noise = rng.uniform(-.022,.022,n).astype(np.float32)
    out[:, 12] = np.clip(.26+noise,.08,1)
    out[:, 13] = np.clip(.235+noise,.08,1)
    out[:, 14] = np.clip(.205+noise,.08,1)
    out[:, 15] = 1.
    support_rebuild(out)
    return out


def make_node_model(original: np.ndarray, data: list[dict],
                    bounds: tuple[np.ndarray, np.ndarray],
                    dims: np.ndarray) -> dict:
    """Sample-derived front micro-patches + geometric nonfront patches.

    Real scan NORMALS, POSITIONS and LINEAR RGB contribute to every patch.
    One source mesh is reused but each patch gets its own measured centroid.
    The 96 opaque proxies are LIGHT-VISIBILITY DATA ONLY, not collision boxes.
    """
    lx, hy, dz = [float(x) for x in dims]
    micro_ids = micro_patch_indices(original)
    areas = (hy*dz, hy*dz, lx*dz, lx*dz, lx*hy,
             lx*hy*.25, lx*hy*.25, lx*hy*.25, lx*hy*.25)
    axis_normal = [
        (1.,0.,0.),(-1.,0.,0.),(0.,1.,0.),(0.,-1.,0.),
        (0.,0.,-1.),(0.,0.,1.),(0.,0.,1.),(0.,0.,1.),(0.,0.,1.),
    ]
    means = []
    for pid in range(NODES_PER_BRICK):
        members = original[micro_ids == pid]
        if len(members) < 50:
            raise ValueError(f"Original scan lacks micro-patch {pid}: {len(members)} samples")
        src_xyz = np.asarray(members[:, :3], dtype=np.float64)
        src_normal = np.asarray(members[:, 4:7], dtype=np.float64)
        src_rgb = np.asarray(members[:, 12:15], dtype=np.float64)
        phys = np.asarray(axis_normal[pid], dtype=np.float64)
        raw = src_normal.mean(axis=0)
        raw /= max(float(np.linalg.norm(raw)), 1.e-10)
        direction = raw*.7 + phys*.3
        direction /= max(float(np.linalg.norm(direction)), 1.e-10)
        if float(np.dot(direction, phys)) < .1:
            raise ValueError("Wrong-facing sampled surface micro-patch")
        # Push outward 1.5 mm: finite patch quadrature point lies above
        # scanned material; ray occluders ignore the owner brick.
        means.append((src_xyz.mean(axis=0) + direction*.0015,
                      direction, src_rgb.mean(axis=0)))
    patches = []
    occluders = []
    for brick_idx, brick in enumerate(data):
        center = np.asarray(brick["center"], dtype=np.float64)
        yaw = float(brick["yaw_rad"])
        co, si = math.cos(yaw), math.sin(yaw)
        rotate = np.asarray([[co, 0., si],
                             [0., 1., 0.],
                             [-si, 0., co]], dtype=np.float64)
        for pid, (local, normal, rgb) in enumerate(means):
            world_pos = center + rotate @ local
            world_n = rotate @ normal
            world_n /= max(float(np.linalg.norm(world_n)), 1.e-10)
            patches.append({
                "position": world_pos.tolist(),
                "normal": world_n.tolist(),
                "area": max(float(areas[pid]), 1.e-5),
                "gray_mean": float(np.clip(rgb.max()*brick["tone"],0.,1.)),
                "material": "clay",
                "brick_id": brick_idx,
                "micro_id": pid,
                "scan_samples_in_patch": int(np.count_nonzero(micro_ids == pid)),
            })
        # Approximating the solid/clay interior with an AABB inset 2-3mm.
        # This is independent from the ONE parent spatial/collision box.
        # No 500K-triangle runtime shadows; yaw < 1 degree is approximated.
        half = np.asarray([lx*.5-.004,hy*.5-.003,dz*.5-.004],dtype=np.float64)
        if (half<=0.).any():
            raise ValueError("Brick scan too small for light proxy")
        occluders.append([(center-half).tolist(),(center+half).tolist()])
    lo, hi = bounds
    patches.append({
        "position": [float((lo[0]+hi[0])*.5),float((lo[1]+hi[1])*.5),float(hi[2]-.020)],
        "normal": [0.,0.,1.],
        "area": float((hi[0]-lo[0])*(hi[1]-lo[1])*.15),
        "gray_mean": .26, "material": "mortar", "brick_id": -1, "micro_id": 9,
    })
    # Existing LIE11 CPU symmetric bounce visibility uses a coarse wall
    # core; DIRECT visibility uses 96 GPU AABBs (new optional LIE11 extension).
    core = [[[float(lo[0]+.012),float(lo[1]+.007),-.035],
             [float(hi[0]-.012),float(hi[1]-.007),.035]]]
    all_rgb = np.asarray(original[:, 12:15], dtype=np.float64).mean(axis=0)
    color_filter = (all_rgb/max(float(all_rgb.max()),1.e-6)).tolist()
    model = {
        "schema": 1, "factor_normalization": "symmetric_local",
        "patches": patches,
        "materials": {
            "clay": {"absorption_code": 0,"tint_linear": color_filter, "radius_scale": 1.},
            "mortar": {"absorption_code": 0,"tint_linear": [1.,.92,.83], "radius_scale": 1.},
        },
        "lights": [{
            "position": [0.,float(hi[1]+.75),1.35],
            "radius": 6.0,"power_rgb":[55.,50.,46.],
        }],
        "bounces": 2,"blockers":core,"triangles":[],
        "direct_shadow_boxes":occluders,
        "direct_shadow_nodes_per_brick":NODES_PER_BRICK,
        "direct_shadow_mortar_node":BRICKS*NODES_PER_BRICK,
        "direct_shadow_method":"GPU LIE11 direct light ray / brick inset AABBs; owner excluded",
        "indirect_occlusion_method":"existing LIE11 single wall core + reciprocal conservative bounce cache",
        "light_provenance":"original LIE11 GPU RGB irradiance transport, with direct visibility extension",
    }
    return model


def canonical_light_codes(value):
    """Stable 1e-7 representation for cross-machine JSON+SHA reproducibility.

    The original FLOAT32 VisualSampleBank stays byte-for-byte authentic. Only
    the PATCH-AVERAGED precomputed node-code *metadata* is quantized; 0.1 µm
    XYZ precision is far below the spatial uncertainty of this historical
    scan. Unit normal validation remains within 1e-5.
    """
    if isinstance(value, float):
        if not math.isfinite(value):
            raise ValueError("Nonfinite finite-patch light code")
        return round(value, 7)
    if isinstance(value, list):
        return [canonical_light_codes(x) for x in value]
    if isinstance(value, dict):
        return {k: canonical_light_codes(x) for k,x in value.items()}
    return value


def build(source: Path = SOURCE, destination: Path = DEST) -> dict:
    origin, src = load_scan(source)
    dims = np.asarray(origin["source_bbox_m"], dtype=np.float32)
    bricks, _ = layout(dims)
    brick_centers = np.asarray([b["center"] for b in bricks], dtype=np.float32)
    bmin = (brick_centers.min(axis=0) - .5*dims - .002).astype(np.float32)
    bmax = (brick_centers.max(axis=0) + .5*dims + .002).astype(np.float32)
    ranges = []
    bank = []
    cursor = 0
    for lod, (samples_per_brick, mortar_shape) in enumerate(zip(SAMPLES_PER_BRICK, MORTAR_GRID)):
        level = origin["masters"]["brick_full"]["levels"][lod]
        candidates = src[level["start"]:level["start"]+level["count"]]
        if samples_per_brick > len(candidates):
            raise ValueError("Insufficient source samples for a wall brick")
        records = []
        radius = (.0052, .0093, .018)[lod]
        for index, brick in enumerate(bricks):
            r, c = brick["row"], brick["column"]
            rng = np.random.default_rng(SEED + lod*1000003 + index*7919)
            subset = candidates[rng.choice(len(candidates), samples_per_brick, replace=False)]
            records.append(transform_real_samples(subset, brick["center"], brick["yaw_rad"],
                                                  brick["tone"], brick["node_start"], radius))
        mortar = mortar_samples((bmin,bmax), mortar_shape, BRICKS*NODES_PER_BRICK, SEED + lod, bricks, dims)
        records.append(mortar)
        samples = np.concatenate(records).astype("<f4", copy=False)
        if len(samples)+cursor > 750000 or (len(samples)+cursor)*STRIDE > 64*1024*1024:
            raise ValueError("LIE sample/work/library cap exceeded")
        if not np.isfinite(samples).all():
            raise ValueError("Invalid LIE samples")
        bank.append(samples)
        ranges.append({"start": cursor, "count": len(samples)})
        cursor += len(samples)
    combined = np.concatenate(bank)
    raw = combined.tobytes()
    model = make_node_model(src[origin["masters"]["brick_full"]["levels"][0]["start"]:
                                origin["masters"]["brick_full"]["levels"][0]["start"]+
                                origin["masters"]["brick_full"]["levels"][0]["count"]],
                            bricks, (bmin, bmax), dims)
    assert len(model["patches"]) == BRICKS*NODES_PER_BRICK+1
    # Stable across NumPy SIMD/float reduction order and GitHub runners.
    model = canonical_light_codes(model)
    lighting_bytes = (json.dumps(model,indent=2,ensure_ascii=False)+"\n").encode("utf-8")
    size = (bmax-bmin+np.asarray([.005,.005,.005])).tolist()
    center = (.5*(bmin+bmax)).tolist()
    metadata = {
        "schema": 1,"stride":STRIDE,"sample_count":len(combined),
        "bytes":len(raw),"sha256":hashlib.sha256(raw).hexdigest(),
        "masters":{"real_scan_wall":{"levels":ranges,"bounds_size":size,
                    "bounds_center":center,"origin_offset":[0,0,0]}},
        "source_title":origin["source_title"],"source_author":origin["source_author"],
        "source_url":origin["source_url"],"license":origin["license"],
        "source_scan_sha256":origin["source_sha256"],"source_master_sha256":origin["sha256"],
        "source_original_triangles":origin["source_original_triangles"],
        "original_meshes_drawn":False,"source_vertex_colors_used":True,
        "wall_layout":{"rows":ROWS,"columns":COLS,"brick_count":BRICKS,
                       "bond":"running with open staggered ends","seed":SEED,"mortar_gap_m":.0085,
                       "procedural_recessed_mortar":True,"mortar_mask":"joints only, never occlude full scanned XY brick faces"},
        "lighting":{"pipeline":"LIE11 real GPU node RGB light transport -> LIE33 wall samples",
                    "node_count":len(model["patches"]),"nodes_per_brick":NODES_PER_BRICK,
                    "front_micro_patches_per_brick":4,
                    "direct_shadow_occluders":len(model["direct_shadow_boxes"]),
                    "lighting_visibility":"source-derived micro patches, inset-brick direct shadows and existing core bounce proxy",
                    "file":"light-model.json","sha256":hashlib.sha256(lighting_bytes).hexdigest(),
                    "per_pixel_shadows":False,
                    "absorption_and_color_stored_separately":True},
        "collision":{"spatial_envelope_count":1,"geometry":"one invisible BoxShape3D",
                     "collision_is_coarse":True},
        "hero_quality_accepted":False,
        "note":"LIE-WALL02: four real scan-derived front patches, per-brick direct shadows; not a 500k triangle ray tracer; photo fidelity and GPU cost unverified."
    }
    destination.mkdir(parents=True,exist_ok=True)
    (destination/"library.bin").write_bytes(raw)
    (destination/"catalog.json").write_text(json.dumps(metadata,indent=2,ensure_ascii=False)+"\n",encoding="utf-8")
    (destination/"light-model.json").write_bytes(lighting_bytes)
    print("LIE-WALL01 verified CC BY real scanned source",origin["sha256"],
          "bricks",BRICKS,"nodes",len(model["patches"]),
          "samples",len(combined),"SHA256",metadata["sha256"],flush=True)
    return metadata


if __name__ == "__main__":
    ap=argparse.ArgumentParser()
    ap.add_argument("--source",type=Path,default=SOURCE)
    ap.add_argument("--output",type=Path,default=DEST)
    args=ap.parse_args()
    build(args.source,args.output)
