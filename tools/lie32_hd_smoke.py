"""Native 960-square wall-module capture, unscaled actual Vulkan pixels."""
import argparse
import hashlib
import json
from pathlib import Path
import time
from PIL import Image
from lie_workshop_client import WorkshopClient,WorkshopBusy


def run(directory):
    c=WorkshopClient(directory,200)
    def ask(v):
        for attempt in range(12):
            try:return c.request(v)
            except WorkshopBusy:
                if attempt==11:raise
                time.sleep(.4)
    for t in range(100):
        snap=ask({"op":"snapshot"})["snapshot"]
        if snap["runtime"]["gpu_ready"]:break
        if snap["runtime"].get("failure"):
            raise RuntimeError(snap["runtime"]["failure"])
        time.sleep(.7)
    else:raise RuntimeError("HD GPU did not initialize")
    assert snap["lab"]=="lie32hd",snap["lab"]
    assert snap["metrics"]["instances"]==4,snap["metrics"]
    assert snap["metrics"]["configured"],snap["metrics"]

    def cap(name):
        result=ask({"op":"capture","filename":name+".png","kind":"compositor"})
        assert result["result"]["ok"],result
        p=Path(result["result"]["path"])
        with Image.open(p) as im:
            assert im.size==(960,960),im.size
            rgba=im.convert("RGBA")
            filled=sum(1 for i in rgba.getchannel("A").getdata() if i>10)
            assert filled>20000,("Empty or tiny native rendering",filled)
        return p,hashlib.sha256(p.read_bytes()).hexdigest(),filled

    wall,wallsha,wallpixels=cap("LIE32-4Modules-Native960")
    answer=ask({"op":"set_values","values":{
        "mode":"master","master":"wall_variant_0","camera_yaw":5,"camera_elevation":5}})
    assert answer["result"]["ok"],answer
    detail,detailsha,detailpixels=cap("LIE32-Module-Detail-Native960")
    report={"renderer":"Actual Godot 4.7.2 Vulkan software LIE",
            "native_output":[960,960],"upscaled":False,
            "sources":"Prebaked CC0-derived 4 shared module masters",
            "wall_sha256":wallsha,"detail_sha256":detailsha,
            "wall_opaque_pixels":wallpixels,"detail_opaque_pixels":detailpixels,
            "module_instances":4,"underlying_bricks":504,
            "sample_invocations":snap["metrics"]["sample_invocations"],
            "physical_gpu_fps_benchmark":False}
    (directory/"LIE32-Native960-validation.json").write_text(json.dumps(report,indent=2))
    return report


if __name__=="__main__":
    ap=argparse.ArgumentParser()
    ap.add_argument("--directory",type=Path,required=True)
    args=ap.parse_args()
    print(json.dumps(run(args.directory),indent=2))
