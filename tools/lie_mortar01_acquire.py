"""Download and SHA-lock the original 8K Poly Haven photographic wall PBR set.

No fabricated maps, no runtime textures, no download on import. This is a
capture SOURCE: brick pixels must be masked off before any LIE mortar samples.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
from urllib.parse import urlparse
from PIL import Image
from lie_material_masters import BASE_API, fetch_to_path, request_json, select_maps

ROOT = Path(__file__).resolve().parents[1]
MATERIAL = ROOT / "assets/material_masters/mortar/hero/real_masonry_joint"
REQUIRED = ("color", "normal_gl", "height", "roughness")
OPTIONAL = ("ao",)


def _sha(path: Path) -> str:
    d = hashlib.sha256()
    with path.open("rb") as f:
        for block in iter(lambda: f.read(1024 * 1024), b""):
            d.update(block)
    return d.hexdigest()


def resolve(manifest: dict, resolution: str, metadata: dict | None = None) -> dict:
    p = manifest["provenance"]
    if p.get("provider") != "Poly Haven" or p.get("license") != "CC0-1.0":
        raise ValueError("Only source-verifiable Poly Haven CC0 assets are allowed")
    if p["api"] != BASE_API + p["asset_id"]:
        raise ValueError("Official Poly Haven API mismatch")
    available = select_maps(request_json(p["api"]) if metadata is None else metadata,
                            resolution, "png")
    if set(REQUIRED) - set(available):
        raise ValueError("Required physically aligned source maps are missing")
    return {k: v for k, v in available.items() if k in REQUIRED + OPTIONAL}


def _image_meta(path: Path) -> dict:
    with Image.open(path) as im:
        im.verify()
    with Image.open(path) as im:
        w, h = im.size
        mode = im.mode
    if min(w, h) < 512 or max(w, h) > 16384:
        raise ValueError("Impossible photographic PBR map resolution")
    return {"width": w, "height": h, "mode": mode}


def inspect_lock(root: Path = MATERIAL) -> dict:
    manifest = json.loads((root / "material_manifest.json").read_text(encoding="utf-8"))
    lock = json.loads((root / "source/source-lock.json").read_text(encoding="utf-8"))
    if lock["schema"] != "lie-source-lock/1.0" or lock["material_id"] != manifest["id"]:
        raise ValueError("Source/material contract mismatch")
    if lock["license"] != "CC0-1.0" or lock["source_page"] != manifest["provenance"]["page"]:
        raise ValueError("Source identity or CC0 provenance mismatch")
    if set(REQUIRED) - set(lock["files"]):
        raise ValueError("Source lock lacks required PBR channels")
    dimensions = set()
    for name, record in lock["files"].items():
        if name not in REQUIRED + OPTIONAL:
            raise ValueError("Unexpected map category")
        path = root / "source" / record["filename"]
        if path.name != record["filename"] or not path.is_file():
            raise ValueError("Invalid or missing source file path")
        if path.stat().st_size != record["bytes"] or _sha(path) != record["sha256"]:
            raise ValueError("Original source failed SHA256 verification")
        observed = _image_meta(path)
        if observed != record["image"]:
            raise ValueError("Source map metadata changed")
        dimensions.add((observed["width"], observed["height"]))
    if len(dimensions) != 1:
        raise ValueError("Source PBR maps are not pixel registered")
    return lock


def acquire(root: Path = MATERIAL, resolution: str = "8k", dry_run: bool = False) -> dict:
    manifest = json.loads((root / "material_manifest.json").read_text(encoding="utf-8"))
    selected = resolve(manifest, resolution)
    if dry_run:
        return {"asset_id": manifest["provenance"]["asset_id"], "resolution": resolution,
                "resolved": selected, "downloaded": False}
    source = root / "source"
    source.mkdir(parents=True, exist_ok=True)
    lock_path = source / "source-lock.json"
    if lock_path.exists():
        # A previously published source lock is metadata only. CI intentionally
        # does not commit nearly 935 MB of raw Poly Haven maps. Rehydrate
        # MISSING files from their pinned official URLs and check SHA-256.
        pinned = json.loads(lock_path.read_text(encoding="utf-8"))
        if (pinned.get("schema")!="lie-source-lock/1.0" or
            pinned.get("material_id")!=manifest["id"] or
            pinned.get("source_page")!=manifest["provenance"]["page"] or
            pinned.get("license")!="CC0-1.0" or
            pinned.get("resolution")!=resolution):
            raise ValueError("Previously locked mortar source is incompatible")
        for name, record in pinned["files"].items():
            filename=record["filename"]
            if (name not in REQUIRED+OPTIONAL or filename!=name+"."+record["format"] or
                not filename.endswith((".png",".exr",".jpg"))):
                raise ValueError("Unsafe prior PBR filename")
            url=urlparse(record["url"])
            if (url.scheme!="https" or
                not (url.hostname=="polyhaven.org" or
                     (url.hostname or "").endswith(".polyhaven.org"))):
                raise ValueError("Non-official pinned PBR source host")
            target=source/filename
            if not target.exists():
                recovered=fetch_to_path(record["url"],target)
                if (recovered["sha256"]!=record["sha256"] or
                    recovered["bytes"]!=record["bytes"]):
                    target.unlink(missing_ok=True)
                    raise ValueError("Recovered image does not match source-lock SHA256")
        return inspect_lock(root)
    result = {"schema": "lie-source-lock/1.0", "material_id": manifest["id"],
              "license": "CC0-1.0", "source_page": manifest["provenance"]["page"],
              "api": manifest["provenance"]["api"], "resolution": resolution,
              "source_kind": "photographic PBR brick wall; mortar must be segmented",
              "height_scale_absolute_verified": False, "files": {}}
    shape = None
    for name in REQUIRED + OPTIONAL:
        if name not in selected:
            continue
        entry = selected[name]
        filename = name + "." + entry["format"]
        target = source / filename
        if not target.is_file():
            downloaded = fetch_to_path(entry["url"], target)
        else:
            downloaded = {"filename": filename, "bytes": target.stat().st_size,
                          "sha256": _sha(target)}
        image = _image_meta(target)
        wh = (image["width"], image["height"])
        if shape is None:
            shape = wh
        if shape != wh:
            raise ValueError("Misregistered image dimensions: " + name)
        result["files"][name] = {**entry, **downloaded, "image": image}
    result["dimensions"] = list(shape)
    # Complete and atomically lock only after EVERY required map checks out.
    temporary = source / "source-lock.pending.json"
    temporary.write_text(json.dumps(result, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    temporary.replace(lock_path)
    inspect_lock(root)
    return result


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=MATERIAL)
    parser.add_argument("--resolution", choices=("2k", "4k", "8k"), default="8k")
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--verify", action="store_true")
    args = parser.parse_args()
    result = inspect_lock(args.root) if args.verify else acquire(args.root, args.resolution, args.dry_run)
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()
