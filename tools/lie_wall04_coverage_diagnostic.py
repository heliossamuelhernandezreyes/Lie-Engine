"""Native Vulkan pixel-mask audit: exactly which photographed mortar samples render.

Green is intentionally a nonphysical DEBUG code, never a material. This test
separates spatial support/depth gaps from physically dark node illumination.
"""
from __future__ import annotations
import argparse,json,time,hashlib
from pathlib import Path
import numpy as np
from PIL import Image
from lie_workshop_client import WorkshopClient,WorkshopBusy

def audit(directory:Path)->dict:
    client=WorkshopClient(directory,timeout=240)
    def request(msg):
        for attempt in range(18):
            try:return client.request(msg)
            except WorkshopBusy:
                if attempt==17:raise
                time.sleep(.25)
    switched=request({"op":"open_lab","lab":"liewall04diag"})
    if not switched["result"]["ok"]:raise RuntimeError(str(switched))
    deadline=time.monotonic()+180
    while time.monotonic()<deadline:
        snap=request({"op":"snapshot"})["snapshot"]
        if snap.get("runtime",{}).get("failure"):
            raise RuntimeError("Diagnostic Godot failed: "+str(snap["runtime"]["failure"]))
        if (snap.get("lab")=="liewall04diag" and snap.get("transport_gpu_ready") and
            snap.get("coded_light",{}).get("transport_bound") and
            snap.get("metrics",{}).get("configured")):break
        time.sleep(.4)
    else:raise TimeoutError("WALL04 diagnostic scene was not ready")
    values={"lighting_preset":"neutral","camera_yaw":17.,
            "camera_elevation":11.,"distance_factor":.65,
            "light_azimuth":-22.,"clay_absorption":0.,
            "coverage_enabled":True,"shadows":True,"direct_shadow_proxies":True}
    result=request({"op":"set_values","values":values})
    assert result["result"]["ok"],result
    time.sleep(1)
    name="LIE-WALL04-CapturedMortar-CoverageDEBUG.png"
    snap=request({"op":"capture","kind":"compositor","filename":name})
    assert snap["result"]["ok"],snap
    path=Path(snap["result"]["path"])
    with Image.open(path) as im:
        assert im.size==(1080,1080)
        pix=np.asarray(im.convert("RGBA"))
    a=pix[...,3]>15
    r,g,b=(pix[...,i].astype(np.int16) for i in range(3))
    # Diagnostic shader returns bright green, which survives tonemapping.
    green=a & (g>100)&(g>r*1.5)&(g>b*1.5)
    bricks=a & ~green
    report={"experimental_only":True,"device":"Mesa Vulkan in GitHub CI",
            "real_vulkan_capture":True,"real_photo_mortar_source":True,
            "debug_color_is_not_real_mortar_albedo":True,
            "source_samples_drawn_on_screen":int(green.sum()),
            "brick_or_other_pixels":int(bricks.sum()),
            "screen_alpha_occupied":int(a.sum()),
            "source_sample_coverage_ratio":float(green.sum())/max(float(a.sum()),1),
            "source_png":path.name,"sha256":hashlib.sha256(path.read_bytes()).hexdigest(),
            "G1_masks_reviewed":False}
    (directory/"LIE-WALL04-coverage-diagnostic.json").write_text(json.dumps(report,indent=2)+"\n")
    if green.sum()<2000:raise RuntimeError("Missing captured source mortar coverage")
    print(json.dumps(report,indent=2))
    return report

if __name__=="__main__":
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument("--directory",type=Path,required=True)
    audit(p.parse_args().directory)
