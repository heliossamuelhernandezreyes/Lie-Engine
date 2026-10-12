"""Native LIE32 baked module acceptance, no generated fake imagery."""
import argparse
import hashlib
import json
from pathlib import Path
import time

from PIL import Image
from lie_workshop_client import WorkshopClient, WorkshopBusy


def run(directory: Path):
    client=WorkshopClient(directory,180)
    def command(request):
        for n in range(10):
            try:return client.request(request)
            except WorkshopBusy:
                if n==9:raise
                time.sleep(.2)
    for _ in range(70):
        result=command({"op":"snapshot"})
        snap=result["snapshot"]
        if snap["runtime"].get("gpu_ready"):break
        if snap["runtime"].get("failure"):
            raise RuntimeError(snap["runtime"]["failure"])
        time.sleep(.5)
    else:
        log=directory/"godot.log"
        raise RuntimeError("GPU not ready: "+log.read_text(errors="replace")[-8000:])
    metrics=snap["metrics"]
    assert snap["lab"]=="lie32",snap["lab"]
    assert metrics["configured"],metrics
    assert metrics["instances"]==4,metrics
    assert metrics["masters"]==4,metrics
    assert metrics["sample_invocations"]<750_000,metrics
    assert snap["runtime"]["asset_uploads"]==1,snap["runtime"]

    def capture(name):
        result=command({"op":"capture","filename":name+".png","kind":"compositor"})
        assert result["result"]["ok"],result
        filename=Path(result["result"]["path"])
        with Image.open(filename) as im:
            rgba=im.convert("RGBA")
            assert im.size==(512,512)
            alpha=rgba.getchannel("A")
            assert alpha.getbbox() is not None,"Empty native pixels"
            covered=sum(1 for v in alpha.getdata() if v>10)
        return filename,hashlib.sha256(filename.read_bytes()).hexdigest(),covered

    wall,baseline,opaque=capture("LIE32-Cluster-Wall-4Modules")
    response=command({"op":"set_values","values":{"seed":31}})
    assert response["result"]["ok"],response
    _,altered,_=capture("LIE32-Cluster-Seed31")
    assert altered!=baseline,"Changing seed did not alter native pixels"
    response=command({"op":"set_values","values":{"seed":29}})
    assert response["result"]["ok"],response
    _,restored,_=capture("LIE32-Cluster-Restored")
    assert restored==baseline,"Reproducibility broken"
    response=command({"op":"set_values","values":{
        "mode":"master","master":"wall_variant_0","camera_yaw":5,"camera_elevation":5}})
    assert response["result"]["ok"],response
    close,close_sha,close_opaque=capture("LIE32-Cluster-One-Module-Closeup")
    assert close_opaque>8000,"Module closeup lost too much opaque coverage"
    report={"renderer":"Native Godot 4.7.2 software Vulkan compositor",
            "provenance":"LIE31 real CC0 PBR samples, now reduced and baked into 4 module variants",
            "wall_image":str(wall),"wall_sha256":baseline,
            "one_module_closeup":str(close),"one_module_sha256":close_sha,
            "source_bricks_per_module":126,
            "combined_bricks":504,
            "instance_count":4,"baked_variants":4,
            "sample_invocations":metrics["sample_invocations"],
            "opaque_pixels":opaque,
            "theoretical_individual_invocations_for_4_modules":437306*4,
            "source_meshes_rendered":0,
            "seed_changes_pixels":True,"seed_replays_identically":True,
            "physical_gpu_speedup_measured":False,
            "source_output_square_px":512}
    (directory/"LIE32-validation.json").write_text(json.dumps(report,indent=2))
    return report


if __name__=="__main__":
    ap=argparse.ArgumentParser();ap.add_argument("--directory",type=Path,required=True)
    a=ap.parse_args();print(json.dumps(run(a.directory),indent=2))
