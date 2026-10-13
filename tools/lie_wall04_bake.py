"""Experimental photographed mortar -> 80-byte LIE XYZ/RGB samples, three LODs.

Never modifies LIE-WALL03's authentic scanned 96-brick bank. No visible
source meshes, new collision boxes, invented lighting, or 3D box-face textures.
G1 review is required before renderer acceptance. Unreviewed output is a
separate forensic sample-bank PROTOTYPE, not an approved game asset.
"""
from __future__ import annotations
import argparse
import hashlib
import json
import zlib
from pathlib import Path

import numpy as np
from PIL import Image
from scipy.ndimage import distance_transform_edt
from lie_wall04_edge_surface import OriginalBrickEdgeField

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_DERIVED = ROOT / "assets/material_masters/mortar/hero/real_masonry_joint/derived"
DEFAULT_WALL = ROOT / "gpu_compute/assets/lie_wall03/catalog.json"
DEFAULT_DEST = ROOT / "gpu_compute/assets/lie_mortar01"
STRIDE_BYTES = 80
SOURCE_PX_PER_M = 8192 / 2.0
LODS = (0.00120, 0.00240, 0.00360)
# Experiment A: flush, narrow mortar. The structural 8.5mm layout is not
# modified; no brick samples or physical boxes are resized.
VISIBLE_MORTAR_WIDTH_M = 0.0060    # 6mm target, independently of structural gap
EDGE_PROTECTION_M = 0.00050       # reserve 0.5mm on both visible mortar sides
MORTAR_MAX_BACK_RELIEF_M = 0.0008  # permitted microtexture behind brick face
MORTAR_MAX_FORWARD_RELIEF_M = 0.0  # never protrude above scanned front reference
MORTAR_EDGE_RECESS_M = 0.00080  # entire joint behind the nearest measured brick edges
MORTAR_EXTRA_MICRO_RELIEF_M = 0.00050  # variation retreats still farther
SPLAT_RADIUS_SCALE = 0.80
SUPPORT_SCALE = 0.51
SAFETY_M = 0.00075  # lengthwise protection near scanned brick joints
# EXPLICIT HEURISTIC: photographic displacement units are NOT calibrated mm.
RELIEF_GAIN_M = 0.0015
ORIGINAL_WALL_SHA = "fd86e723f0e6f0f4da17cab4d4ba8dbd105fe482d62b4057e99be592999ef5ba"


def readmap(path: Path) -> np.ndarray:
    with Image.open(path) as im:
        return np.array(im)


def srgb_to_linear(rgb: np.ndarray) -> np.ndarray:
    c = rgb.astype(np.float32) / 255.
    return np.where(c <= .04045, c / 12.92, ((c + .055) / 1.055) ** 2.4)


def deterministic_hash(a: int, b: int, c: int) -> int:
    x = ((a + 1) * 0x9e3779b1 ^ (b + 1) * 0x85ebca6b ^
         (c + 1) * 0xc2b2ae35) & 0xffffffff
    x ^= x >> 16
    x = x * 0x7feb352d & 0xffffffff
    x ^= x >> 15
    return x * 0x846ca68b & 0xffffffff


