"""Stage a small real LIE36 Vulkan lab, without fake reference imagery."""
from __future__ import annotations
import argparse
import json
import shutil
from pathlib import Path
from lie36_real_house import build
from lie_asset_contract import inspect_bank
ROOT=Path(__file__).resolve().parents[1]
SRC=ROOT/"gpu_compute"
FILES=[
    "lie22_modular_effect.gd",
    "lie28_building_effect.gd",
    "lie28_building_lab.gd",
    "lie_shared_sample_buffers.gd",
    "lie_asset_catalog.gd",
    "lie36_house_effect.gd",
    "lie36_house_lab.gd",
    "lie36_house_lab.tscn",
    "test_lie36_house.gd",
    "shaders/lie28_building.glsl",
    "shaders/lie36_house_material.glsl",
    "shaders/lie22_modular.glsl",
]
def stage(dest:Path):
    dest=Path(dest)
    dest.mkdir(parents=True,exist_ok=True)
    for name in FILES:
        out=dest/name
        out.parent.mkdir(parents=True,exist_ok=True)
        shutil.copy2(SRC/name,out)
    root=dest/"captures/liehouse36"
    meta,layout=build(root)
    # Reuse the common LIE0.9 asset preflight, NOT a house-specific hash.
    contract=inspect_bank((root/"library.bin").read_bytes(),meta)
    (root/"asset-contract.json").write_text(json.dumps(contract,indent=2)+"\n")
    (dest/"project.godot").write_text(
        'config_version=5\n[application]\nconfig/name="LIE36 Real Scan House"\n'
        'run/main_scene="res://lie36_house_lab.tscn"\n'
        '[rendering]\nrenderer/rendering_method="mobile"\n'
        'renderer/rendering_method.mobile="mobile"\n'
        '[display]\nwindow/size/viewport_width=1280\n'
        'window/size/viewport_height=800\n')
    (dest/"captures_out").mkdir(exist_ok=True)
    return {"root":str(dest),"samples":meta["sample_count"],
        "source_sha256":meta["source_bank_sha256"],"instances":len(layout["instances"])}
if __name__=="__main__":
    p=argparse.ArgumentParser()
    p.add_argument("--stage",type=Path,required=True)
    a=p.parse_args()
    print(json.dumps(stage(a.stage),indent=2))
