"""Native Godot Vulkan check of experimental photographed LIE-WALL04 mortar.

Never call a synthetic PIL render a native screenshot. The saved PNGs come
exclusively from the real LIE11+LIE33 compositor via the agent readback.
"""
from __future__ import annotations
import argparse
import hashlib
import json
import time
from pathlib import Path

from lie_wall03_native_smoke import analyze_png
from lie_workshop_client import WorkshopClient,WorkshopBusy

ROOT=Path(__file__).resolve().parents[1]

def smoke(directory:Path) ->dict:
    cat=json.loads((ROOT/"gpu_compute/captures/liewall04/catalog.json").read_text())
    assert cat["source_original_triangles"]==500000
    assert cat["wall_layout"]["brick_count"]==96
    assert cat["collision"]["spatial_envelope_count"]==1
    assert cat["lighting"]["node_count"]==872
    assert not cat["wall04"]["mortar_source_masks_reviewed"]
    assert cat["wall04"]["legacy_mortar_samples_removed"]
    assert cat["wall04"]["original_brick_samples_byte_identical"]
    conn=WorkshopClient(directory,timeout=240)

    def request(msg):
        for i in range(18):
            try:return conn.request(msg)
            except WorkshopBusy:
                if i==17:raise
                time.sleep(.3)

    start=time.monotonic()
    while time.monotonic()-start<180:
        response=request({"op":"snapshot"})
        snap=response["snapshot"]
        if snap.get("runtime",{}).get("failure"):
            raise RuntimeError("Godot Vulkan startup: "+str(snap["runtime"]["failure"]))
        if (snap.get("lab")=="liewall04" and snap.get("transport_gpu_ready") and
            snap.get("coded_light",{}).get("transport_bound") and
            snap.get("metrics",{}).get("configured")):break
        time.sleep(.6)
    else:raise RuntimeError("WALL04 Vulkan transport timeout: "+(directory/"godot.log").read_text(errors="replace")[-12000:])

    assert snap["collider_count"]==snap["wall_envelope_count"]==1,snap
    assert snap["metrics"]["instances"]==1,snap
    assert snap["metrics"]["visible_source_meshes"]==0,snap
    assert snap["material_light_nodes"]==872,snap
    assert snap["mortar_light_nodes"]==8,snap
    assert snap["shadow_metrics"]["direct_shadow_boxes"]==96,snap
    assert snap["legacy_planar_mortar_enabled"] is False,snap
    assert snap["original_brick_records_verified"] is True,snap
    assert snap["source_mortar_G1_reviewed"] is False,snap
    assert snap["hero_quality_accepted"] is False,snap

    def update(values):
        response=request({"op":"set_values","values":values})
        assert response["result"]["ok"],response
        time.sleep(1)

    def capture(label):
        response=request({"op":"capture","kind":"compositor","filename":"LIE-WALL04-"+label+".png"})
        assert response["result"]["ok"],response
        measured=analyze_png(Path(response["result"]["path"]))
        assert measured["occupied_pixels"]>30000,measured
        return measured

    update({"lighting_preset":"neutral","camera_yaw":17.,
            "camera_elevation":11.,"distance_factor":.65,
            "light_azimuth":-22.,"clay_absorption":0.,
            "coverage_enabled":True,"shadows":True,"direct_shadow_proxies":True})
    neutral=capture("CapturedMortar-Neutral")
    # A/B with identical 1080p wall/camera/PBR/light RGB and WITHOUT optional
    # occlusion: locate whether 96 direct-shadow proxies or actual intrinsic
    # LIE11 node irradiance cause opaque dark bricks.
    update({"shadows":False,"direct_shadow_proxies":False})
    no_occluders=capture("CapturedMortar-NoOccluders-DIAGNOSTIC")
    update({"shadows":True,"direct_shadow_proxies":True})
    update({"lighting_preset":"warm_raking","light_azimuth":-72.,"light_power":1.2})
    warm=capture("CapturedMortar-Raking")
    assert neutral["sha256"]!=warm["sha256"],"Dynamic LIE11 source energy failed"
    distant=request({"op":"snapshot"})["snapshot"]
    assert distant["wall_envelope_count"]==1
    report={
      "scenario":"Native Godot Vulkan: authentic scanned original bricks + photographed unreviewed XYZ mortar samples",
      "source_wall03_sha256":cat["wall04"]["wall03_original_sha256"],
      "mortar_source_sha256":cat["wall04"]["mortar01_sha256"],
      "combined_bank_sha256":cat["sha256"],
      "source_triangles_drawn":0,"spatial_envelopes":1,
      "scanned_bricks":96,"lighting_nodes":872,
      "photographic_masks_reviewed":False,
      "absolute_mortar_relief_scale_verified":False,
      "photorealism_certified":False,
      "physical_android_gpu_tested":False,
      "mesa_vulkan_is_not_mobile_performance":True,
      "sample_counts":[v["count"] for v in cat["masters"]["real_scan_wall"]["levels"]],
      "captured_real_vulkan_pngs":{"neutral":neutral,"no_occluders_diagnostic":no_occluders,"raking":warm},
      "shadow_versus_patch_light_test":{
        "neutral_black_opaque_pixels":neutral["black_opaque_pixels"],
        "no_occluders_black_opaque_pixels":no_occluders["black_opaque_pixels"],
        "neutral_luminance":neutral["mean_luminance"],
        "no_occluders_luminance":no_occluders["mean_luminance"],
        "same_original_light_source_rgb_and_camera":True,
        "occlusion_disabled_result_only_diagnostic":True
      },
    }
    (directory/"LIE-WALL04-native-validation.json").write_text(json.dumps(report,indent=2)+"\n")
    print(json.dumps(report,indent=2))
    return report

if __name__=="__main__":
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--directory",type=Path,required=True)
    smoke(parser.parse_args().directory)
