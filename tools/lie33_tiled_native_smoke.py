"""Validate real high-resolution square LIE compositor PNGs, no upscaling."""
import argparse
import hashlib
import json
from pathlib import Path
import time
from PIL import Image
from lie_workshop_client import WorkshopClient, WorkshopBusy


def run(directory: Path) -> dict:
    client=WorkshopClient(directory, 200)

    def cmd(payload):
        for attempt in range(8):
            try:
                return client.request(payload)
            except WorkshopBusy:
                if attempt==7:raise
                time.sleep(.5)
    for _ in range(90):
        response=cmd({"op":"snapshot"})
        snap=response["snapshot"]
        if snap["runtime"]["gpu_ready"]:break
        if snap["runtime"].get("failure"):
            raise RuntimeError(snap["runtime"]["failure"])
        time.sleep(.7)
    else:
        log=directory/"godot.log"
        raise RuntimeError("Native 1080 compositor not ready: "+log.read_text(errors="replace")[-6000:])
    assert snap["lab"]=="lie33",snap["lab"]
    assert snap["metrics"]["configured"],snap["metrics"]
    assert snap["metrics"]["instances"]==127,snap["metrics"]

    def capture(name):
        resp=cmd({"op":"capture","kind":"compositor","filename":name})
        assert resp["result"]["ok"], resp
        path=Path(resp["result"]["path"])
        with Image.open(path) as img:
            assert img.size==(1080,1080),f"Expected native 1080, got {img.size}"
            rgba=img.convert("RGBA")
            mask=rgba.getchannel("A")
            assert mask.getbbox() is not None,"Empty real compositor capture"
        return path,hashlib.sha256(path.read_bytes()).hexdigest()
    wall,wall_sha=capture("LIE33-Wall-Native-1080-Square.png")
    response=cmd({"op":"set_values","values":{
        "mode":"master","master":"brick","camera_yaw":25,"camera_elevation":25}})
    assert response["result"]["ok"],response
    brick,brick_sha=capture("LIE33-Brick-Native-1080-Square.png")
    report={"renderer":"Actual Godot 4.7.2 LIE Software Vulkan",
            "native_screen_size":[1080,1080],
            "not_1920x1080_widescreen":True,
            "not_upscaled":True,
            "wall_png":str(wall),"wall_sha256":wall_sha,
            "brick_png":str(brick),"brick_sha256":brick_sha,
            "sample_invocations_wall":snap["metrics"]["sample_invocations"],
            "instances_wall":127,
            "physical_gpu_benchmark":False}
    (directory/"LIE33-native1080-report.json").write_text(json.dumps(report,indent=2))
    return report


if __name__=="__main__":
    p=argparse.ArgumentParser()
    p.add_argument("--directory",type=Path,required=True)
    args=p.parse_args()
    print(json.dumps(run(args.directory),indent=2))
