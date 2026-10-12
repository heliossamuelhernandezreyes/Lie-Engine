"""Bake immutable seeded LIE32 wall clusters from real LIE31 PBR samples.

One baked module contains brick positions, source normals, PBR albedo/roughness
and face-support bounds in a SINGLE master range. LIE32 renders four shared
variants as 1 job each, instead of 127 per-brick jobs. Geometry and collisions
stay available in LIE31 for interactive/destructible close-range walls.
The benchmark MUST measure visual loss, VRAM and time; sample-count reduction
alone is not proof of faster physical-GPU rendering.
"""
from __future__ import annotations

from array import array
import hashlib
import json
from pathlib import Path

import numpy as np

ROOT=Path(__file__).resolve().parents[1]
BASE=ROOT/"gpu_compute/captures/lie31hd"
DEST=ROOT/"gpu_compute/captures/lie32cluster"
VARIANTS=4
EXPECTED_STRIDE=80
# Deterministic face-balanced subsampling per brick; preserve six sides.
FACE_BUDGET={"front":90,"back":24,"top":28,"bottom":8,"left":11,"right":11}
FACES={"front":(64,24),"back":(32,12),"top":(48,16),
       "bottom":(24,10),"left":(20,16),"right":(20,16)}


def hash32(x):
    x &= 0xffffffff
    x ^= x >> 16
    x = (x*0x7feb352d)&0xffffffff
    x ^= x >> 15
    x = (x*0x846ca68b)&0xffffffff
    return (x^(x>>16)) & 0xffffffff


def rnd(seed,row,col,channel):
    return hash32((seed*0x9e3779b1)^(row*0x85ebca77)^
                  (col*0xc2b2ae3d)^(channel*0x27d4eb2f))/4294967295.0


def tint(seed,row,col):
    tone=1.0+.12*(2*rnd(seed,row,col,0)-1)
    rough=.06*(2*rnd(seed,row,col,1)-1)
    palette=min(int(rnd(seed,row,col,2)*3),2)
    vals=[(1.08,1.00,.98),(.99,.95,.94),(1.14,1.04,1.01)][palette]
    return np.array(vals,dtype=np.float32)*tone,rough


def select_face_balanced(samples,half):
    offsets=[]
    start=0
    for face,(nx,ny) in FACES.items():
        if face in ("front","back","top","bottom"):
            nx=max(12,round(nx*(.115/.24))) if half else nx
        count=nx*ny
        available=min(count,FACE_BUDGET[face])
        subset=start+np.linspace(0,count-1,available).astype(np.int64)
        offsets.extend(subset.tolist())
        start+=count
    if start!=len(samples):
        raise ValueError(f"Unexpected PBR source face layout: {start}!={len(samples)}")
    return samples[np.array(offsets,dtype=np.int64)].copy()


def transform(samples,position,scale=(1.,1.,1.),rgb=None,rough_offset=0,inflate=1):
    result=samples.copy()
    position=np.asarray(position,dtype=np.float32)
    scale=np.asarray(scale,dtype=np.float32)
    result[:,0:3]=result[:,0:3]*scale +position
    result[:,3]=result[:,3]*inflate*float(np.max(scale))
    if rgb is not None:
        result[:,12:15]=np.clip(result[:,12:15]*rgb,0,1)
    result[:,10]=np.clip(result[:,10]+rough_offset,.2,.98)
    normals=np.argmax(np.abs(result[:,4:7]),axis=1)
    # LIE source-face clipping projects to YZ (normal X), XZ (normal Y),
    # or XY (normal Z). Translate original support rectangles accordingly.
    for axis,(a,b) in enumerate(((2,1),(0,2),(0,1))):
        selection=normals==axis
        if selection.any():
            result[selection,16] = result[selection,16]*scale[a]+position[a]
            result[selection,18] = result[selection,18]*scale[a]+position[a]
            result[selection,17] = result[selection,17]*scale[b]+position[b]
            result[selection,19] = result[selection,19]*scale[b]+position[b]
    return result


def build(root=BASE, output=DEST):
    catalog=json.loads((root/"catalog.json").read_text())
    raw=(root/"library.bin").read_bytes()
    if hashlib.sha256(raw).hexdigest()!=catalog["sha256"]:
        raise ValueError("LIE31 source bank corrupted")
    src=np.frombuffer(raw,dtype="<f4").reshape(-1,20)
    originals={}
    for name in ("brick","half_brick"):
        level=catalog["masters"][name]["levels"][1]
        subset=src[level["start"]:level["start"]+level["count"]]
        originals[name]=select_face_balanced(subset,half=(name=="half_brick"))
    slabmeta=catalog["masters"]["concrete_panel"]["levels"][1]
    slab=src[slabmeta["start"]:slabmeta["start"]+slabmeta["count"]]
    slab=slab[np.linspace(0,len(slab)-1,960).astype(np.int32)].copy()
    bank=array("f")
    master_catalog={}
    variant_digests=[]
    for variant in range(VARIANTS):
        seed=29+variant*7919
        patches=[]
        # Recessed joint underlayer: the same material captured by LIE30.
        patches.append(transform(slab,(0,.48,.05),(2.5,1.2,.05),
                                 rgb=(.58,.51,.44),rough_offset=.03,inflate=2.0))
        for row in range(12):
            y=(row+.5)*.08
            if row%2==0:
                placements=[("brick",(col-4.5)*.25,col) for col in range(10)]
            else:
                placements=[("half_brick",-1.1875,0)]+[
                    ("brick",(col-4.0)*.25,col+1) for col in range(9)]+[
                    ("half_brick",1.1875,10)]
            for name,x,col in placements:
                rgb,rough=tint(seed,row,col)
                samples=transform(originals[name],(x,y,0),rgb=rgb,
                                  rough_offset=rough,inflate=2.7)
                patches.append(samples)
        combined=np.concatenate(patches).astype("<f4")
        if not np.isfinite(combined).all():
            raise ValueError("Invalid combined samples")
        start=len(bank)//20
        bank.frombytes(combined.tobytes())
        count=len(combined)
        name=f"wall_variant_{variant}"
        master_catalog[name]={
            "levels":[{"start":start,"count":count}]*2,
            "bounds_size":[2.5,.96,.12],
            "origin_offset":[0,0,0],
            "seed":seed,
            "source_brick_count":126,
            "sample_count_per_brick_approx":len(originals["brick"]),
        }
        digest=hashlib.sha256(combined.tobytes()).hexdigest()
        variant_digests.append(digest)
        print("LIE32 bake",name,"samples",count,"sha256",digest,flush=True)
    raw=bank.tobytes()
    output.mkdir(parents=True,exist_ok=True)
    (output/"library.bin").write_bytes(raw)
    metadata={
        "schema":1,"stride":80,"sample_count":len(bank)//20,
        "sha256":hashlib.sha256(raw).hexdigest(),"bytes":len(raw),
        "source_master_sha256":catalog["sha256"],
        "source":"LIE31-Hd Poly Haven photographed CC0 relief samples",
        "type":"prebaked multi-brick PBR shared wall master",
        "license":"CC0-1.0",
        "masters":master_catalog,
        "variant_sha256":variant_digests,
        "limitations":"Downsampled source samples; visual comparison required",
    }
    (output/"catalog.json").write_text(json.dumps(metadata,indent=2))
    return metadata


if __name__=="__main__":
    m=build()
    print("LIE32 JOINT MASTERS",m["sample_count"],m["bytes"],m["sha256"])