class Donor:
    def __init__(self, directory: Path, record: dict):
        self.kind = record["kind"]
        self.region = tuple(record["source_bbox_xyxy"])
        files = record["source_files"]
        self.color = readmap(directory / files["color"])
        self.normal = readmap(directory / files["normal_gl"])
        self.height = readmap(directory / files["height"]).astype(np.float32)
        self.roughness = readmap(directory / files["roughness"]).astype(np.float32)
        self.mask = readmap(directory / record["mask"])
        if any(a.shape[:2] != self.mask.shape for a in
               (self.color, self.normal, self.height, self.roughness)):
            raise ValueError("PBR donor maps do not share pixel registration")
        if (self.color.ndim != 3 or self.color.shape[2] < 3 or
                self.normal.ndim != 3 or self.normal.shape[2] < 3):
            raise ValueError("Expected source RGB and normal GL")
        valid = self.mask > 127
        if np.count_nonzero(valid) < 8 or np.mean(valid) > .85:
            raise ValueError("Mortar mask empty or includes excessive brick area")
        # Valid-source distance transform. A rectangular capture crop IS NOT
        # permission to sample the source brick outside an observed joint.
        dist, indices = distance_transform_edt(~valid, return_indices=True)
        self.distance = dist
        self.nearest_y, self.nearest_x = indices
        self.shape = self.mask.shape
        accepted = self.height[valid]
        self.height_base = float(np.median(accepted))
        h05, h95 = np.percentile(accepted, [5, 95])
        self.height_span = max(float(h95 - h05), 100.)
        self.color_linear = srgb_to_linear(self.color[..., :3])
        self.rough_unit = self.roughness / (65535. if self.roughness.max() > 255 else 255.)

    def extract(self, along_m: np.ndarray, across_m: np.ndarray,
                phase: int) -> tuple[np.ndarray, np.ndarray, np.ndarray, np.ndarray, np.ndarray]:
        h, w = self.shape
        u = np.mod(np.floor(along_m * SOURCE_PX_PER_M).astype(np.int32) + phase,
                   h if self.kind == "vertical" else w)
        midpoint = w // 2 if self.kind == "vertical" else h // 2
        if self.kind == "vertical":
            center = self.nearest_x[u, np.full_like(u, midpoint)]
            xx = np.clip(np.rint(center + across_m * SOURCE_PX_PER_M).astype(np.int32), 0, w-1)
            yy = u
        else:
            center = self.nearest_y[np.full_like(u, midpoint), u]
            yy = np.clip(np.rint(center - across_m * SOURCE_PX_PER_M).astype(np.int32), 0, h-1)
            xx = u
        sy, sx = self.nearest_y[yy, xx], self.nearest_x[yy, xx]
        # Maximum 14 source pixels ~= 3.4 mm from the measured donor
        # source joint. Never sample the raw donor brick surface.
        accepted = self.distance[yy, xx] <= 14.
        color = self.color_linear[sy, sx]
        n = self.normal[sy, sx, :3].astype(np.float32) / 127.5 - 1.
        n[:, 1] *= -1.
        n /= np.maximum(np.linalg.norm(n, axis=1, keepdims=True), 1e-5)
        n[:, 2] = np.maximum(n[:, 2], .15)
        n /= np.linalg.norm(n, axis=1, keepdims=True)
        dz = np.clip((self.height[sy, sx] - self.height_base) /
                     self.height_span, -1., 1.) * RELIEF_GAIN_M * .5
        rough = np.clip(self.rough_unit[sy, sx], .23, .99)
        return accepted, color, n, dz, rough


def load_donors(directory: Path) -> tuple[dict, dict[str, list[Donor]]]:
    report = json.loads((directory / "mortar-unreviewed-report.json").read_text())
    masks = json.loads((directory / "mortar-unreviewed-masked-crops.json").read_text())
    if (report["source_sha256"] != masks["source_sha256"] or
            report["material_id"] != masks["material_id"]):
        raise ValueError("Mortar/source provenance mismatch")
    if (report["source_resolution"] != "8k" or
            report["source_dimensions"] != [8192, 8192] or
            masks["physical_height_scale_verified"] or
            report["absolute_displacement_mm_verified"]):
        raise ValueError("Unrecognized photographic source scale")
    mask_by_index = {r["index"]: r for r in masks["candidates"]}
    result = {"horizontal": [], "vertical": []}
    for i, rec in enumerate(report["candidate_crops"]):
        sel = mask_by_index.get(i)
        if sel is None or sel["source_bbox_xyxy"] != rec["source_bbox_xyxy"]:
            raise ValueError("Mortar candidate and alpha mask do not agree")
        donor = Donor(directory, {**rec, "mask": sel["mask"]})
        result[rec["kind"]].append(donor)
    if min(len(result["horizontal"]), len(result["vertical"])) < 2:
        raise ValueError("G1 blocked: both photographed joint orientations required")
    return report, result


