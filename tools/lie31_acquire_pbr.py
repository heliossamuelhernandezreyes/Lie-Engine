"""Acquire a real high-resolution CC0 photographic PBR source for LIE31.

This is a *material scan*, not a separately scanned full 3D brick mesh. The
model-based Sketchfab assets require authorized downloads and are not bundled.
The LIE31 derived master will generate physical relief from this height map.
"""
from __future__ import annotations
import argparse
import hashlib
import json
from pathlib import Path
import urllib.request
from PIL import Image

ASSET = "red_brick"
API = f"https://api.polyhaven.com/files/{ASSET}"
SOURCE_PAGE = "https://polyhaven.com/a/red_brick"
MAPS = {
    "color": ["Diffuse", "diffuse", "albedo"],
    "normal": ["nor_gl", "Normal", "normal"],
    "height": ["Displacement", "disp", "height"],
    "roughness": ["Rough", "roughness", "rough"],
}
UA = {"User-Agent": "LIE31-source-research/1.0 (CC0 research, public API)"}


def get_bytes(url: str) -> bytes:
    request = urllib.request.Request(url, headers=UA)
    with urllib.request.urlopen(request, timeout=120) as response:
        return response.read()


def find_map(doc: dict, candidates: list[str], resolution: str) -> tuple[str, str]:
    key = next((key for key in candidates if key in doc), None)
    if key is None:
        raise KeyError(f"Required map unavailable: {candidates}; available {list(doc)}")
    formats = doc[key][resolution]
    for ext in ("jpg", "png", "exr"):
        record = formats.get(ext)
        if record and record.get("url"):
            return key, record["url"]
    raise KeyError(f"No usable format in {key} at {resolution}: {formats.keys()}")


def acquire(directory: Path, resolution: str = "4k") -> dict:
    if resolution not in ("2k", "4k", "8k"):
        raise ValueError("select 2k/4k/8k")
    directory.mkdir(parents=True, exist_ok=True)
    available = json.loads(get_bytes(API))
    provenance = {"asset": ASSET, "license": "CC0 1.0", "source_page": SOURCE_PAGE,
                  "api": API, "resolution": resolution, "type": "photo-based PBR material",
                  "NOT_scanned_mesh": True, "files": {}}
    for name, candidates in MAPS.items():
        key, url = find_map(available, candidates, resolution)
        extension = url.split("?", 1)[0].rsplit(".", 1)[-1].lower()
        if extension not in ("jpg", "jpeg", "png", "exr"):
            raise ValueError(f"Unrecognized extension: {url}")
        dest = directory / f"{name}.{extension}"
        data = get_bytes(url)
        if not data or len(data) > 250_000_000:
            raise ValueError("Downloaded file size invalid")
        digest = hashlib.sha256(data).hexdigest()
        dest.write_bytes(data)
        provenance["files"][name] = {"map_key": key, "url": url,
                                    "filename": dest.name, "bytes": len(data),
                                    "sha256": digest}
        print("LIE31 SOURCE", name, dest.name, len(data), digest, flush=True)
    diffuse = directory / provenance["files"]["color"]["filename"]
    with Image.open(diffuse) as im:
        rgb = im.convert("RGB")
        print("LIE31 COLOR DIMENSIONS", rgb.size, flush=True)
        # This is source reference only; NOT a LIE-rendered image.
        size = min(rgb.size)
        cropped = rgb.crop(((rgb.width-size)//2, (rgb.height-size)//2,
                            (rgb.width+size)//2, (rgb.height+size)//2))
        cropped.thumbnail((960, 960))
        cropped.save(directory / "SOURCE_ONLY_preview.jpg", quality=90)
        provenance["source_dimensions"] = list(rgb.size)
    (directory / "source-lock.json").write_text(json.dumps(provenance, indent=2))
    return provenance


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--directory", type=Path, required=True)
    ap.add_argument("--resolution", choices=("2k", "4k", "8k"), default="4k")
    args = ap.parse_args()
    print(json.dumps(acquire(args.directory, args.resolution), indent=2))
