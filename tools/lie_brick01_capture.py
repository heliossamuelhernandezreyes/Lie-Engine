"""LIE-BRICK-01: authored source photo -> physically irregular LIE brick samples.

This is a genuine native LIE sample bank made from Poly Haven's CC0 Red Brick
4096px PBR maps; it is NOT an independently photogrammetry-scanned 3D brick.
Only ONE hidden BoxShape3D is needed per active brick in the native Godot lab.
Chipped edges, nonplanar normals and corner damage are encoded in visible LIE
samples and must never be substituted by drawn triangles/collision triangles.
"""
from __future__ import annotations
from array import array
import argparse
import hashlib
import json
from pathlib import Path

import numpy as np
from PIL import Image

from lie31_capture_hd import BRICK, HALF, MAX_BANK, bilinear, choose_photo_brick, linear, load_maps

ROOT=Path(__file__).resolve().parents[1]
PROFILES={
  "hero":{"front":(370,200),"back":(250,125),"top":(300,150),
          "bottom":(120,70),"left":(175,130),"right":(175,130)},
  "mid":{"front":(130,70),"back":(100,45),"top":(130,54),
         "bottom":(55,20),"left":(67,45),"right":(67,45)},
  "wall":{"front":(62,24),"back":(28,12),"top":(37,17),
          "bottom":(18,10),"left":(20,14),"right":(20,14)}
}
FACES=("front","back","top","bottom","left","right")
DIMS={"brick_full":BRICK,"brick_half":HALF}


def normalize(a):
    return a/np.maximum(np.linalg.norm(a,axis=-1,keepdims=True),1e-8)


def clustered_grid(n):
    """Cosine distribution concentrates samples around edges/corners."""
    t=(np.arange(n,dtype=np.float32)+.5)/n
    return (.5-.5*np.cos(np.pi*t)).astype(np.float32)


