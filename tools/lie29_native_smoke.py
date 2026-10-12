"""LIE29 genuine native compositor contract, captured from running Godot."""
import argparse
import hashlib
import json
from pathlib import Path
import time

from PIL import Image
from lie_workshop_client import WorkshopClient, WorkshopBusy


def run(directory: Path) -> dict:
    c = WorkshopClient(directory, 120)
    def call(obj):
        for attempt in range(8):
            try:
                return c.request(obj)
            except WorkshopBusy:
                if attempt == 7:
                    raise
                time.sleep(.3)

    for attempt in range(35):
        response = call({"op": "snapshot"})
        snap = response["snapshot"]
        if snap.get("runtime", {}).get("gpu_ready"):
            break
        if snap.get("runtime", {}).get("failure"):
            raise RuntimeError(snap["runtime"]["failure"])
        time.sleep(.5)
    else:
        log = directory / "godot.log"
        print("Final native snapshot:", json.dumps(snap, indent=2), flush=True)
        if log.exists():
            print("Native Godot log (tail):", log.read_text(errors="replace")[-16000:], flush=True)
        raise RuntimeError("Native GPU compositor did not initialize")

    assert snap["lab"] == "lie29", snap["lab"]
    assert snap["metrics"]["configured"], snap["metrics"]
    assert snap["metrics"]["instances"] == 120, snap["metrics"]
    assert snap["metrics"]["sample_invocations"] == 678000, snap["metrics"]
    assert snap["runtime"]["asset_uploads"] == 1, snap["runtime"]

    def capture(filename):
        data = call({"op": "capture", "kind": "compositor", "filename": filename})
        assert data["result"]["ok"], data
        path = Path(data["result"]["path"])
        with Image.open(path) as image:
            rgba = image.convert("RGBA")
            alpha = rgba.getchannel("A")
            assert alpha.getbbox() is not None, "Empty native compositor image"
        return path, hashlib.sha256(path.read_bytes()).hexdigest()

    image, base_sha = capture("LIE29-Wall-Godot.png")
    out = call({"op": "set_values", "values": {"seed": 31}})
    assert out["result"]["ok"], out
    _, changed_sha = capture("LIE29-Wall-Seed31.png")
    assert changed_sha != base_sha, "Changing seed did not alter native pixels"
    out = call({"op": "set_values", "values": {"seed": 29}})
    assert out["result"]["ok"], out
    _, restored_sha = capture("LIE29-Wall-Restored.png")
    assert restored_sha == base_sha, "Restored seed did not restore exact pixels"
    report = {
        "renderer": "Native Godot 4.7.2 software Vulkan LIE compositor",
        "image": str(image), "image_sha256": base_sha,
        "instances": 120, "master_banks": 1, "sample_invocations": 678000,
        "seed_change_modified_pixels": changed_sha != base_sha,
        "seed_restore_exact": restored_sha == base_sha,
        "physical_gpu_performance_claim": False
    }
    (directory / "LIE29-validation.json").write_text(
        json.dumps(report, indent=2), encoding="utf-8"
    )
    return report


if __name__ == "__main__":
    p = argparse.ArgumentParser()
    p.add_argument("--directory", required=True, type=Path)
    args = p.parse_args()
    print(json.dumps(run(args.directory), indent=2))