def measured_brick_front_plane(wall_catalog_path: Path, wall: dict) -> tuple[float, dict]:
    """Use ACTUAL preserved 96-brick source XYZ/normals, not the old mortar plane.

    A single mean front datum is an approximation, not guaranteed local flush
    to every individual scanned pore or edge; record this uncertainty.
    """
    original = wall_catalog_path.parent / "wall_bank.zlib"
    raw = zlib.decompress(original.read_bytes())
    if (len(raw) != int(wall["sample_count"]) * STRIDE_BYTES or
            hashlib.sha256(raw).hexdigest() != wall["sha256"]):
        raise ValueError("Original scanned brick master SHA/ABI invalid")
    samples = np.frombuffer(raw, dtype="<f4").reshape(-1, 20)
    start = wall["masters"]["real_scan_wall"]["levels"][0]
    level = samples[start["start"]:start["start"] + start["count"]]
    # Exclude all old procedural mortar records and side/back normals.
    front = level[(level[:, 9] < 864) & (level[:, 6] > .70)]
    if len(front) < 10000 or not np.isfinite(front).all():
        raise ValueError("Insufficient authentic brick front-face samples")
    z = front[:, 2]
    # The median is the *depth through the rough scanned surface*, NOT its
    # exposed face. Real render evidence showed median=0.04385m while the
    # earlier mortar plane was 0.05631m: that error buried the mortar 12.5mm
    # and produced more black joints. Use the upper tail of actual +Z-facing
    # scanned pixels as a robust flush datum, not their internal depth.
    q10, q50, q90, q975 = (float(v) for v in np.percentile(z,[10, 50, 90, 97.5]))
    plane = q975
    nominal = float(wall["wall_layout"]["mortar_shader_layout"]["mortar_plane_z_m"])
    if not (np.isfinite(plane) and .03 < plane < .09 and
            nominal - .0015 <= plane <= nominal + .009 and q975 >= q90 >= q50 >= q10):
        raise ValueError("Exposed scanned face calibration failed: do not bury mortar behind brick")
    return plane, {
        "method": "97.5th percentile Z of actual +Z-facing scanned brick samples",
        "source_front_samples": int(len(front)),
        "source_front_z_p10_m": q10,
        "source_front_z_median_m": q50,
        "source_front_z_p90_m": q90,
        "source_front_z_p975_m": q975,
        "legacy_recessed_mortar_plane_z_m": nominal,
        "local_per_brick_flush_verified": False,
    }


def sample_line(kind: str, row: int, column: int, lo: float, hi: float,
                across_center: float, spacing: float, gap: float, plane_z: float,
                donors: list[Donor],
                edge_field: OriginalBrickEdgeField | None = None) -> np.ndarray:
    # Preserve real brick dimensions: modify mortar only. Do not draw across
    # the entire original 8.5mm structural joint.
    visible_gap = min(gap, VISIBLE_MORTAR_WIDTH_M)
    half = visible_gap * .5 - EDGE_PROTECTION_M
    if visible_gap <= 2.0 * EDGE_PROTECTION_M or half <= 0 or hi <= lo:
        raise ValueError("Unsafe scanned brick/mortar clearance")
    along = np.arange(lo + spacing * .5, hi, spacing, dtype=np.float32)
    across = np.arange(-half + spacing * .5, half, spacing, dtype=np.float32)
    if len(across) == 0:
        across = np.array([0.], dtype=np.float32)
    if len(along) == 0:
        return np.zeros((0, 20), np.float32)
    aa, bb = np.meshgrid(along, across, indexing="xy")
    a, b = aa.ravel(), bb.ravel()
    seed = deterministic_hash(row, column, 0 if kind == "horizontal" else 1)
    donor = donors[seed % len(donors)]
    phase = seed % min(donor.shape[0 if kind == "vertical" else 1], 128)
    good, rgb, nrm, dz, rough = donor.extract(a - lo, b, phase)
    a, b, rgb, nrm, dz, rough = (v[good] for v in (a, b, rgb, nrm, dz, rough))
    if not len(a):
        return np.zeros((0, 20), np.float32)
    data = np.zeros((len(a), 20), dtype="<f4")
    if kind == "horizontal":
        data[:, 0] = a
        data[:, 1] = across_center + b
        extent = (lo, across_center-half, hi, across_center+half)
    else:
        data[:, 0] = across_center + b
        data[:, 1] = a
        extent = (across_center-half, lo, across_center+half, hi)
    # Normalize source photographic relief to [-0.8, 0] mm relative to the
    # MEASURED brick face. Unlike a crude clamp, this preserves both peaks
    # and valleys in the donor map without creating a flattened top half.
    unit_relief = np.clip(dz / (RELIEF_GAIN_M * .5), -1., 1.)
    backwards = -MORTAR_MAX_BACK_RELIEF_M * (.5 - .5 * unit_relief)
    backwards = np.clip(backwards, -MORTAR_MAX_BACK_RELIEF_M,
                        MORTAR_MAX_FORWARD_RELIEF_M)
    if edge_field is not None:
        local_edge_z=edge_field.face_limit(kind,row,column,data[:,0:2])
        # Photo detail always digs INWARD from *actual adjacent brick face*.
        # Using the conservative minimum of two neighbors prevents plaster
        # floating in front of the brick on a worn/recessed course.
        local_micro=-MORTAR_EXTRA_MICRO_RELIEF_M * (.5 - .5 * unit_relief)
        data[:, 2]=np.minimum(local_edge_z-MORTAR_EDGE_RECESS_M+local_micro,
                             local_edge_z-MORTAR_EDGE_RECESS_M)
        if np.any(data[:,2]>local_edge_z-MORTAR_EDGE_RECESS_M+1e-7):
            raise ValueError("Mortar projected in front of original scanned brick edge")
    else:
        # Isolated legacy unit tests only. The production bake ALWAYS supplies
        # the original-brick edge field.
        data[:, 2] = plane_z + backwards
    data[:, 3] = spacing * SPLAT_RADIUS_SCALE
    data[:, 4:7] = nrm
    data[:, 7] = 1.
    data[:, 8] = 3.
    data[:, 9] = 864 + row  # Preserve original 8 course irradiance patches.
    data[:, 10] = rough
    data[:, 11] = 0.
    data[:, 12:15] = rgb
    data[:, 15] = 1.
    # Support must stay inside the 6mm visible band and never spill into
    # source-scanned brick faces. No box-face visibility.
    data[:, 16] = np.maximum(data[:, 0] - spacing * SUPPORT_SCALE, extent[0])
    data[:, 17] = np.maximum(data[:, 1] - spacing * SUPPORT_SCALE, extent[1])
    data[:, 18] = np.minimum(data[:, 0] + spacing * SUPPORT_SCALE, extent[2])
    data[:, 19] = np.minimum(data[:, 1] + spacing * SUPPORT_SCALE, extent[3])
    return data