def bake_face(maps,rect,dims,face,nx,ny,hero):
    length,height,depth=dims
    u,v=np.meshgrid(clustered_grid(nx),clustered_grid(ny))
    zero=np.zeros_like(u);one=np.ones_like(u)
    if face=="front":
        xyz=[(u-.5)*length,(.5-v)*height,one*depth/2]
        outward=np.array([0,0,1],dtype=np.float32);tanu=np.array([1,0,0]);tanv=np.array([0,-1,0])
        spacing=max(length/nx,height/ny)
    elif face=="back":
        xyz=[(.5-u)*length,(.5-v)*height,-one*depth/2]
        outward=np.array([0,0,-1],dtype=np.float32);tanu=np.array([-1,0,0]);tanv=np.array([0,-1,0])
        spacing=max(length/nx,height/ny)
    elif face=="top":
        xyz=[(u-.5)*length,one*height/2,(v-.5)*depth]
        outward=np.array([0,1,0],dtype=np.float32);tanu=np.array([1,0,0]);tanv=np.array([0,0,1])
        spacing=max(length/nx,depth/ny)
    elif face=="bottom":
        xyz=[(u-.5)*length,-one*height/2,(v-.5)*depth]
        outward=np.array([0,-1,0],dtype=np.float32);tanu=np.array([1,0,0]);tanv=np.array([0,0,1])
        spacing=max(length/nx,depth/ny)
    elif face=="left":
        xyz=[-one*length/2,(.5-v)*height,(u-.5)*depth]
        outward=np.array([-1,0,0],dtype=np.float32);tanu=np.array([0,0,1]);tanv=np.array([0,-1,0])
        spacing=max(depth/nx,height/ny)
    else:
        xyz=[one*length/2,(.5-v)*height,(u-.5)*depth]
        outward=np.array([1,0,0],dtype=np.float32);tanu=np.array([0,0,1]);tanv=np.array([0,-1,0])
        spacing=max(depth/nx,height/ny)
    p=np.stack(xyz,axis=-1).astype(np.float32)
    plane_axis=int(np.argmax(abs(outward)))
    tangent_axes=[axis for axis in range(3) if axis!=plane_axis]
    sizes=np.array([length,height,depth],dtype=np.float32)/2
    edge_d1=np.maximum(sizes[tangent_axes[0]]-np.abs(p[...,tangent_axes[0]]),0)
    edge_d2=np.maximum(sizes[tangent_axes[1]]-np.abs(p[...,tangent_axes[1]]),0)
    # Physical bevel across all six faces. The displacement depends on the
    # point's other-two-axes distances to their ends, not a painted normal.
    edge_weight=np.exp(-np.minimum(edge_d1,edge_d2)/.0034)
    world_phase=(np.sin(p[...,0]*137+p[...,1]*97+p[...,2]*119)
                 +.22*np.sin(p[...,0]*607-p[...,2]*311+p[...,1]*287))
    # Smooth, damaged clay contours rather than periodic sawtooth edges.
    bevel=(.00115+.00024*world_phase)*edge_weight
    corner_weight=np.exp(-edge_d1/.007-edge_d2/.006)
    bevel+=.0010*corner_weight
    # The front/top/left corner is chipped on every adjacent face, not
    # simulated by changing the collision shape.
    distance=np.sqrt(((p[...,0]+length/2)/.012)**2+
                     ((height/2-p[...,1])/.009)**2+
                     ((depth/2-p[...,2])/.011)**2)
    chipped=.0037*np.maximum(1-distance,0)**1.45
    # Non-uniform side/top erosion continues around edges. Color/height
    # detail comes from the original photographed PBR material.
    left,top,right,bottom=rect
    face_index=FACES.index(face)
    pad_x=.035*(right-left);pad_y=.045*(bottom-top)
    xleft=left+pad_x*(1+(face_index%3)*.18)
    xright=right-pad_x*(1+(face_index%2)*.12)
    ytop=top+pad_y*(1+(face_index%2)*.14)
    ybottom=bottom-pad_y
    photo_u=xleft+(xright-xleft)*u
    photo_v=ytop+(ybottom-ytop)*v
    pigment=linear(bilinear(maps["color"],photo_u,photo_v))
    rough=np.clip(bilinear(maps["roughness"],photo_u,photo_v)[...,0],.22,.97)
    heightmap=bilinear(maps["height"],photo_u,photo_v)[...,0]
    original_normal=bilinear(maps["normal"],photo_u,photo_v)*2-1
    displacement=(heightmap-.5)*(.005 if hero else .004)
    # Remove material at chipped corners and beveled edges; retained source
    # height is independent of the collider geometry.
    offset=displacement-bevel-chipped
    p+=offset[...,None]*outward
    du=np.gradient(p,axis=1)
    dv=np.gradient(p,axis=0)
    geom=normalize(np.cross(du,dv))
    if np.mean(np.sum(geom*outward,axis=-1))<0:geom=-geom
    pbr=normalize(np.maximum(original_normal[...,2,None],.3)*outward
                  +original_normal[...,0,None]*tanu*.27
                  +original_normal[...,1,None]*tanv*.27)
    normal=normalize(geom*.75+pbr*.25)
    # Original LIE face support uses local axis pair selected by max normal
    # component. Restrict projection to physical face domains. For beveled
    # corners, per-sample support is intentionally tight to avoid filling
    # eroded silhouettes with large neighbouring sample discs.
    # Nonuniform cosine-spaced sampling REQUIRES varying splat radii.
    # Uniform radii in v1 left visible dotted holes in the top surface,
    # even with >200K source samples. Use physical neighbour separation.
    local_cell_u=np.linalg.norm(du,axis=-1)
    local_cell_v=np.linalg.norm(dv,axis=-1)
    radius=np.clip(np.maximum(local_cell_u,local_cell_v)*
                   (1.12 if hero else 1.28),.00015,.012)
    local_support=np.zeros((*u.shape,4),dtype=np.float32)
    dominant=np.argmax(np.abs(normal),axis=-1)
    for axis,(a,b) in enumerate(((2,1),(0,2),(0,1))):
        sel=dominant==axis
        footprint=radius[sel]*1.6
        local_support[sel,0]=p[sel,a]-footprint
        local_support[sel,1]=p[sel,b]-footprint
        local_support[sel,2]=p[sel,a]+footprint
        local_support[sel,3]=p[sel,b]+footprint
    out=np.zeros((*u.shape,20),dtype="<f4")
    out[...,0:3]=p
    out[...,3]=radius
    out[...,4:7]=normal
    out[...,7]=1
    out[...,8]=3
    out[...,10]=rough
    out[...,12:15]=np.clip(pigment,0,1)
    out[...,15]=1
    out[...,16:20]=local_support
    if not np.isfinite(out).all():raise ValueError("Nonfinite PBR samples")
    return out.reshape(-1,20),{
        "samples":int(nx*ny),
        "max_edge_cut_mm":round(float(np.max(bevel)*1000),4),
        "max_corner_cut_mm":round(float(np.max(chipped)*1000),4),
        "position_variation_mm":round(float(np.std(offset)*1000),4)
    }


