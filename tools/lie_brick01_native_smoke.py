"""Real Godot Vulkan LIE-BRICK01 hero-quality laboratory acceptance.

Verifies native PNGs, source captured geometry, one hidden box collider, two
master sizes and multiple viewpoints. This is a TECHNICAL smoke: the stringent
photo-realism comparison remains manual and requires a corresponding real
photo of the exact source object, not merely a plausible render.
"""
from __future__ import annotations
import argparse,hashlib,json,time
from pathlib import Path
from PIL import Image
from lie_workshop_client import WorkshopClient,WorkshopBusy

ROOT=Path(__file__).resolve().parents[1]


def validate(directory:Path):
    meta=json.loads((ROOT/"gpu_compute/captures/liebrick01/catalog.json").read_text())
    assert len(meta["masters"])==2
    assert meta["collision_proxy_count_per_active_brick"]==1
    assert meta["masters"]["brick_full"]["levels"][0]["count"]>180000
    assert meta["masters"]["brick_half"]["levels"][0]["count"]>75000
    c=WorkshopClient(directory,240)

    def request(payload):
        for tries in range(12):
            try:return c.request(payload)
            except WorkshopBusy:
                if tries==11:raise
                time.sleep(.4)

    for _ in range(100):
        snap=request({"op":"snapshot"})["snapshot"]
        if snap["runtime"].get("gpu_ready"):break
        if snap["runtime"].get("failure"):raise RuntimeError(snap["runtime"]["failure"])
        time.sleep(.6)
    else:
        log=directory/"godot.log"
        raise RuntimeError("Native hero GPU did not start: "+log.read_text(errors="replace")[-9000:])

    assert snap["lab"]=="liebrick01",snap["lab"]
    assert snap["collider_count"]==1,snap
    assert snap["physical_proxy"]=="one BoxShape3D",snap
    assert snap["metrics"]["instances"]==1,snap["metrics"]
    assert snap["metrics"]["configured"],snap["metrics"]
    assert snap["metrics"]["visible_source_meshes"]==0,snap["metrics"]
    assert snap["runtime"]["asset_uploads"]==1,snap["runtime"]

    def capture(filename):
        resp=request({"op":"capture","kind":"compositor","filename":filename})
        assert resp["result"]["ok"],resp
        p=Path(resp["result"]["path"])
        with Image.open(p) as im:
            assert im.size==(1080,1080),im.size
            rgba=im.convert("RGBA")
            alpha=rgba.getchannel("A")
            bounds=alpha.getbbox()
            assert bounds is not None,"Empty compositor"
            opaque=sum(value>10 for value in alpha.getdata())
            assert opaque>10000,f"Unexpected tiny hero capture: {opaque}"
        return {"path":str(p),"sha256":hashlib.sha256(p.read_bytes()).hexdigest(),
                "opaque_pixels":opaque,"bounds":list(bounds)}

    views={
      "ThreeQuarter":{"camera_yaw":28.0,"camera_elevation":24.0,
                      "light_azimuth":-68.0,"distance_factor":1.0},
      "Front":{"camera_yaw":0.0,"camera_elevation":0.0,
               "light_azimuth":-35.0},
      "Top":{"camera_yaw":20.0,"camera_elevation":74.0,
             "light_azimuth":-35.0},
      "RakingLight":{"camera_yaw":32.0,"camera_elevation":15.0,
                     "light_azimuth":-118.0,"light_power":1.4},
    }
    result={}
    for name,values in views.items():
        response=request({"op":"set_values","values":values})
        assert response["result"]["ok"],response
        result[name]=capture("LIE-BRICK01-"+name+".png")
    assert len({x["sha256"] for x in result.values()})==4, "View changes not propagated"
    main=request({"op":"snapshot"})["snapshot"]
    self_hero=meta["masters"]["brick_full"]["levels"][0]["count"]
    assert main["metrics"]["sample_invocations"]==self_hero, main["metrics"]

    response=request({"op":"set_values","values":{
        "master":"brick_half","camera_yaw":28,"camera_elevation":24,
        "light_azimuth":-68,"distance_factor":1}})
    assert response["result"]["ok"],response
    result["Half"]=capture("LIE-BRICK01-Half.png")
    half=request({"op":"snapshot"})["snapshot"]
    assert half["metrics"]["instances"]==1
    assert half["collider_count"]==1
    assert half["metrics"]["sample_invocations"]==meta["masters"]["brick_half"]["levels"][0]["count"]

    response=request({"op":"set_values","values":{
        "master":"brick_full","distance_factor":1.85}})
    assert response["result"]["ok"],response
    far=request({"op":"snapshot"})["snapshot"]
    assert far["metrics"]["lod"]==2,far["metrics"]
    assert far["metrics"]["sample_invocations"]==meta["masters"]["brick_full"]["levels"][2]["count"]

    report={
        "renderer":"Actual Godot 4.7.2 Vulkan (Mesa llvmpipe)",
        "source_geometry":"4K photographed PBR map + real procedural 3D chipped edges",
        "one_box_collider":True,"source_meshes_rendered":0,
        "master_full_levels":meta["masters"]["brick_full"]["levels"],
        "master_half_levels":meta["masters"]["brick_half"]["levels"],
        "native_pixels":[1080,1080],"upscaled":False,
        "view_captures":result,
        "lod_hero_count":self_hero,
        "lod_far_count":far["metrics"]["sample_invocations"],
        "bank_sha256":meta["sha256"],
        "hero_photo_indistinguishable":False,
        "hero_visual_acceptance":"PENDING direct reference-photo A/B and silhouette inspection",
        "physical_GPU_benchmark":False}
    (directory/"LIE-BRICK01-validation.json").write_text(json.dumps(report,indent=2))
    print(json.dumps(report,indent=2),flush=True)
    return report


if __name__=="__main__":
    ap=argparse.ArgumentParser();ap.add_argument("--directory",type=Path,required=True)
    args=ap.parse_args();validate(args.directory)
