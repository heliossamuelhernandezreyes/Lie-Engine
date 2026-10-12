"""Restore verified LIE31 native captured PBR master bank from GitHub.

Run after a successful LIE31 CI execution publishes hd_bank.zlib + catalog.
This never fetches Sketchfab or manufactures a claim of a separately scanned
high-poly mesh. The samples derive from real CC0 photographic texture maps.
"""
from __future__ import annotations
import hashlib
import json
from pathlib import Path
import zlib

ROOT=Path(__file__).resolve().parents[1]
SOURCE=ROOT/"gpu_compute/assets/lie31"
OUTPUT=ROOT/"gpu_compute/captures/lie31hd"


def restore(destination: Path=OUTPUT) -> Path:
    meta=json.loads((SOURCE/"catalog.json").read_text())
    content=zlib.decompress((SOURCE/"hd_bank.zlib").read_bytes())
    if meta["stride"]!=80 or len(content)!=meta["bytes"]:
        raise ValueError("Invalid sample bank length")
    if len(content)!=meta["sample_count"]*80:
        raise ValueError("Inconsistent sample count")
    if hashlib.sha256(content).hexdigest()!=meta["sha256"]:
        raise ValueError("Bank hash mismatch")
    destination.mkdir(parents=True,exist_ok=True)
    output=destination/"library.bin"
    output.write_bytes(content)
    (destination/"catalog.json").write_text(json.dumps(meta,indent=2))
    return output


if __name__=="__main__":
    p=restore()
    print("Verified LIE31 HD bank",p,p.stat().st_size)