def build(source:Path,destination:Path):
    maps=load_maps(source)
    color=(maps["color"]*255).clip(0,255).astype(np.uint8)
    rect=choose_photo_brick(color)
    destination.mkdir(parents=True,exist_ok=True)
    bank=array("f");masters={};face_report={}
    for master,dims in DIMS.items():
        levels=[];face_report[master]={}
        for profile_name,profile in PROFILES.items():
            start=len(bank)//20
            count=0
            face_report[master][profile_name]={}
            for face in FACES:
                nx,ny=profile[face]
                if face in ("front","back","top","bottom"):
                    nx=max(12,round(nx*(dims[0]/BRICK[0])))
                arr,stats=bake_face(maps,rect,dims,face,nx,ny,
                                    hero=profile_name=="hero")
                bank.frombytes(arr.tobytes());count+=len(arr)
                face_report[master][profile_name][face]=stats
            levels.append({"start":start,"count":count})
            print("LIE-BRICK01",master,profile_name,count,flush=True)
        masters[master]={"levels":levels,"bounds_size":list(dims),
                         "origin_offset":[0,0,0],
                         "collision_proxy":"exactly one BoxShape3D"}
    raw=bank.tobytes()
    if len(raw)>MAX_BANK:raise ValueError("Sample bank exceeded 64MiB cap")
    sha=hashlib.sha256(raw).hexdigest()
    (destination/"library.bin").write_bytes(raw)
    metadata={
        "schema":1,"stride":80,"sample_count":len(bank)//20,
        "bytes":len(raw),"sha256":sha,
        "masters":masters,"face_sample_report":face_report,
        "source":"CC0 Poly Haven Red Brick original photographic 4K albedo/normal/height/roughness",
        "source_url":"https://polyhaven.com/a/red_brick",
        "license":"CC0 1.0",
        "geometry":"LIE physically displaced and procedurally eroded six-faced surfaces",
        "source_mesh_drawn":False,"scanned_individual_3d_mesh":False,
        "collision_proxy_count_per_active_brick":1,
        "hero_quality_accepted":False,
        "quality_caveat":"Native validation of shape is mandatory; never imply photo-indistinguishability without photo A/B test",
        "crop_uv":[float(x) for x in rect]}
    (destination/"catalog.json").write_text(json.dumps(metadata,indent=2))
    print("LIE-BRICK01 bank",len(bank)//20,"samples",len(raw),"bytes",sha,flush=True)
    return metadata


if __name__=="__main__":
    parser=argparse.ArgumentParser()
    parser.add_argument("--source",required=True,type=Path)
    parser.add_argument("--output",type=Path,
                        default=ROOT/"gpu_compute/captures/liebrick01")
    opt=parser.parse_args()
    build(opt.source,opt.output)
