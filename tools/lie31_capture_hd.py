"""Generate physically displaced PBR-derived brick sample banks for LIE31.

Important provenance: this derives *new* geometry from a photographed CC0
surface displacement map. It does NOT pretend to download or capture the
separately scanned Sketchfab high-poly mesh. All samples are surface normals,
linear reflectance, roughness, 3D positions and face-support bounds; no
source mesh is rendered by the LIE runtime.
"""
from __future__ import annotations

import argparse
from array import array
import hashlib
import json
import math
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
BRICK = (0.24, 0.07, 0.12)
HALF = (0.115, 0.07, 0.12)
MAX_BANK = 64 * 1024 * 1024


def segments(indices):
    if not len(indices):
        return []
    boundaries = np.flatnonzero(np.diff(indices) > 1)
    return [group for group in np.split(indices, boundaries) if len(group)]


def choose_photo_brick(color: np.ndarray) -> tuple[float, float, float, float]:
    """Pick a central red brick face, excluding gray joints by color."""
    thumb = np.asarray(Image.fromarray(color).resize((1024, 1024), Image.Resampling.BILINEAR))
    red = (thumb[:, :, 0] > thumb[:, :, 1] * 1.16) & (
        thumb[:, :, 0] > thumb[:, :, 2] * 1.28) & (thumb[:, :, 0] > 85)
    rows = red.mean(axis=1)
    valid = np.flatnonzero((rows > 0.57) & (np.arange(1024) > 250) & (np.arange(1024) < 770))
    row_spans = [s for s in segments(valid) if len(s) > 12]
    if not row_spans:
        raise ValueError("Cannot isolate red brick row; inspect source photo before capture")
    row = min(row_spans, key=lambda s: abs(float(np.mean(s)) - 490) + 12 / len(s))
    cy = (int(row[0]) + int(row[-1])) // 2
    window = red[max(0, cy-7):min(1024, cy+8)]
    cols = np.flatnonzero(window.mean(axis=0) > 0.68)
    col_spans = [s for s in segments(cols) if 75 < len(s) < 260 and 150 < s[0] < 880]
    if not col_spans:
        raise ValueError("Cannot isolate one complete brick between mortar joints")
    col = min(col_spans, key=lambda s: abs(float(np.mean(s)) - 520))
    x0, x1 = float(col[0]+5)/1024, float(col[-1]-5)/1024
    y0, y1 = float(row[0]+4)/1024, float(row[-1]-4)/1024
    if x1 <= x0 or y1 <= y0:
        raise ValueError("Empty mortar-free crop")
    # Mortar outlines are irregular and extend INSIDE axis-aligned red-row
    # bounds. Inset each candidate further, most aggressively at the upper
    # edge. This protects the hero master from the source wall's gray grout.
    width, tall = x1-x0, y1-y0
    x0 += .07*width
    x1 -= .07*width
    y0 += .26*tall
    y1 -= .08*tall
    if x1 <= x0 or y1 <= y0:
        raise ValueError("Conservative crop eroded away source brick")
    return x0, y0, x1, y1


def bilinear(image: np.ndarray, u, v):
    h, w = image.shape[:2]
    x = np.clip(np.asarray(u)* (w-1), 0, w-1)
    y = np.clip(np.asarray(v)* (h-1), 0, h-1)
    xa, ya = np.floor(x).astype(np.int32), np.floor(y).astype(np.int32)
    xb, yb = np.minimum(xa+1,w-1), np.minimum(ya+1,h-1)
    tx, ty = (x-xa)[..., None], (y-ya)[..., None]
    return (image[ya, xa]*(1-tx)*(1-ty)+image[ya, xb]*tx*(1-ty)+
            image[yb, xa]*(1-tx)*ty+image[yb, xb]*tx*ty)


def linear(rgb):
    return np.where(rgb <= .04045, rgb/12.92, ((rgb+.055)/1.055)**2.4)


def load_maps(directory: Path) -> dict:
    maps={}
    lock=json.loads((ROOT / "evidence/LIE31-source-lock.json").read_text())
    for name,record in lock["files"].items():
        path=directory/record["filename"]
        if hashlib.sha256(path.read_bytes()).hexdigest()!=record["sha256"]:
            raise ValueError(f"Source drift: {name}")
        with Image.open(path) as im:
            maps[name]=np.asarray(im.convert("RGB"),dtype=np.float32)/255
    return maps