def bank_samples(wall: dict, donors: dict[str, list[Donor]], spacing: float,
                 brick_front_z: float | None = None,
                 edge_field: OriginalBrickEdgeField | None = None) -> np.ndarray:
    j = wall["wall_layout"]["mortar_shader_layout"]
    gap = float(wall["wall_layout"]["mortar_gap_m"])
    if (int(j["rows"]) != 8 or int(j["columns"]) != 12 or
            wall["collision"]["spatial_envelope_count"] != 1 or
            wall["lighting"]["node_count"] != 872):
        raise ValueError("Unexpected 96-brick layout, light codes or invisible box")
    w, h, px, py = (float(j[name]) for name in
                    ("brick_length_m", "brick_height_m", "pitch_x_m", "pitch_y_m"))
    ox, oy, legacy_plane = (float(j[name]) for name in
                            ("first_brick_x_m", "first_brick_y_m", "mortar_plane_z_m"))
    plane = legacy_plane if brick_front_z is None else float(brick_front_z)
    if not np.isfinite(plane):
        raise ValueError("Brick front plane is invalid")
    pieces = []
    for row in range(8):
        cy = oy + row * py
        stagger = (row % 2) * float(j["running_bond_stagger_fraction"]) * px
        for col in range(11):
            cx = ox + stagger + (col + .5) * px
            part = sample_line("vertical", row, col, cy-h*.5+SAFETY_M,
                               cy+h*.5-SAFETY_M, cx, spacing, gap, plane,
                               donors["vertical"], edge_field)
            if len(part):
                pieces.append(part)
        if row < 7:
            next_stagger = ((row + 1) % 2) * float(j["running_bond_stagger_fraction"]) * px
            minx = max(ox+stagger-w*.5, ox+next_stagger-w*.5) + SAFETY_M
            maxx = min(ox+stagger+11*px+w*.5,
                       ox+next_stagger+11*px+w*.5) - SAFETY_M
            part = sample_line("horizontal", row, 100, minx, maxx,
                               cy+py*.5, spacing, gap, plane,
                               donors["horizontal"], edge_field)
            if len(part):
                pieces.append(part)
    if not pieces:
        raise ValueError("No photographic source-backed mortar samples")
    values = np.concatenate(pieces)
    if not np.isfinite(values).all() or len(values) >= 250000:
        raise ValueError("Unbounded/invalid mortar LIE bank")
    if values.shape[1] != 20 or not np.all(values[:, 10] >= .2):
        raise ValueError("Incorrect 80-byte LIE record layout")
    return values


