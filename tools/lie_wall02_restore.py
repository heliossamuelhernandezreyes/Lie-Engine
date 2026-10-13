"""Restore immutable 96-authentic-brick LIE-WALL02 with 865 source micro-light nodes.

Preserves CC BY attribution, source hashes, one spatial envelope and the
separate 96 LIGHT-only shadow proxies. Not an exact-triangle ray trace.
"""
from __future__ import annotations

import hashlib
import json
from pathlib import Path
import zlib

ROOT=Path(__file__).resolve().parents[1]
SOURCE=ROOT/"gpu_compute/assets/lie_wall02"
DEST=ROOT/"gpu_compute/captures/liewall02"
BRICK=ROOT/"gpu_compute/assets/lie_brick02/catalog.json"


def restore(source: Path=SOURCE, dest: Path=DEST) -> dict:
    catalog=json.loads((source/"catalog.json").read_text(encoding="utf-8"))
    provenance=json.loads((source/"source_provenance.json").read_text(encoding="utf-8"))
    original=json.loads(BRICK.read_text(encoding="utf-8"))
    light_bytes=(source/"light-model.json").read_bytes()
    model=json.loads(light_bytes)
    raw=zlib.decompress((source/"wall_bank.zlib").read_bytes())
    if catalog.get("schema")!=1 or catalog.get("stride")!=80:
        raise ValueError("LIE wall sample byte ABI mismatch")
    if catalog.get("source_master_sha256")!=original.get("sha256") or catalog.get("source_scan_sha256")!=original.get("source_sha256"):
        raise ValueError("Authentic scanned source SHA mismatch")
    if catalog["source_scan_sha256"]!=provenance.get("expected_sha256") or provenance.get("license")!="CC BY 4.0":
        raise ValueError("Missing authentic 500k CC BY scan provenance")
    if catalog.get("source_original_triangles")!=500000 or catalog.get("original_meshes_drawn") is not False:
        raise ValueError("Runtime must not draw source mesh triangles")
    if len(raw)!=catalog["sample_count"]*80 or catalog["bytes"]!=len(raw):
        raise ValueError("Sample length differs from immutable master")
    if hashlib.sha256(raw).hexdigest()!=catalog.get("sha256"):
        raise ValueError("Master sample SHA corrupted")
    if hashlib.sha256(light_bytes).hexdigest()!=catalog["lighting"]["sha256"]:
        raise ValueError("Node code JSON SHA corrupted")
    if catalog["lighting"]["node_count"]!=865 or catalog["lighting"]["nodes_per_brick"]!=9:
        raise ValueError("Incorrect 865 precision nodes")
    if len(model.get("patches",[]))!=865 or len(model.get("direct_shadow_boxes",[]))!=96:
        raise ValueError("Missing GPU visibility data")
    if model.get("direct_shadow_nodes_per_brick")!=9 or model.get("direct_shadow_mortar_node")!=864:
        raise ValueError("Incorrect stable sample-to-patch indices")
    if catalog["collision"]["spatial_envelope_count"]!=1 or catalog["wall_layout"]["brick_count"]!=96:
        raise ValueError("Extra runtime collision envelopes")
    ranges=catalog["masters"]["real_scan_wall"]["levels"]
    if len(ranges)!=3 or sum(int(x["count"]) for x in ranges)!=catalog["sample_count"]:
        raise ValueError("Incorrect three LOD sample ranges")
    if any(int(r["start"])!=sum(int(p["count"]) for p in ranges[:i]) for i,r in enumerate(ranges)):
        raise ValueError("Discontinuous shared master ranges")
    dest.mkdir(parents=True,exist_ok=True)
    (dest/"library.bin").write_bytes(raw)
    (dest/"catalog.json").write_text(json.dumps(catalog,indent=2)+"\n",encoding="utf-8")
    (dest/"light-model.json").write_bytes(light_bytes)
    print("RESTORED LIE-WALL02",catalog["sample_count"],"real scanned samples",
          catalog["lighting"]["node_count"],"LIE11 light nodes",
          len(model["direct_shadow_boxes"]),"light-only proxies",
          catalog["sha256"],flush=True)
    return catalog


if __name__=="__main__":
    restore()
