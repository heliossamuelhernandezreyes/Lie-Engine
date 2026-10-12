"""Restore CC0-attributed LIE30 masonry captures derived from the LIE28 bank.

The 80-byte sample records are an immutable subset of the tested LIE28 archive:
brick/half_brick/concrete_panel, level 1. No new scan or 4K source is claimed.
All samples share one resident GPU allocation while scene instancing is separate.
"""
from __future__ import annotations
import base64
import hashlib
import json
from pathlib import Path
import zlib

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "gpu_compute/assets/lie30/masonry_bank.zlib.b64"
DESTINATION = ROOT / "gpu_compute/captures/lie30masonry"
EXPECTED_SHA256 = "d2f72992a99ce1febe37eaba73fd48f9db42071eb5c5ad105270c976311a5c63"
MASTERS = {
    "brick": {"start": 0, "count": 5650, "bounds_size": [0.24, 0.07, 0.12]},
    "half_brick": {"start": 5650, "count": 3186, "bounds_size": [0.115, 0.07, 0.12]},
    "concrete_panel": {"start": 8836, "count": 5930, "bounds_size": [1., .8, .12]},
}
STRIDE = 80
TOTAL_SAMPLES = sum(v["count"] for v in MASTERS.values())


def restore(destination: Path = DESTINATION) -> Path:
    source = "".join(SOURCE.read_text(encoding="ascii").split())
    raw = zlib.decompress(base64.b64decode(source, validate=True))
    if len(raw) != TOTAL_SAMPLES * STRIDE:
        raise ValueError("LIE30 incorrect sample bank byte count")
    if hashlib.sha256(raw).hexdigest() != EXPECTED_SHA256:
        raise ValueError("LIE30 sample bank SHA-256 mismatch")
    destination.mkdir(parents=True, exist_ok=True)
    (destination / "library.bin").write_bytes(raw)
    masters = {}
    for name, entry in MASTERS.items():
        level = {"start": entry["start"], "count": entry["count"]}
        masters[name] = {
            "levels": [level.copy(), level.copy()],
            "bounds_size": entry["bounds_size"],
            "origin_offset": [0, 0, 0],
        }
    catalog = {
        "schema": 1,
        "stride": STRIDE,
        "sample_count": TOTAL_SAMPLES,
        "sha256": EXPECTED_SHA256,
        "bytes": len(raw),
        "original_mesh_drawn": False,
        "source": "Original Blender geometry LIE28; CC0 Poly Haven photographic color and roughness",
        "materials": [
            {"name": "Factory Brick", "author": "Rob Tuytel", "license": "CC0",
             "url": "https://polyhaven.com/a/factory_brick"},
            {"name": "Concrete", "author": "Rob Tuytel", "license": "CC0",
             "url": "https://polyhaven.com/a/concrete"},
        ],
        "masters": masters,
    }
    (destination / "catalog.json").write_text(
        json.dumps(catalog, indent=2), encoding="utf-8"
    )
    return destination / "library.bin"


if __name__ == "__main__":
    output = restore()
    print("LIE30 verified", TOTAL_SAMPLES, "samples", output, EXPECTED_SHA256)
