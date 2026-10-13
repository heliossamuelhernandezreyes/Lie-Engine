"""Live Godot/Mesa Vulkan evidence of 96 real scanned bricks and LIE11 node transport.

Checks actual camera captures and changes to coded RGB and absorption. This does
NOT claim photographic indistinguishability or a hardware GPU performance win.
"""
from __future__ import annotations
import argparse
import hashlib
import json
import time
from pathlib import Path

import numpy as np
from PIL import Image
from lie_workshop_client import WorkshopClient, WorkshopBusy

ROOT=Path(__file__).resolve().parents[1]


def smoke(directory: Path):
    m=json.loads((ROOT/"gpu_compute/captures/liewall02/catalog.json").read_text())
    assert m["wall_layout"]["brick_count"]==96
    assert m["lighting"]["node_count"]==865
    assert m["lighting"]["direct_shadow_occluders"]==96
    assert m["collision"]["spatial_envelope_count"]==1
    client=WorkshopClient(directory,timeout=240)

    def request(payload):
        for i in range(12):
            try: return client.request(payload)
            except WorkshopBusy:
                if i==11:raise
                time.sleep(.5)

    start=time.monotonic()
    while time.monotonic()-start<140:
        snapshot=request({"op":"snapshot"})["snapshot"]
        if snapshot.get("runtime",{}).get("failure"):
            raise RuntimeError(snapshot["runtime"]["failure"])
        if snapshot.get("transport_gpu_ready") and snapshot.get("coded_light",{}).get("transport_bound") and snapshot.get("metrics",{}).get("configured"):
            break
        time.sleep(.5)
    else:
        raise RuntimeError("LIE11+LIE33 did not become ready: "+(directory/"godot.log").read_text(errors="replace")[-9000:])

    assert snapshot["lab"]=="liewall02",snapshot["lab"]
    assert snapshot["collider_count"]==1,snapshot
    assert snapshot["wall_brick_count"]==96
    assert snapshot["wall_envelope_count"]==1
    assert snapshot["metrics"]["instances"]==1
    assert snapshot["metrics"]["visible_source_meshes"]==0
    assert snapshot["lighting_node_count"]==865
    assert snapshot["micro_patches_per_brick"]==9
    assert snapshot["front_micro_patches"]==4
    assert snapshot["shadow_metrics"]["direct_shadow_boxes"]==96
    assert snapshot["shadow_metrics"]["shadow_storage_bytes"]>3000
    assert snapshot["coded_light"]["legacy_point_light_double_counting"] is False
    hero_count=m["masters"]["real_scan_wall"]["levels"][0]["count"]
    assert snapshot["metrics"]["sample_invocations"]==hero_count,snapshot["metrics"]

    def capture(label):
        filename=f"LIE-WALL02-MicroLight-{label}.png"
        a=request({"op":"capture","kind":"compositor","filename":filename})
        assert a["result"]["ok"],a
        p=Path(a["result"]["path"])
        with Image.open(p) as im:
            assert im.size==(1080,1080),im.size
            rgba=np.asarray(im.convert("RGBA"),dtype=np.uint8)
        valid=rgba[:,:,3]>10
        amount=int(valid.sum())
        assert amount>11000,(label,amount)
        lit=rgba[:,:,:3][valid].astype(np.float32)
        return {"filename":filename,"sha256":hashlib.sha256(p.read_bytes()).hexdigest(),
                "opaque_pixels":amount,"mean_rgb":[float(v) for v in lit.mean(axis=0)],
                "mean_luminance":float((lit @ np.array([.2126,.7152,.0722])).mean())}

    result={"neutral":capture("Neutral")}
    for label,values in (
        ("warm_raking",{"lighting_preset":"warm_raking","light_azimuth":-72.0,"light_power":1.3}),
        ("cool_ambient",{"lighting_preset":"cool_ambient","light_azimuth":63.0,"light_power":1.1}),
    ):
        response=request({"op":"set_values","values":values})
        assert response["result"]["ok"],response
        time.sleep(1.2)
        result[label]=capture(label)
    assert len({entry["sha256"] for entry in result.values()})==3,result
    # Compare the SAME raking light with original GPU shadow proxy binding
    # enabled/disabled: no camera, RGB or material changes.
    reply=request({"op":"set_values","values":{"lighting_preset":"warm_raking",
        "light_azimuth":-72.0,"light_power":1.3,"shadows":False}})
    assert reply["result"]["ok"],reply
    time.sleep(1.2)
    unoccluded=capture("warm_raking_no_direct_shadows")
    assert unoccluded["sha256"]!=result["warm_raking"]["sha256"], "GPU direct shadow AABBs not active"
    result["warm_raking_no_direct_shadows"]=unoccluded
    reply=request({"op":"set_values","values":{"lighting_preset":"cool_ambient",
        "light_azimuth":63.0,"light_power":1.1,"shadows":True}})
    assert reply["result"]["ok"],reply
    time.sleep(1.2)

    assert result["warm_raking"]["mean_rgb"][0]>result["warm_raking"]["mean_rgb"][2],result
    assert result["cool_ambient"]["mean_rgb"][2]>result["cool_ambient"]["mean_rgb"][0],result

    before=result["cool_ambient"]
    response=request({"op":"set_values","values":{"clay_absorption":.60}})
    assert response["result"]["ok"],response
    time.sleep(1.2)
    result["absorbed"]=capture("Absorption60")
    assert result["absorbed"]["sha256"]!=before["sha256"],"Absorption code not consumed"
    assert result["absorbed"]["mean_luminance"]<before["mean_luminance"]*.94,(before,result["absorbed"])
    update_snapshot=request({"op":"snapshot"})["snapshot"]
    assert update_snapshot["transport_frame_count"]>=3
    assert update_snapshot["lighting_updates"]>=3

    assert request({"op":"set_values","values":{"distance_factor":1.85}})["result"]["ok"]
    time.sleep(.5)
    lod=request({"op":"snapshot"})["snapshot"]
    assert lod["metrics"]["lod"]==2,lod
    far_count=m["masters"]["real_scan_wall"]["levels"][2]["count"]
    assert lod["metrics"]["sample_invocations"]==far_count,lod["metrics"]
    report={
        "kind":"LIE11 original GPU coded irradiance plus 96 source-brick shadow proxies to LIE33 865-node scan wall",
        "source_title":m["source_title"],"source_sha256":m["source_scan_sha256"],
        "source_original_triangles":500000,"original_meshes_rendered":0,
        "bricks":96,"coarse_spatial_boxes":1,"wall_render_instances":1,
        "light_nodes":865,"gpu_direct_shadow_proxies":96,"micro_patches_per_brick":9,"two_conservative_bounces":True,
        "native_output_pixels":[1080,1080],"software_Vulkan":True,
        "real_hardware_GPU_fps_measured":False,"photo_reference_AB_passed":False,
        "lod_hero_samples":hero_count,"lod_distant_samples":far_count,
        "light_updates":lod["lighting_updates"],"transport_frames":lod["transport_frame_count"],
        "views":result}
    (directory/"LIE-WALL02-native-validation.json").write_text(json.dumps(report,indent=2))
    print(json.dumps(report,indent=2),flush=True)
    return report


if __name__=="__main__":
    ap=argparse.ArgumentParser()
    ap.add_argument("--directory",type=Path,required=True)
    args=ap.parse_args()
    smoke(args.directory)
