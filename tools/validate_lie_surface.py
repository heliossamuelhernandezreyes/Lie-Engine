"""Validate LIE-02 capture manifest and PNG assets before Godot import.

Structural/provenance validation only: cannot establish shading correctness.
No external dependencies (checks PNG header and content hashes).
"""
from __future__ import annotations
import argparse
import hashlib
import json
from pathlib import Path
import struct

PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"


def validate(root: Path) -> int:
    m = json.loads((root / "manifest.json").read_text(encoding="utf-8"))
    if m.get("schema_version") != 2 or m.get("projection") != "orthographic":
        raise ValueError("Unsupported Lie surface manifest")
    elevations = m["elevation_degrees"]
    steps = m["azimuth_steps"]
    res = m["resolution"]
    if steps < 4 or len(elevations) < 1 or len(m["views"]) != steps * len(elevations):
        raise ValueError("View grid incomplete")
    if not 0 < m["linear_depth_meters"]["near"] < m["linear_depth_meters"]["far"]:
        raise ValueError("Invalid depth range")
    seen = set()
    count = 0
    for view in m["views"]:
        key = view["code"]
        if key in seen:
            raise ValueError("Duplicate angular code " + key)
        seen.add(key)
        if key != f"az_{view['azimuth_index']:02d}_el_{view['elevation_index']:02d}":
            raise ValueError("Incorrect angular code " + key)
        if view["sha256"]["normal"] == view["sha256"]["depth"]:
            raise ValueError("Normal and depth channels are identical: " + key)
        for ch in ("albedo", "normal", "depth"):
            name = view["channels"][ch]
            if name != key + "." + ch + ".png":
                raise ValueError("Unexpected channel filename " + name)
            path = root / name
            data = path.read_bytes()
            if hashlib.sha256(data).hexdigest() != view["sha256"][ch]:
                raise ValueError("PNG checksum mismatch " + name)
            if not data.startswith(PNG_SIGNATURE) or data[12:16] != b"IHDR":
                raise ValueError("Not a PNG " + name)
            width, height = struct.unpack(">II", data[16:24])
            bits, color_type = data[24], data[25]
            if [width, height] != res or color_type != 6:
                raise ValueError("Wrong dimensions or RGBA encoding " + name)
            if bits != (8 if ch == "albedo" else 16):
                raise ValueError("Unexpected PNG channel precision " + name)
            count += 1
    print(f"LIE-02 SURFACE MANIFEST PASS views={len(seen)} png={count} sha256=verified")
    return count


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("directory", type=Path)
    args = parser.parse_args()
    validate(args.directory)