def emit_face(data: array, maps: dict, rect: tuple[float,float,float,float],
              dims: tuple[float,float,float], face: str, nx: int, ny: int,
              radius_scale: float, material_zone: int):
    length, height, depth = dims
    # Every emitted sample is 20 float32 elements / 80 bytes, matching LIE28.
    left, top, right, bottom = rect
    xx = (np.arange(nx,dtype=np.float32)+.5)/nx
    yy = (np.arange(ny,dtype=np.float32)+.5)/ny
    u,v=np.meshgrid(xx, yy, indexing="xy")
    uvx = left + (right-left)*u
    uvy = top+(bottom-top)*v
    color = linear(bilinear(maps["color"], uvx,uvy))
    normal_raw = bilinear(maps["normal"],uvx,uvy)*2-1
    height_raw = bilinear(maps["height"], uvx,uvy)[:,:,0]
    rough = bilinear(maps["roughness"], uvx,uvy)[:,:,0]
    height_offset=(height_raw-.5)*.005
    # Convert measured tangent-space normals and topological displacement to
    # a stable face-major normal. The face axis remains dominant, preserving
    # LIE's source face-support clipping.
    dx = np.clip(normal_raw[:,:,0],-.7,.7)*.24
    dy = np.clip(normal_raw[:,:,1],-.7,.7)*.24
    zero=np.zeros_like(u)
    one=np.ones_like(u)
    if face=="front":
        px=(u-.5)*length; py=(.5-v)*height; pz=depth/2+height_offset
        normal=np.stack([dx,dy,one],axis=-1)
        bounds=(-length/2,-height/2,length/2,height/2)
        spacing=max(length/nx,height/ny)
    elif face=="back":
        px=(.5-u)*length; py=(.5-v)*height; pz=-depth/2-height_offset*.6
        normal=np.stack([-dx,dy,-one],axis=-1)
        bounds=(-length/2,-height/2,length/2,height/2)
        spacing=max(length/nx,height/ny)
    elif face in ("top","bottom"):
        px=(u-.5)*length; pz=(v-.5)*depth
        py=(height/2+height_offset*.5) if face=="top" else (-height/2-height_offset*.2)
        normal=np.stack([dx,one if face=="top" else -one,dy],axis=-1)
        bounds=(-length/2,-depth/2,length/2,depth/2)
        spacing=max(length/nx,depth/ny)
    else:
        pz=(u-.5)*depth; py=(.5-v)*height
        px=(length/2+height_offset*.3) if face=="right" else (-length/2-height_offset*.3)
        normal=np.stack([one if face=="right" else -one,dy,dx],axis=-1)
        bounds=(-depth/2,-height/2,depth/2,height/2)
        spacing=max(depth/nx,height/ny)
    normal=normal / np.maximum(np.linalg.norm(normal,axis=-1,keepdims=True),1e-6)
    # Smaller sample support than the actual brick face prevents covering joints.
    radius=spacing*radius_scale
    if radius<=0 or not np.isfinite(radius):
        raise ValueError("Nonfinite sample radius")
    arr=np.stack([px,py,pz,np.full_like(px,radius),
                  normal[:,:,0],normal[:,:,1],normal[:,:,2],one,
                  np.full_like(px,material_zone),zero,np.clip(rough,.2,.98),zero,
                  color[:,:,0],color[:,:,1],color[:,:,2],one,
                  np.full_like(px,bounds[0]),np.full_like(px,bounds[1]),
                  np.full_like(px,bounds[2]),np.full_like(px,bounds[3])],axis=-1)
    if not np.isfinite(arr).all():
        raise ValueError("Nonfinite PBR samples")
    data.frombytes(arr.astype("<f4",copy=False).tobytes())
    return nx*ny


def make_master(maps, rect, dims, dense):
    data=array("f")
    # Dense source captures >50k samples; wall-level captures 2-4k samples.
    if dense:
        configs={"front":(260,100),"back":(100,40),"top":(120,50),
                 "bottom":(55,24),"left":(40,40),"right":(40,40)}
    else:
        configs={"front":(64,24),"back":(32,12),"top":(48,16),
                 "bottom":(24,10),"left":(20,16),"right":(20,16)}
    # Halves receive proportional horizontal density.
    ratio=dims[0]/BRICK[0]
    counts={}
    for face,(w,h) in configs.items():
        if face in ("front","back","top","bottom"):
            w=max(12,int(round(w*ratio)))
        counts[face]=emit_face(data,maps,rect,dims,face,w,h,
                               radius_scale=.85 if dense else 1.12,material_zone=3)
    return data, counts


