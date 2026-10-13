"""Restore immutable authentic LIE-WALL-03 scanned samples and RGB mortar nodes.

Requires no model download, Blender or mesh rasterization at runtime. Original
source CC BY attribution and every SHA-256 layer are checked before extraction.
"""
from __future__ import annotations

import hashlib
import json
from pathlib import Path
import zlib

ROOT=Path(__file__).resolve().parents[1]
SRC=ROOT/"gpu_compute/assets/lie_wall03"
DST=ROOT/"gpu_compute/captures/liewall03"
BRICK=ROOT/"gpu_compute/assets/lie_brick02/catalog.json"


def restore(src: Path=SRC,dest: Path=DST) -> dict:
    manifest=json.loads((src/"catalog.json").read_text(encoding="utf-8"))
    source=json.loads(BRICK.read_text(encoding="utf-8"))
    prov=json.loads((src/"source_provenance.json").read_text(encoding="utf-8"))
    model_bytes=(src/"light-model.json").read_bytes()
    model=json.loads(model_bytes)
    compressed=(src/"wall_bank.zlib").read_bytes()
    raw=zlib.decompress(compressed)
    if manifest.get("schema")!=1 or manifest.get("stride")!=80:
        raise ValueError("Unexpected LIE-WALL03 source sample byte ABI")
    if len(raw)!=manifest.get("bytes") or len(raw)!=manifest.get("sample_count",0)*80:
        raise ValueError("Truncated/invalid immutable wall visual samples")
    if hashlib.sha256(raw).hexdigest()!=manifest.get("sha256"):
        raise ValueError("Visual sample bank failed SHA-256")
    if manifest.get("source_master_sha256")!=source.get("sha256") or manifest.get("source_scan_sha256")!=source.get("source_sha256"):
        raise ValueError("Historical 500K-triangle source identity mismatch")
    if prov.get("expected_sha256")!=source.get("source_sha256") or prov.get("license")!="CC BY 4.0":
        raise ValueError("Original Centre-of-Archaeology license/provenance mismatch")
    if hashlib.sha256(model_bytes).hexdigest()!=manifest["lighting"]["sha256"]:
        raise ValueError("Original LIE11 encoded light JSON SHA mismatch")
    if manifest.get("source_original_triangles")!=500000 or manifest.get("original_meshes_drawn") is not False:
        raise ValueError("Source scan must not be represented by visible GLB triangles")
    if manifest.get("wall_layout",{}).get("brick_count")!=96 or manifest.get("collision",{}).get("spatial_envelope_count")!=1:
        raise ValueError("LIE spatial master must use exactly one coarse box")
    if manifest["lighting"]["node_count"]!=872 or manifest["lighting"]["mortar_nodes"]!=8:
        raise ValueError("Invalid 872-node LIE11 node code mapping")
    if len(model.get("patches",[]))!=872 or len(model.get("direct_shadow_boxes",[]))!=96:
        raise ValueError("Missing original LIE11 ray visibility nodes")
    if abs(float(manifest["wall_layout"]["mortar_recess_m"])-.0035)>1e-6:
        raise ValueError("Mortar must stay behind genuine scan and outside light proxy")
    joints=manifest["wall_layout"]["mortar_shader_layout"]
    if not joints.get("procedural_joint_surface_only") or joints.get("rows")!=8 or joints.get("columns")!=12:
        raise ValueError("Invalid visible joint stencil dimensions")
    levels=manifest["masters"]["real_scan_wall"]["levels"]
    if len(levels)!=3 or sum(int(v["count"]) for v in levels)!=manifest["sample_count"]:
        raise ValueError("LOD counts corrupt")
    if any(int(v["start"])!=sum(int(x["count"]) for x in levels[:i]) for i,v in enumerate(levels)):
        raise ValueError("LOD ranges noncontiguous")
    dest.mkdir(parents=True,exist_ok=True)
    (dest/"library.bin").write_bytes(raw)
    (dest/"catalog.json").write_text(json.dumps(manifest,indent=2)+"\n",encoding="utf-8")
    (dest/"light-model.json").write_bytes(model_bytes)
    print("RESTORED REAL LIE-WALL03",manifest["sample_count"],"samples",
          len(model["patches"]),"real GPU RGB codes; 1 spatial box; SHA",manifest["sha256"],flush=True)
    return manifest


if __name__=="__main__":
    restore()
