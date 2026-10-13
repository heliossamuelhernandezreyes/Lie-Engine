"""Acquire the exact CC-BY Shakespeare brick from the public Objaverse 1.0 release.

Objaverse is an authorized public research dataset of Creative-Commons objects.
Only downloads published object files; NEVER extracts viewer endpoints or bypasses
Sketchfab login. Missing/restricted UID => FAIL, do not substitute any object.
"""
from __future__ import annotations
import argparse
import hashlib
import json
from pathlib import Path
import shutil

UID = "6077f6801089403993f6a6612ff5739a"
SKETCHFAB = "https://sketchfab.com/3d-models/stratford-new-place-brick-ver-2-" + UID
DATASET = "https://huggingface.co/datasets/allenai/objaverse"
TITLE = "Stratford New Place Brick Ver 2"
ARTIST = "Centre-of-Archaeology"


def acquire(directory: Path) -> dict:
    import objaverse
    directory.mkdir(parents=True, exist_ok=True)
    annotation = objaverse.load_annotations(uids=[UID]).get(UID)
    if not isinstance(annotation, dict):
        raise RuntimeError("Exact Sketchfab UID not present in public Objaverse; do not substitute")
    license_code = str(annotation.get("license", "")).lower()
    if license_code not in ("by", "cc-by", "cc-by-4.0"):
        raise RuntimeError(f"Public object's metadata license is not CC BY: {license_code}")
    found_uri = str(annotation.get("uri", ""))
    viewer_url = str(annotation.get("viewerUrl", ""))
    if UID not in found_uri and UID not in viewer_url:
        raise RuntimeError("Object dataset UID does not match source attribution")
    objects = objaverse.load_objects(uids=[UID], download_processes=1)
    raw_path = objects.get(UID)
    if not raw_path or not Path(raw_path).is_file():
        raise RuntimeError("Licensed public dataset cannot deliver original GLB")
    raw_path = Path(raw_path)
    target = directory / (UID + ".glb")
    if raw_path.stat().st_size < 1024 or raw_path.stat().st_size > 200_000_000:
        raise RuntimeError("Unexpectedly sized original source")
    with raw_path.open("rb") as handle:
        if handle.read(4) != b"glTF":
            raise RuntimeError("Downloaded object does not have GLB 2.0 header")
    shutil.copyfile(raw_path, target)
    digest = hashlib.sha256(target.read_bytes()).hexdigest()
    provenance = {
        "title": TITLE,
        "author": ARTIST,
        "license": "CC BY 4.0",
        "source_url": SKETCHFAB,
        "capture_kind": "structured-light 3D scan (heritage publisher description)",
        "expected_sha256": digest,
        "dataset_url": DATASET,
        "dataset_uid": UID,
        "dataset_annotation": {
            "license": annotation.get("license"),
            "name": annotation.get("name"),
            "uri": annotation.get("uri"),
            "viewerUrl": annotation.get("viewerUrl"),
            "user": annotation.get("user"),
        },
        "download_method": "public CC-licensed Objaverse 1.0 GLB, official load_objects",
        "source_size_bytes": target.stat().st_size,
    }
    (directory / "provenance.json").write_text(json.dumps(provenance, indent=2) + "\n")
    report = {
        "original_asset": SKETCHFAB,
        "dataset": DATASET,
        "sha256": digest,
        "bytes": target.stat().st_size,
        "license":"CC BY 4.0",
        "source_file": str(target),
        "source_is_original_dataset_glb": True,
        "mesh_geometry_processed": False,
    }
    (directory / "acquisition-report.json").write_text(json.dumps(report, indent=2) + "\n")
    print("REAL BRICK ORIGINAL ACQUIRED", json.dumps(report), flush=True)
    return report


if __name__ == "__main__":
    p=argparse.ArgumentParser()
    p.add_argument("--directory",required=True,type=Path)
    args=p.parse_args()
    acquire(args.directory)
