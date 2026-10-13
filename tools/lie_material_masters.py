"""LIE CC0 material-bank acquisition, separate from runtime rendering.

Resolves authoritative Poly Haven asset files via its public metadata API.
No geometry is generated and no output is a LIE visual capture by itself.
Standard library only; offline --list works without network access.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import tempfile
from urllib.parse import urlparse
from urllib.request import Request, urlopen

ROOT = Path(__file__).resolve().parents[1] / "assets" / "material_masters"
BASE_API = "https://api.polyhaven.com/files/"
MAPS = {
    "color": ("Diffuse", "diffuse", "albedo"),
    "normal_gl": ("nor_gl", "Normal (GL)", "normal_gl"),
    "height": ("Displacement", "disp", "height"),
    "roughness": ("Rough", "roughness", "rough"),
    "ao": ("AO", "ao"),
}
REQUIRED = ("color", "normal_gl", "height", "roughness")
EXTENSIONS = ("png", "exr", "jpg")
RESOLUTIONS = ("2k", "4k", "8k", "16k")
MAX_FILE_BYTES = 700_000_000
UA = {"User-Agent": "Lie-Engine-MaterialMasters/1.0 (CC0 offline research)"}


def load_catalog(root: Path = ROOT) -> tuple[dict, list[tuple[dict, dict, Path]]]:
    catalog = json.loads((root / "catalog.json").read_text(encoding="utf-8"))
    result = []
    for entry in catalog["materials"]:
        path = root / entry["manifest"]
        manifest = json.loads(path.read_text(encoding="utf-8"))
        if entry["id"] != manifest["id"]:
            raise ValueError(f"Catalog/manifest ID mismatch at {path}")
        result.append((entry, manifest, path.parent))
    return catalog, result


def request_json(url: str) -> dict:
    with urlopen(Request(url, headers=UA), timeout=45) as response:
        return json.load(response)


def select_maps(api_data: dict, resolution: str, file_format: str = "png") -> dict:
    """Resolve Poly Haven API map entries; fail rather than invent content."""
    if resolution not in RESOLUTIONS:
        raise ValueError(f"Unsupported resolution: {resolution}")
    if file_format not in EXTENSIONS:
        raise ValueError(f"Unsupported format: {file_format}")
    selected = {}
    choices = (file_format,) + tuple(x for x in EXTENSIONS if x != file_format)
    for name, possible in MAPS.items():
        key = next((k for k in possible if k in api_data), None)
        if key is None:
            if name in REQUIRED:
                raise KeyError(f"Missing required map: {name}")
            continue
        if resolution not in api_data[key]:
            if name in REQUIRED:
                raise KeyError(f"Missing required resolution {resolution} for {name}")
            continue
        record = api_data[key][resolution]
        match = next(((ext, record[ext]) for ext in choices
                      if isinstance(record.get(ext), dict) and record[ext].get("url")), None)
        if match is None:
            if name in REQUIRED:
                raise KeyError(f"Missing usable format for {name} at {resolution}")
            continue
        ext, descriptor = match
        url = descriptor["url"]
        parsed = urlparse(url)
        if parsed.scheme != "https" or not (parsed.hostname == "polyhaven.org" or
                                             (parsed.hostname or "").endswith(".polyhaven.org")):
            raise ValueError(f"Unexpected download host for {name}: {url}")
        selected[name] = {"api_key": key, "format": ext, "url": url}
    return selected


def fetch_to_path(url: str, destination: Path) -> dict:
    """Atomically download a single image; record its exact content hash."""
    destination.parent.mkdir(parents=True, exist_ok=True)
    digest = hashlib.sha256()
    count = 0
    fd, temp_name = tempfile.mkstemp(prefix=".lie_", suffix=".part", dir=destination.parent)
    try:
        with os.fdopen(fd, "wb") as output, urlopen(Request(url, headers=UA), timeout=120) as response:
            while chunk := response.read(1024 * 1024):
                count += len(chunk)
                if count > MAX_FILE_BYTES:
                    raise ValueError("Single image exceeds safety size cap")
                digest.update(chunk)
                output.write(chunk)
        if count < 64:
            raise ValueError("Unexpectedly small image")
        os.replace(temp_name, destination)
    finally:
        if os.path.exists(temp_name):
            os.remove(temp_name)
    return {"filename": destination.name, "bytes": count, "sha256": digest.hexdigest()}


def acquire(manifest: dict, directory: Path, resolution: str, file_format: str) -> dict:
    source = manifest["provenance"]
    if source["provider"] != "Poly Haven" or source["license"] != "CC0-1.0":
        raise ValueError("Only verified Poly Haven CC0 manifests supported")
    api_url = BASE_API + source["asset_id"]
    if source["api"] != api_url:
        raise ValueError("Manifest API source mismatch")
    selected = select_maps(request_json(api_url), resolution, file_format)
    target = directory / "source"
    target.mkdir(parents=True, exist_ok=True)
    # Keep the original source assets immutable once locked; explicit deletion is
    # required before re-acquiring a different resolution/version.
    lock_path = target / "source-lock.json"
    if lock_path.exists():
        raise FileExistsError(f"Existing source lock (do not overwrite): {lock_path}")
    report = {
        "schema": "lie-source-lock/1.0", "material_id": manifest["id"],
        "source_page": source["page"], "api": api_url,
        "license": source["license"], "source_kind": source["source_type"],
        "resolution": resolution, "requested_format": file_format, "files": {},
        "NOT_a_scanned_complete_individual_3d_object": True,
    }
    for name, info in selected.items():
        destination = target / f"{name}.{info['format']}"
        if destination.exists():
            raise FileExistsError(f"Will not silently overwrite: {destination}")
        locked = fetch_to_path(info["url"], destination)
        report["files"][name] = {**info, **locked}
        print(f"{manifest['id']}: {name} {locked['bytes']} B SHA256 {locked['sha256']}", flush=True)
    lock_path.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    return report


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    mode = ap.add_mutually_exclusive_group(required=True)
    mode.add_argument("--list", action="store_true", help="Show ten catalogued sources; no network")
    mode.add_argument("--download", action="store_true", help="Fetch Poly Haven PBR images and SHA-256 locks")
    scope = ap.add_mutually_exclusive_group()
    scope.add_argument("--id", help="One catalog material ID")
    scope.add_argument("--all", action="store_true", help="Explicitly download all ten; requires disk space")
    ap.add_argument("--resolution", choices=RESOLUTIONS, help="Override per-material preferred resolution")
    ap.add_argument("--format", dest="file_format", choices=EXTENSIONS, default="png")
    ap.add_argument("--root", type=Path, default=ROOT)
    args = ap.parse_args()
    _, items = load_catalog(args.root)
    if args.list:
        for entry, manifest, _ in items:
            print(entry["id"], manifest["provenance"]["page"], entry["max_advertised_resolution"])
        return 0
    if not args.id and not args.all:
        ap.error("--download requires --id or --all (large downloads are never implicit)")
    matching = [item for item in items if args.all or item[0]["id"] == args.id]
    if not matching:
        ap.error(f"Unknown material ID: {args.id}")
    for entry, manifest, folder in matching:
        resolution = args.resolution or entry["preferred_master_resolution"]
        print(f"Acquiring {entry['id']} at {resolution} ({args.file_format} preferred)", flush=True)
        acquire(manifest, folder, resolution, args.file_format)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
