"""Native Mesa Vulkan regression of *synthetic* GLB -> LIE samples; NOT a photorealism certification."""
from __future__ import annotations
import argparse
import hashlib
import json
from pathlib import Path
import time
from PIL import Image
from lie_workshop_client import WorkshopClient, WorkshopBusy

ROOT=Path(__file__).resolve().parents[1]


def validate(directory: Path) -> dict:
    catalog=json.loads((ROOT/"gpu_compute/captures/liebrick02/catalog.json").read_text())
    assert catalog["source_3d_shape_used"] and catalog["source_photo_texture_uv_used"]
    assert catalog["source_capture_kind_declared"].startswith("synthetic")
    assert not catalog["hero_quality_accepted"]
    assert len(catalog["masters"]["brick_full"]["levels"])==3
    assert catalog["collision_proxy_count_per_active_brick"]==1
    c=WorkshopClient(directory,240)

    def request(payload):
        for tries in range(15):
            try:return c.request(payload)
            except WorkshopBusy:
                if tries==14:raise
                time.sleep(.4)

    for _ in range(110):
        snap=request({"op":"snapshot"})["snapshot"]
        if snap["runtime"].get("gpu_ready"):break
        if snap["runtime"].get("failure"):raise RuntimeError(str(snap["runtime"]["failure"]))
        time.sleep(.5)
    else:
        raise RuntimeError("Vulkan never became ready: "+(directory/"godot.log").read_text(errors="replace")[-5000:])
    assert snap["lab"]=="liebrick02",snap["lab"]
    assert snap["collider_count"]==1,snap
    assert snap["metrics"]["visible_source_meshes"]==0,snap
    assert snap["metrics"]["instances"]==1,snap
    assert snap["metrics"]["configured"],snap
    captures={}
    for name,settings in {
        "front":{"camera_yaw":0.,"camera_elevation":0.},
        "three_quarter":{"camera_yaw":28.,"camera_elevation":24.},
        "top":{"camera_yaw":20.,"camera_elevation":74.}
    }.items():
        resp=request({"op":"set_values","values":settings})
        assert resp["result"]["ok"],resp
        image=request({"op":"capture","kind":"compositor","filename":f"LIE-BRICK02-SYNTHETIC-{name}.png"})
        assert image["result"]["ok"],image
        path=Path(image["result"]["path"])
        with Image.open(path) as im:
            assert im.size==(1080,1080),im.size
            opaque=sum(v>10 for v in im.convert("RGBA").getchannel("A").getdata())
        assert opaque>1500,(name,opaque)
        captures[name]={"sha256":hashlib.sha256(path.read_bytes()).hexdigest(),"opaque_pixels":opaque}
    assert len({v["sha256"] for v in captures.values()})==3,captures
    before=request({"op":"snapshot"})["snapshot"]
    assert before["metrics"]["sample_invocations"]==catalog["masters"]["brick_full"]["levels"][0]["count"]
    assert request({"op":"set_values","values":{"distance_factor":1.85}})["result"]["ok"]
    after=request({"op":"snapshot"})["snapshot"]
    assert after["metrics"]["lod"]==2,after["metrics"]
    assert after["metrics"]["sample_invocations"]==catalog["masters"]["brick_full"]["levels"][2]["count"]
    report={
        "result":"native smoke passed" ,"source":"SYNTHETIC_GLTF_NOT_PHOTOGRAMMETRY",
        "original_source_triangles":catalog["source_original_triangles"],
        "captured_samples":catalog["sample_count"],
        "source_meshes_drawn":0, "one_invisible_box":True,
        "native_resolution":[1080,1080],"software_Vulkan":True,
        "physical_gpu_performance_verified":False, "indistinguishable_from_photo":False,
        "views":captures, "far_lod_invocations":after["metrics"]["sample_invocations"]}
    (directory/"LIE-BRICK02-validation.json").write_text(json.dumps(report,indent=2))
    print(json.dumps(report,indent=2),flush=True)
    return report


if __name__=="__main__":
    parser=argparse.ArgumentParser()
    parser.add_argument("--directory",type=Path,required=True)
    args=parser.parse_args()
    validate(args.directory)
