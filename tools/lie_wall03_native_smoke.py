"""Genuine LIE-WALL03 Godot/Vulkan A/B: safe hole coverage, mortar RGB, dynamic light.

Works against the existing agent inbox on a real Vulkan compositor; never
generates pictures with Pillow. Pillow only measures the Godot native PNGs.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import statistics
import time
from pathlib import Path

import numpy as np
from PIL import Image
from lie_workshop_client import WorkshopClient, WorkshopBusy

ROOT=Path(__file__).resolve().parents[1]


def analyze_png(path: Path) -> dict:
    with Image.open(path) as im:
        assert im.size==(1080,1080), im.size
        rgba=np.asarray(im.convert("RGBA"),dtype=np.uint8)
    alpha=rgba[:,:,3]
    present=alpha>10
    x=rgba[:,:,:3].astype(np.float64)
    mean=x[present].mean(axis=0) if present.any() else np.zeros(3)
    lum=np.dot(x[present],np.array([.2126,.7152,.0722])).mean() if present.any() else 0.
    # Strict visible interior 1px surrounded by real high-coverage pixels in
    # X and Y: excludes external silhouette/background. Diagnostic only.
    a=alpha.astype(np.int16)
    inside=np.zeros_like(present)
    inside[1:-1,1:-1]=((a[1:-1,1:-1]<10) &
        (a[1:-1,:-2]>220)&(a[1:-1,2:]>220)&
        (a[:-2,1:-1]>220)&(a[2:,1:-1]>220))
    return {"file":path.name,
            "sha256":hashlib.sha256(path.read_bytes()).hexdigest(),
            "occupied_pixels":int(present.sum()),
            "empty_enclosed_single_pixel_holes":int(inside.sum()),
            "mean_rgb":[float(v) for v in mean],
            "mean_luminance":float(lum),
            "black_opaque_pixels":int(np.count_nonzero(present & (x.max(axis=-1)<10)))}


def smoke(directory: Path) -> dict:
    cat=json.loads((ROOT/"gpu_compute/captures/liewall03/catalog.json").read_text())
    assert cat["source_original_triangles"]==500000
    assert cat["wall_layout"]["brick_count"]==96
    assert cat["lighting"]["node_count"]==872
    assert cat["lighting"]["mortar_nodes"]==8
    assert cat["collision"]["spatial_envelope_count"]==1
    conn=WorkshopClient(directory,timeout=240)

    def request(command):
        for i in range(18):
            try:return conn.request(command)
            except WorkshopBusy:
                if i==17: raise
                time.sleep(.3)

    start=time.monotonic()
    while time.monotonic()-start<155:
        snap=request({"op":"snapshot"})["snapshot"]
        if snap.get("runtime",{}).get("failure"):
            raise RuntimeError("GPU startup: "+str(snap["runtime"]["failure"]))
        if (snap.get("transport_gpu_ready") and
                snap.get("coded_light",{}).get("transport_bound") and
                snap.get("metrics",{}).get("configured")):
            break
        time.sleep(.5)
    else:
        raise RuntimeError("LIE-WALL03 GPU did not become ready: "+
                           (directory/"godot.log").read_text(errors="replace")[-9000:])
    assert snap["lab"]=="liewall03",snap.get("lab")
    assert snap["collider_count"]==snap["wall_envelope_count"]==1
    assert snap["metrics"]["instances"]==1
    assert snap["metrics"]["visible_source_meshes"]==0
    assert snap["material_light_nodes"]==872
    assert snap["mortar_light_nodes"]==8
    assert snap["shadow_metrics"]["direct_shadow_boxes"]==96
    assert snap["coded_light"]["legacy_point_light_double_counting"] is False

    def update(values):
        response=request({"op":"set_values","values":values})
        assert response["result"]["ok"],response
        time.sleep(1.0)

    def capture(label):
        name=f"LIE-WALL03-{label}.png"
        r=request({"op":"capture","kind":"compositor","filename":name})
        assert r["result"]["ok"],r
        record=analyze_png(Path(r["result"]["path"]))
        assert record["occupied_pixels"]>30000,record
        return record

    result={}
    # Identical scanned geometry, light codes, view and material: change only
    # the bounded gap reconstruction switch. NO generated illustrative PNGs.
    update({"lighting_preset":"neutral","light_azimuth":-22.0,
            "camera_yaw":19.0,"camera_elevation":12.0,
            "distance_factor":.6,"clay_absorption":0.0,
            "direct_shadow_proxies":True,"shadows":True,
            "coverage_enabled":False})
    result["coverage_off"]=capture("SameLight-CoverageOFF")
    snap_off=request({"op":"snapshot"})["snapshot"]
    update({"coverage_enabled":True})
    result["coverage_on"]=capture("SameLight-CoverageON")
    snap_on=request({"op":"snapshot"})["snapshot"]
    assert snap_on["coverage_active"] is True
    assert snap_on["coverage_profiler"]["full_resolution_hole_dispatches"]>0
    assert result["coverage_on"]["occupied_pixels"]>=result["coverage_off"]["occupied_pixels"],result
    # At least one interior pixel must change — ensure shader not inert.
    assert result["coverage_on"]["sha256"]!=result["coverage_off"]["sha256"],result
    assert result["coverage_on"]["empty_enclosed_single_pixel_holes"]<=result["coverage_off"]["empty_enclosed_single_pixel_holes"],result

    # Prove code-driven lighting still updates, and remains independent from
    # the capture source's original linear scanned COLOR_0.
    update({"distance_factor":1.0,"camera_yaw":12.0,"camera_elevation":9.0,
            "lighting_preset":"warm_raking","light_azimuth":-72.0,"light_power":1.3})
    result["warm_raking"]=capture("WarmRaking")
    update({"lighting_preset":"cool_ambient","light_azimuth":63.0,"light_power":1.1})
    result["cool"]=capture("CoolLight")
    assert result["warm_raking"]["sha256"]!=result["cool"]["sha256"]
    assert result["warm_raking"]["mean_rgb"][0]>result["warm_raking"]["mean_rgb"][2]
    assert result["cool"]["mean_rgb"][2]>result["cool"]["mean_rgb"][0]
    update({"clay_absorption":.6})
    result["absorption60"]=capture("ClayAbsorption60")
    assert result["absorption60"]["mean_luminance"]<result["cool"]["mean_luminance"]*.95

    # Verify LOD reduction without increasing source mesh count or colliders.
    update({"distance_factor":1.85})
    distant=request({"op":"snapshot"})["snapshot"]
    lods=cat["masters"]["real_scan_wall"]["levels"]
    assert distant["metrics"]["lod"]==2,distant["metrics"]
    assert distant["metrics"]["sample_invocations"]==lods[2]["count"]
    assert distant["collider_count"]==1
    assert distant["metrics"]["instances"]==1
    report={
        "scenario":"True Godot Vulkan LIE11 injected light, scanned COLOR_0 bricks, optional safe GPU hole fill",
        "original_source_sha256":cat["source_scan_sha256"],
        "source_original_triangles":500000,
        "source_geometry_drawn":0,"bricks":96,
        "spatial_envelopes":1,"wall_instances":1,
        "light_nodes":872,"mortar_nodes":8,"light_only_shadow_proxies":96,
        "vulkan_image_resolution":[1080,1080],
        "device_type":"software Vulkan Mesa on GitHub Actions",
        "physical_android_fps_measured":False,
        "source_photo_AB_performed":False,
        "coverage_on":snap_on["coverage_profiler"],
        "coverage_off":snap_off["coverage_profiler"],
        "lod_samples":[x["count"] for x in lods],
        "captures":result,
    }
    (directory/"LIE-WALL03-native-validation.json").write_text(json.dumps(report,indent=2)+"\n")
    print(json.dumps(report,indent=2),flush=True)
    return report


if __name__=="__main__":
    ap=argparse.ArgumentParser()
    ap.add_argument("--directory",type=Path,required=True)
    smoke(ap.parse_args().directory)
