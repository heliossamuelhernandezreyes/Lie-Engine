"""WALL04: calibrate eight mortar LIE11 light-code patches to REAL photo-bank XYZ.

The historical LIE11 model placed these eight codes at the OLD planar mortar
surface (Z≈56.3mm), although WALL04 measured photographic mortar lies near
Z≈39mm. Lighting a recessed source as if in FRONT of the scanned brick
creates nonphysical exposed/raised looking joints. This tool copies the exact
original model, changes ONLY mortar patch positions and source-measured
normals, and records a source SHA lock. No added lights, source geometry,
mesh faces, or new physics contract.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import zlib

import numpy as np

ROOT=Path(__file__).resolve().parents[1]
SOURCE=ROOT/"gpu_compute/assets/lie_wall03"
MORTAR=ROOT/"gpu_compute/assets/lie_mortar01"
TARGET=ROOT/"gpu_compute/assets/lie_wall04"
FIRST=864
LAST=872


def sha(blob:bytes)->str:
    return hashlib.sha256(blob).hexdigest()


def calibrate(source:Path=SOURCE,mortar:Path=MORTAR,target:Path=TARGET)->dict:
    original_cat=json.loads((source/"catalog.json").read_text())
    bank_cat=json.loads((mortar/"catalog.json").read_text())
    wall_cat=json.loads((target/"catalog.json").read_text())
    light_source=(source/"light-model.json").read_bytes()
    if (sha(light_source)!=original_cat["lighting"]["sha256"]
            or wall_cat["wall04"]["wall03_original_sha256"]!=original_cat["sha256"]
            or bank_cat["sha256"]!=wall_cat["wall04"]["mortar01_sha256"]
            or wall_cat["collision"]["spatial_envelope_count"]!=1):
        raise ValueError("Source scan / lighting / material identity changed")
    raw=zlib.decompress((mortar/"mortar-bank.zlib").read_bytes())
    if (len(raw)!=bank_cat["sample_count"]*80 or sha(raw)!=bank_cat["sha256"]
            or len(bank_cat["levels"])!=3):
        raise ValueError("Real photographed mortar bank SHA/ABI mismatch")
    samples=np.frombuffer(raw,dtype="<f4").reshape(-1,20)
    level=bank_cat["levels"][0]
    highest=samples[level["start"]:level["start"]+level["count"]]
    original=json.loads(light_source)
    if len(original["patches"])!=872:
        raise ValueError("LIE11 original 872-light-code ABI was changed")
    old_light_sha=sha(light_source)
    patch_results=[]
    for node in range(FIRST,LAST):
        record=original["patches"][node]
        if record["material"]!="mortar" or record["micro_id"]!=node:
            raise ValueError("Unexpected old LIE11 mortar code identity")
        joint=highest[(highest[:,9].astype(np.int32)==node)&(highest[:,11]<.5)]
        if len(joint)<400 or np.any(~np.isfinite(joint)):
            raise ValueError("Insufficient original source photographic core samples")
        center=np.median(joint[:,:3],axis=0).astype(np.float64)
        avg_normal=np.mean(joint[:,4:7].astype(np.float64),axis=0)
        avg_normal/=max(np.linalg.norm(avg_normal),1e-12)
        if not (.01<center[2]<.060 and avg_normal[2]>.93):
            raise ValueError("Mortar source front height/normal not physically plausible")
        previous=list(record["position"])
        # Preserve all LIE11 radiometry, area, color, power and bounce rules:
        # ONLY the eight measured representative receiver XYZ/normals change.
        record["position"]=[float(round(v,9)) for v in center]
        record["normal"]=[float(round(v,7)) for v in avg_normal]
        record["wall04_position_source"]="median of real CC0 8K mortar front-core 80-byte XYZ samples"
        patch_results.append({
            "node_id":node,
            "source_front_core_samples":int(len(joint)),
            "original_position":previous,
            "measured_position":record["position"],
            "original_z_to_measured_z_mm":(previous[2]-record["position"][2])*1000.0,
            "measured_normal":record["normal"]
        })
    # Original 864 original brick patches must stay field-identical.
    old=json.loads(light_source)
    if original["patches"][:FIRST]!=old["patches"][:FIRST]:
        raise ValueError("Attempt to change 864 original scanned brick light nodes")
    assert original["lights"]==old["lights"]
    assert original["materials"]==old["materials"]
    assert original["bounces"]==old["bounces"]
    assert original["direct_shadow_boxes"]==old["direct_shadow_boxes"]
    original["mortar_light_provenance"]={
        "code_ids":[FIRST,LAST-1],
        "data":"actual CC0 8K photographed mortar XYZ + PBR source normals",
        "historical_lie11_sha256":old_light_sha,
        "bricks_0_863_unchanged":True,
        "original_lights_unchanged":True,
        "original_96_shadow_boxes_unchanged":True,
        "unreviewed_source_quality":True
    }
    content=(json.dumps(original,indent=2,ensure_ascii=False)+"\n").encode()
    new_light_sha=sha(content)
    wall_cat["lighting"]["sha256"]=new_light_sha
    wall_cat["wall04"]["original_lie11_light_sha256"]=old_light_sha
    wall_cat["wall04"]["recalibrated_mortar_nodes_sha256"]=new_light_sha
    wall_cat["wall04"]["mortar_source_light_positions_measured_not_artificial"]=True
    wall_cat["hero_quality_accepted"]=False
    proof={
        "schema":"lie-wall04-eight-mortar-patch-calibration/1",
        "original_872_patch_model_sha256":old_light_sha,
        "measured_source_872_patch_model_sha256":new_light_sha,
        "source_mortar_bank_sha256":bank_cat["sha256"],
        "immutable_brick_bank_sha256":original_cat["sha256"],
        "source_historical_864_brick_patches_unchanged":True,
        "source_original_point_light_unchanged":True,
        "source_original_96_brick_visibility_boxes_unchanged":True,
        "zero_new_light_sources":True,
        "photoreal_approved":False,
        "patches":patch_results
    }
    (target/"light-model.json").write_bytes(content)
    (target/"catalog.json").write_text(json.dumps(wall_cat,indent=2)+"\n")
    (target/"light-node-calibration.json").write_text(json.dumps(proof,indent=2)+"\n")
    return proof


if __name__=="__main__":
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source",type=Path,default=SOURCE)
    parser.add_argument("--mortar",type=Path,default=MORTAR)
    parser.add_argument("--target",type=Path,default=TARGET)
    args=parser.parse_args()
    print(json.dumps(calibrate(args.source,args.mortar,args.target),indent=2))
