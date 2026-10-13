"""LIE-WALL-03: preserve original 96 scanned bricks and give mortar local light codes.

Bakes a separate immutable VisualSampleBank; neither LIE-WALL-01/02 nor their
CC BY originals are modified. The wall remains one *coarse spatial envelope*.
Mortar is deliberately procedural (not misrepresented as the historical scan).
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path

import numpy as np
import lie_wall01_bake as legacy

ROOT=Path(__file__).resolve().parents[1]
DEST=ROOT/"gpu_compute/captures/liewall03"
MORTAR_FIRST=legacy.BRICKS*legacy.NODES_PER_BRICK # 864
MORTAR_NODES=legacy.ROWS # 8
MORTAR_RECESS_M=.011 # visible joints lie 11mm behind nominal brick front


def build(source: Path=legacy.SOURCE,destination: Path=DEST) -> dict:
    # Reuse proven source-authenticated GLB → LIE 80B source sample transformation.
    catalog=legacy.build(source=source,destination=destination)
    scan,_=legacy.load_scan(source)
    brick_dims=np.asarray(scan["source_bbox_m"],dtype=np.float64)
    bricks,_=legacy.layout(brick_dims)
    center_y=np.asarray([bricks[row*legacy.COLS]["center"][1] for row in range(legacy.ROWS)],
                        dtype=np.float64)
    bank_path=destination/"library.bin"
    data=np.memmap(bank_path,dtype="<f4",mode="r+",shape=(catalog["sample_count"],20))
    mortar_counts=[]
    for level in catalog["masters"]["real_scan_wall"]["levels"]:
        start,end=int(level["start"]),int(level["start"]+level["count"])
        v=data[start:end]
        selected=np.where(v[:,9]==MORTAR_FIRST)[0]
        if len(selected)<200:
            raise ValueError("Cannot find authentic wall's procedural joint samples")
        closest=np.argmin(np.abs(v[selected,1,None]-center_y[None,:]),axis=1)
        # New node ID per course; movement only affects procedural mortar,
        # never any SOURCE SCANNED brick XYZ, COLOR_0 or sample radius.
        v[selected,9]=MORTAR_FIRST+closest
        v[selected,2]+=.020-MORTAR_RECESS_M
        v[selected,12:15]=np.clip(v[selected,12:15]+np.array([.035,.039,.042],dtype=np.float32),0,1)
        mortar_counts.append(int(len(selected)))
    data.flush()
    del data
    model=json.loads((destination/"light-model.json").read_text(encoding="utf-8"))
    original_mortar=model["patches"].pop()
    if len(model["patches"])!=MORTAR_FIRST or original_mortar["material"]!="mortar":
        raise ValueError("Unexpected genuine original scanned wall node arrangement")
    face_z=float(max(brick["center"][2] for brick in bricks)+brick_dims[2]*.5-MORTAR_RECESS_M)
    mean_x=float(np.mean([brick["center"][0] for brick in bricks]))
    for row,y in enumerate(center_y):
        patch=original_mortar.copy()
        patch["position"]=[mean_x,float(y),face_z]
        patch["area"]=float(original_mortar["area"])/MORTAR_NODES
        patch["gray_mean"]=.30
        patch["mortar_course"]=int(row)
        patch["micro_id"]=MORTAR_FIRST+row
        model["patches"].append(patch)
    model["direct_shadow_mortar_node"]=MORTAR_FIRST
    model["direct_shadow_mortar_count"]=MORTAR_NODES
    model["mortar_light_provenance"]="8 finite RGB patches at actual mortar rows, not a single wall-wide irradiance code"
    model=legacy.canonical_light_codes(model)
    assert len(model["patches"])==MORTAR_FIRST+MORTAR_NODES
    encoded=(json.dumps(model,indent=2,ensure_ascii=False)+"\n").encode("utf-8")
    (destination/"light-model.json").write_bytes(encoded)
    raw=bank_path.read_bytes()
    catalog["sha256"]=hashlib.sha256(raw).hexdigest()
    catalog["bytes"]=len(raw)
    catalog["lighting"].update({
        "node_count":MORTAR_FIRST+MORTAR_NODES,
        "mortar_nodes":MORTAR_NODES,
        "mortar_light_regions":"one finite patch per course; local RGB code, dynamic",
        "sha256":hashlib.sha256(encoded).hexdigest(),
        "screen_space_reconstruction":"opt-in geometry/depth/normal constrained GPU interior hole recovery",
        "photographic_material_texture_invented":False,
    })
    catalog["wall_layout"]["mortar_recess_m"]=MORTAR_RECESS_M
    catalog["wall_layout"]["mortar_nodes_by_row"]=True
    catalog["wall_layout"]["mortar_samples_per_lod"]=mortar_counts
    catalog["wall_layout"]["scanned_brick_xyz_and_colors_unchanged"]=True
    catalog["hero_quality_accepted"]=False
    catalog["note"]="One invisible box; original scanned bricks; no added geometry; 8 separately lit procedural mortar courses; GPU interior coverage pass optional."
    (destination/"catalog.json").write_text(json.dumps(catalog,indent=2,ensure_ascii=False)+"\n",encoding="utf-8")
    print("LIE-WALL03",catalog["sample_count"],"samples,",
          len(model["patches"]),"material/light nodes,",
          MORTAR_NODES,"mortar rows,",
          catalog["sha256"],flush=True)
    return catalog


if __name__=="__main__":
    ap=argparse.ArgumentParser()
    ap.add_argument("--source",type=Path,default=legacy.SOURCE)
    ap.add_argument("--output",type=Path,default=DEST)
    args=ap.parse_args()
    build(args.source,args.output)