def bake(derived: Path, wall_catalog: Path, dest: Path,
         allow_unreviewed: bool = False) -> dict:
    report, donors = load_donors(derived)
    review = json.loads((derived / "mortar-unreviewed-masked-crops.json").read_text())
    if not allow_unreviewed and not review["g1_human_review_passed"]:
        raise ValueError("G1 human review required; experimental --allow-unreviewed only")
    wall = json.loads(wall_catalog.read_text())
    if wall["sha256"] != ORIGINAL_WALL_SHA:
        raise ValueError("Original 96-brick scanned wall bank has changed")
    if wall["original_meshes_drawn"] or wall["source_original_triangles"] != 500000:
        raise ValueError("Cannot substitute six box faces or original source polygons")
    measured_plane, front_scan = measured_brick_front_plane(wall_catalog, wall)
    # Source-based Z cap for EVERY mortar sample: no longer use this single
    # global 97.5th percentile as the surface depth.
    edge_field=OriginalBrickEdgeField(wall_catalog, wall)
    levels = []
    arrays = []
    offset = 0
    for spacing in LODS:
        bank = bank_samples(wall, donors, spacing, measured_plane, edge_field)
        arrays.append(bank)
        levels.append({"start": offset, "count": len(bank), "spacing_m": spacing})
        offset += len(bank)
    raw = np.concatenate(arrays).astype("<f4", copy=False).tobytes()
    result = {
        "schema": "lie-mortar01/experimental/1.0", "stride": STRIDE_BYTES,
        "sample_count": offset, "bytes": len(raw), "sha256": hashlib.sha256(raw).hexdigest(),
        "levels": levels, "source_material_id": report["material_id"],
        "source_sha256": report["source_sha256"], "source_license": "CC0-1.0",
        "source_kind": "photographic PBR, not individual 3D source scan",
        "source_brick_pixel_contamination_excluded_by_review": bool(review["g1_human_review_passed"]),
        "source_brick_contamination_status": (
            "reviewed" if review["g1_human_review_passed"] else "unverified_may_include_brick_pixels"),
        "photographic_joint_masks_reviewed": bool(review["g1_human_review_passed"]),
        "source_height_is_metric": False, "relative_relief_gain_m": RELIEF_GAIN_M,
        "flush_mortar_experiment": {
            "visible_mortar_width_m": VISIBLE_MORTAR_WIDTH_M,
            "structural_mortar_gap_m": float(wall["wall_layout"]["mortar_gap_m"]),
            "edge_protection_m": EDGE_PROTECTION_M,
            "radius_scale": SPLAT_RADIUS_SCALE,
            "support_scale": SUPPORT_SCALE,
            "max_back_relief_m": MORTAR_MAX_BACK_RELIEF_M,
            "min_recess_from_local_brick_edge_m": MORTAR_EDGE_RECESS_M,
            "max_extra_relief_from_local_brick_edge_m": MORTAR_EXTRA_MICRO_RELIEF_M,
            "local_brick_edge_calibration": edge_field.report(),
            "max_forward_relief_m": MORTAR_MAX_FORWARD_RELIEF_M,
            "measured_front_plane_z_m": measured_plane,
            "front_plane_source": front_scan,
            "width_6mm_in_8point5mm_leaves_open_unfilled_margin": True,
            "product_quality_accepted": False,
            "global_plane_no_longer_controls_mortar_z": True
        },
        "workshop_only_not_renderer_accepted": not review["g1_human_review_passed"],
        "lighting_node_range": [864, 871], "brick_source_wall03_sha256": wall["sha256"],
        "unchanged_brick_source_samples": True,
        "collision": {"spatial_envelope_count": 1,
                      "geometry": "unchanged WALL03 invisible spatial box"},
        "source_meshes_drawn": False, "hero_quality_accepted": False
    }
    dest.mkdir(parents=True, exist_ok=True)
    (dest / "mortar-bank.zlib").write_bytes(zlib.compress(raw, 6))
    (dest / "catalog.json").write_text(json.dumps(result, indent=2) + "\n")
    return result


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--derived", type=Path, default=DEFAULT_DERIVED)
    parser.add_argument("--wall-catalog", type=Path, default=DEFAULT_WALL)
    parser.add_argument("--output", type=Path, default=DEFAULT_DEST)
    parser.add_argument("--allow-unreviewed", action="store_true")
    args = parser.parse_args()
    print(json.dumps(bake(args.derived, args.wall_catalog, args.output,
                          args.allow_unreviewed), indent=2))
