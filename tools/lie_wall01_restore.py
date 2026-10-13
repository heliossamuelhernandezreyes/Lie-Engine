"""Restore exact LIE-WALL-01 immutable real-brick samples and nodal light codes.

Checks the SHA-256 of wall samples, LIE11 code model, and its genuine CC BY
heritage-brick source. The original 500k-triangle mesh is NOT loaded at runtime.
"""
from __future__ import annotations
import hashlib
import json
from pathlib import Path
import zlib

ROOT=Path(__file__).resolve().parents[1]
SOURCE=ROOT/"gpu_compute/assets/lie_wall01"
DEST=ROOT/"gpu_compute/captures/liewall01"
BRICK_META=ROOT/"gpu_compute/assets/lie_brick02/catalog.json"


def restore(source: Path=SOURCE, dest: Path=DEST) -> dict:
    cat=json.loads((source/"catalog.json").read_text(encoding="utf-8"))
    provenance=json.loads((source/"source_provenance.json").read_text(encoding="utf-8"))
    light=(source/"light-model.json").read_bytes()
    raw=zlib.decompress((source/"wall_bank.zlib").read_bytes())
    brick=json.loads(BRICK_META.read_text(encoding="utf-8"))
    if cat["schema"]!=1 or cat["stride"]!=80 or cat["original_meshes_drawn"] is not False:
        raise ValueError("Invalid LIE wall visual-sample schema")
    if cat.get("source_original_triangles")!=500000 or cat.get("source_vertex_colors_used") is not True:
        raise ValueError("A synthetic brick has replaced the real scan")
    if cat.get("source_master_sha256")!=brick.get("sha256"):
        raise ValueError("Real LIE-BRICK02 source master mismatch")
    if cat.get("source_scan_sha256")!=brick.get("source_sha256") or provenance.get("expected_sha256")!=cat["source_scan_sha256"]:
        raise ValueError("Original heritage scan SHA-256 mismatch")
    if provenance.get("license")!="CC BY 4.0":
        raise ValueError("Missing required original artist attribution")
    if len(raw)!=cat["bytes"] or len(raw)!=cat["sample_count"]*80 or hashlib.sha256(raw).hexdigest()!=cat["sha256"]:
        raise ValueError("Corrupted wall immutable sample bank")
    if hashlib.sha256(light).hexdigest()!=cat["lighting"]["sha256"]:
        raise ValueError("Corrupted LIE11 coded light graph")
    model=json.loads(light)
    if len(model["patches"])!=cat["lighting"]["node_count"]!=577:
        raise ValueError("Node count differs from captured scan mapping")
    master=cat["masters"]["real_scan_wall"]
    levels=master["levels"]
    if len(levels)!=3 or sum(l["count"] for l in levels)!=cat["sample_count"]:
        raise ValueError("Invalid three-level wall LOD")
    if any(l["start"]!=sum(p["count"] for p in levels[:i]) for i,l in enumerate(levels)):
        raise ValueError("Noncontiguous LOD ranges")
    if cat["collision"]["spatial_envelope_count"]!=1 or cat["wall_layout"]["brick_count"]!=96:
        raise ValueError("Wall layout/envelope contract mismatch")
    dest.mkdir(parents=True,exist_ok=True)
    (dest/"library.bin").write_bytes(raw)
    (dest/"catalog.json").write_text(json.dumps(cat,indent=2)+"\n",encoding="utf-8")
    (dest/"light-model.json").write_bytes(light)
    print("RESTORED LIE-WALL01",cat["sample_count"],"real scanned samples",cat["lighting"]["node_count"],"original LIE11 light nodes",cat["sha256"],flush=True)
    return cat


if __name__=="__main__":
    restore()