def build(directory: Path, destination: Path):
    maps=load_maps(directory)
    color=(maps["color"]*255).clip(0,255).astype(np.uint8)
    rect=choose_photo_brick(color)
    destination.mkdir(parents=True,exist_ok=True)
    full_crop=color[int(rect[1]*color.shape[0]):int(rect[3]*color.shape[0]),
                    int(rect[0]*color.shape[1]):int(rect[2]*color.shape[1])]
    Image.fromarray(full_crop).resize((1200,300)).save(destination/"SOURCE_BRICK_CROP.png")
    brick_mask=(full_crop[:,:,0]>full_crop[:,:,1]*1.16)&(full_crop[:,:,0]>full_crop[:,:,2]*1.28)
    grout_fraction=1.0-float(brick_mask.mean())
    top_fraction=float(brick_mask[:max(1,full_crop.shape[0]//6)].mean())
    print("LIE31 photo crop: mortar-like pixel fraction",round(grout_fraction,4),
          "top red fraction",round(top_fraction,4),flush=True)
    if grout_fraction>.16 or top_fraction<.75:
        raise ValueError("Selected brick photograph includes too much visible mortar")
    samples=array("f")
    masters={}
    for name,dims in (("brick",BRICK),("half_brick",HALF)):
        levels=[]
        for dense in (True,False):
            master_samples, counts=make_master(maps,rect,dims,dense)
            if len(master_samples)%20:
                raise ValueError("Unaligned samples")
            level={"start":len(samples)//20,"count":len(master_samples)//20,
                   "face_counts":counts}
            samples.extend(master_samples)
            levels.append({"start":level["start"],"count":level["count"]})
            print("LIE31",name,"dense" if dense else "wall",level,flush=True)
        masters[name]={"levels":levels,"bounds_size":list(dims),
                       "origin_offset":[0,0,0]}
    # Keep native LIE30 source mortar, still mapped to the "concrete_panel"
    # master. This small capture preserves the same 127-instance scene shape.
    catalog30=json.loads((ROOT/"gpu_compute/captures/lie30masonry/catalog.json").read_text())
    parent=(ROOT/"gpu_compute/captures/lie30masonry/library.bin").read_bytes()
    mortar=catalog30["masters"]["concrete_panel"]["levels"][1]
    begin=mortar["start"]*80
    end=begin+mortar["count"]*80
    mortar_data=parent[begin:end]
    start=len(samples)//20
    samples.frombytes(mortar_data)
    masters["concrete_panel"]={"levels":[{"start":start,"count":mortar["count"]}]*2,
                                "bounds_size":[1.,.8,.12],
                                "origin_offset":[0,0,0]}
    raw=samples.tobytes()
    if len(raw)>MAX_BANK:
        raise ValueError("LIE31 capture bank >64 MB")
    sha=hashlib.sha256(raw).hexdigest()
    (destination/"library.bin").write_bytes(raw)
    meta={"schema":1,"stride":80,"sample_count":len(samples)//20,
          "sha256":sha,"bytes":len(raw),
          "original_mesh_drawn":False,
          "geometry_source":"Height/displacement-derived individual brick surfaces, not a downloaded 3D scan",
          "photographic_source":"https://polyhaven.com/a/red_brick",
          "license":"CC0 1.0","source_resolution":4096,
          "crop_uv":[round(z,8) for z in rect],"masters":masters}
    (destination/"catalog.json").write_text(json.dumps(meta,indent=2))
    print("LIE31 HD BANK",meta["sample_count"],len(raw),sha,flush=True)
    return meta


if __name__=="__main__":
    p=argparse.ArgumentParser()
    p.add_argument("--source",type=Path,required=True)
    p.add_argument("--output",type=Path,
                   default=ROOT/"gpu_compute/captures/lie31hd")
    args=p.parse_args()
    print(json.dumps(build(args.source,args.output),indent=2))
