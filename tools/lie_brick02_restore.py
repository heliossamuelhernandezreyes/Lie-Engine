"""Restore LIE-BRICK02 verified authentic Shakespeare brick sample bank.

No original mesh triangles are rendered in Godot: one invisible BoxShape3D
bounds the independently captured 80-byte samples. Original artist remains
attributed through the persisted CC BY 4.0 source provenance.
"""
from __future__ import annotations
import hashlib
import json
from pathlib import Path
import zlib

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "gpu_compute/assets/lie_brick02"
DEST = ROOT / "gpu_compute/captures/liebrick02"


def restore(source: Path = SOURCE, destination: Path = DEST) -> dict:
    meta = json.loads((source / "catalog.json").read_text(encoding="utf-8"))
    provenance = json.loads((source / "source_provenance.json").read_text(encoding="utf-8"))
    compressed = (source / "real_brick_bank.zlib").read_bytes()
    raw = zlib.decompress(compressed)
    if meta.get("stride") != 80 or meta.get("schema") != 1:
        raise ValueError("Incorrect LIE sample-bank schema/stride")
    if len(raw) != meta["sample_count"]*80 or len(raw) != meta["bytes"]:
        raise ValueError("LIE sample-bank byte size mismatch")
    if hashlib.sha256(raw).hexdigest() != meta["sha256"]:
        raise ValueError("Captured bank SHA-256 mismatch")
    if meta.get("source_original_triangles") != 500000:
        raise ValueError("Unexpected original scan triangle count")
    if meta.get("source_original_vertices") != 357956:
        raise ValueError("Unexpected original scan vertex count")
    if not meta.get("source_vertex_colors_used") or meta.get("source_photo_texture_uv_used"):
        raise ValueError("Scan COLOR_0 has been replaced or corrupted")
    if provenance.get("license") != "CC BY 4.0":
        raise ValueError("Original artist attribution/CC BY provenance required")
    if provenance.get("expected_sha256") != meta.get("source_sha256"):
        raise ValueError("Original source-lock SHA mismatch")
    masters = meta.get("masters", {})
    if len(masters) != 1 or "brick_full" not in masters:
        raise ValueError("Not one individually scanned brick master")
    levels = masters["brick_full"]["levels"]
    if len(levels) != 3 or sum(int(level["count"]) for level in levels) != meta["sample_count"]:
        raise ValueError("Invalid LIE-BRICK02 LOD ranges")
    if any(int(level["start"]) != sum(int(x["count"]) for x in levels[:i])
           for i, level in enumerate(levels)):
        raise ValueError("Non-contiguous LOD ranges")
    if meta.get("source_mesh_drawn") is not False:
        raise ValueError("Original source triangles must remain hidden")
    destination.mkdir(parents=True,exist_ok=True)
    (destination/"library.bin").write_bytes(raw)
    (destination/"catalog.json").write_text(json.dumps(meta,indent=2)+"\n",encoding="utf-8")
    print("VERIFIED REAL LIE-BRICK02",meta["sample_count"],"samples",meta["sha256"],flush=True)
    return meta


if __name__ == "__main__":
    restore()
