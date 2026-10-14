"""Prepare SHA-locked assets needed by full Python regression discovery.

Never substitute a fixture for the published real brick bank. Only generated
captures are written; versioned source/provenance/assets remain untouched.
"""
from __future__ import annotations
import json
from importlib.metadata import version
from pathlib import Path
from lie_brick02_restore import restore


def prepare() -> dict:
    root = Path(__file__).resolve().parents[1]
    packages = {name: version(name) for name in ("numpy", "Pillow", "scipy", "trimesh")}
    metadata = restore(destination=root / "gpu_compute/captures/liebrick02")
    return {"dependencies": packages, "real_brick_sha256": metadata["sha256"],
            "sample_count": metadata["sample_count"], "source_triangles": metadata["source_original_triangles"]}


if __name__ == "__main__":
    print(json.dumps(prepare(), sort_keys=True))
