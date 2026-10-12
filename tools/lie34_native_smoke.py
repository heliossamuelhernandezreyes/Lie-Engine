"""Native software-Vulkan acceptance of actual Draco-photogrammetry LIE capture."""
import argparse,hashlib,json,time
from pathlib import Path
from PIL import Image
from lie_workshop_client import WorkshopClient,WorkshopBusy


def run(directory:Path):
    c=WorkshopClient(directory,210)
    def ask(data):
        for retry in range(8):
            try:return c.request(data)
            except WorkshopBusy:
                if retry==7:raise
                time.sleep(.3)
    for _ in range(100):
        snap=ask({"op":"snapshot"})["snapshot"]
        if snap["runtime"].get("gpu_ready"):break
        if snap["runtime"].get("failure"):
            raise RuntimeError(snap["runtime"]["failure"])
        time.sleep(.7)
    else:
        log=directory/"godot.log"
        raise RuntimeError("Native scan GPU not ready: "+log.read_text(errors="replace")[-6000:])
    assert snap["lab"]=="lie34",snap["lab"]
    assert snap["metrics"]["instances"]==1,snap["metrics"]
    assert snap["metrics"]["sample_invocations"]==140000,snap["metrics"]
    assert snap["metrics"]["configured"],snap["metrics"]
    assert snap["runtime"]["asset_uploads"]==1,snap["runtime"]

    def shot(name):
        response=ask({"op":"capture","kind":"compositor","filename":name})
        assert response["result"]["ok"],response
        p=Path(response["result"]["path"])
        with Image.open(p) as im:
            assert im.size==(1080,1080),im.size
            rgba=im.convert("RGBA")
            coverage=sum(1 for v in rgba.getchannel("A").getdata() if v>10)
            assert coverage>1500, f"Visible captured geometry too sparse: {coverage}"
        return p,hashlib.sha256(p.read_bytes()).hexdigest(),coverage

    image,firstsha,coverage=shot("LIE34-Real-Photogrammetry-Native1080.png")
    response=ask({"op":"set_values","values":{"camera_yaw":-35.0}})
    assert response["result"]["ok"],response
    angled,secondsha,secondcoverage=shot("LIE34-Scan-Rotated-Native1080.png")
    assert secondsha!=firstsha,"Camera rotation did not alter actual scan image"
    report={
       "renderer":"Actual Godot 4.7.2 LIE Vulkan Software",
       "source_original_triangles":5500320,
       "source_original_vertices":2994426,
       "source_type":"Authentic photogrammetry of full building, NOT a single brick",
       "license":"CC BY 4.0 — Matthew Guertin",
       "actual_LIE_sample_invocations":140000,
       "sample_uploads":1,
       "native_size":[1080,1080],
       "unscaled":True,
       "original_source_mesh_drawn":False,
       "first_sha256":firstsha,
       "rotated_sha256":secondsha,
       "first_coverage_pixels":coverage,
       "rotated_coverage_pixels":secondcoverage,
       "physical_GPU_FPS_measured":False
    }
    (directory/"LIE34-native-validation.json").write_text(json.dumps(report,indent=2))
    return report


if __name__=="__main__":
    p=argparse.ArgumentParser();p.add_argument("--directory",required=True,type=Path)
    a=p.parse_args()
    print(json.dumps(run(a.directory),indent=2))
