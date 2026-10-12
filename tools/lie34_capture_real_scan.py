"""LIE34: capture REAL 5.5M-triangle Draco photogrammetry into neutral LIE samples.

Original source: Matthew Guertin, Drone Building Scans, CC BY 4.0.
This is a *building/facade*, NOT an individual photogrammetry-scanned brick.
Reconstructs material albedo via source UV and original embedded textures.
The original 3D mesh is NEVER rendered by the LIE compositor: only new
source-sampled surface records, with 80-byte LIE layout and reproducible seeds.
"""
from __future__ import annotations
from array import array
import hashlib
import io
import json
import math
import struct
from pathlib import Path
import numpy as np
from PIL import Image

ROOT=Path(__file__).resolve().parents[1]
SOURCE=ROOT/"gpu_compute/assets/lie34"
OUTPUT=ROOT/"gpu_compute/captures/lie34scan"
SOURCE_CREDIT="Drone Building Scans — Matthew Guertin, 2026. CC BY 4.0."
STRIDE=80
SAMPLE_COUNTS=(540000,120000)


def unpack_glb(path):
    blob=path.read_bytes()
    if blob[:4]!=b"glTF":raise ValueError("Expected GLB")
    n,kind=struct.unpack_from("<II",blob,12)
    if kind!=0x4e4f534a:raise ValueError("First chunk must be JSON")
    doc=json.loads(blob[20:20+n].decode("utf-8").strip())
    binary_size,kind=struct.unpack_from("<II",blob,20+n)
    if kind!=0x004e4942:raise ValueError("Expected GLB BIN chunk")
    return doc,blob[28+n:28+n+binary_size]


def payload_from_view(doc,binchunk,index):
    v=doc["bufferViews"][index]
    off=v.get("byteOffset",0)
    return binchunk[off:off+v["byteLength"]]


def texture_from_material(doc,binchunk,primitive,key):
    mat=doc["materials"][primitive["material"]]
    pbr=mat.get("pbrMetallicRoughness",{})
    if key=="albedo": rec=pbr.get("baseColorTexture")
    else:rec=pbr.get("metallicRoughnessTexture")
    if rec is None:return None
    image_idx=doc["textures"][rec["index"]]["source"]
    descriptor=doc["images"][image_idx]
    if "bufferView" not in descriptor:
        raise ValueError("Only embedded GLB textures currently supported")
    raw=payload_from_view(doc,binchunk,descriptor["bufferView"])
    with Image.open(io.BytesIO(raw)) as im:
        return np.asarray(im.convert("RGB"),dtype=np.uint8)


def sample_texture(pixels,uv):
    if pixels is None:
        raise ValueError("Missing photographic texture")
    height,width=pixels.shape[:2]
    tex=np.mod(uv,1.)
    x=np.minimum(np.floor(tex[:,0]*(width-1)).astype(np.intp),width-1)
    y=np.minimum(np.floor((1.-tex[:,1])*(height-1)).astype(np.intp),height-1)
    return pixels[y,x].astype(np.float32)/255.


def linear(rgb):
    return np.where(rgb<=.04045,rgb/12.92,((rgb+.055)/1.055)**2.4)


def face_areas(points,faces):
    result=np.empty(len(faces),dtype=np.float64)
    batch=150000
    for k in range(0,len(faces),batch):
        f=faces[k:k+batch]
        a=points[f[:,0]]
        ab=points[f[:,1]]-a
        ac=points[f[:,2]]-a
        result[k:k+batch]=.5*np.linalg.norm(np.cross(ab,ac),axis=1)
    return result


def encode_samples(points,faces,vertex_normals,texcoords,albedo,rough_texture,
                   source_dims,source_center,count,seed):
    rng=np.random.default_rng(seed)
    area=face_areas(points,faces)
    total=np.sum(area)
    if not np.isfinite(total) or total<.01:raise ValueError("Degenerate source area")
    cumulative=np.cumsum(area)
    cumulative/=cumulative[-1]
    selected=np.searchsorted(cumulative,rng.random(count),side="left")
    f=faces[selected]
    v=rng.random(count)
    s=np.sqrt(rng.random(count))
    weight=np.column_stack((1.-s,s*(1.-v),s*v)).astype(np.float32)
    pos=np.sum(points[f]*weight[:,:,None],axis=1)
    normals=np.sum(vertex_normals[f]*weight[:,:,None],axis=1)
    lens=np.linalg.norm(normals,axis=1,keepdims=True)
    normals/=np.maximum(lens,1e-6)
    uv=np.sum(texcoords[f]*weight[:,:,None],axis=1)
    rgb=linear(sample_texture(albedo,uv))
    if rough_texture is not None:
        rough=np.clip(sample_texture(rough_texture,uv)[:,1],.2,.98)
    else:rough=np.full(count,.82,dtype=np.float32)

    # Original scan Z-up -> Godot/LIE Y-up; rotate without distorting its
    # 3D geometry. Normalize the largest horizontal span to 3 meters.
    span=np.asarray(source_dims,dtype=np.float32)
    scale=3.0/max(float(span[0]),float(span[1]))
    local=(pos-np.asarray(source_center,dtype=np.float32))*scale
    world=np.column_stack((local[:,0],local[:,2],-local[:,1])).astype(np.float32)
    nr=np.column_stack((normals[:,0],normals[:,2],-normals[:,1])).astype(np.float32)

    radius=np.clip(np.sqrt(total/max(count,1))*scale*1.05,.001,.045)
    support=np.zeros((count,4),dtype=np.float32)
    dominant=np.argmax(np.abs(nr),axis=1)
    for axis,(a,b) in enumerate(((2,1),(0,2),(0,1))):
        select=dominant==axis
        q=world[select][:,[a,b]]
        support[select,:2]=q-radius*2.5
        support[select,2:]=q+radius*2.5
    out=np.zeros((count,20),dtype="<f4")
    out[:,:3]=world
    out[:,3]=radius
    out[:,4:7]=nr
    out[:,7]=1.
    out[:,8]=3.  # clay/stone PBR surface zone
    out[:,10]=rough
    out[:,12:15]=rgb
    out[:,15]=1.
    out[:,16:20]=support
    if not np.isfinite(out).all() or (out[:,3]<=0).any():
        raise ValueError("Non-finite surface captures")
    return out,total,radius,scale


def capture(glb:Path,destination:Path=OUTPUT):
    import DracoPy
    lock=json.loads((glb.parent/"source-lock.json").read_text())
    if hashlib.sha256(glb.read_bytes()).hexdigest()!=lock["original_sha256"]:
        raise ValueError("Photogrammetry GLB changed since acquisition")
    doc,binchunk=unpack_glb(glb)
    primitive=doc["meshes"][0]["primitives"][0]
    ext=primitive["extensions"]["KHR_draco_mesh_compression"]
    compressed=payload_from_view(doc,binchunk,ext["bufferView"])
    decoded=DracoPy.decode(compressed)
    points=np.asarray(decoded.points,dtype=np.float32)
    faces=np.asarray(decoded.faces,dtype=np.int32)
    vn=np.asarray(decoded.normals,dtype=np.float32)
    uv=np.asarray(decoded.tex_coord,dtype=np.float32)
    if len(points)!=2994426 or len(faces)!=5500320:
        raise ValueError("Unexpected real 3D source geometry; do not silently replace asset")
    if len(vn)!=len(points) or len(uv)!=len(points):
        raise ValueError("Missing photogrammetry normals or source UVs")
    if not np.isfinite(points).all() or not np.any(np.ptp(points,axis=0)>.1):
        raise ValueError("Degenerate compressed scan")
    albedo=texture_from_material(doc,binchunk,primitive,"albedo")
    if albedo is None:raise ValueError("Missing original photo atlas")
    rough=texture_from_material(doc,binchunk,primitive,"roughness")
    print("LIE34 SOURCE",len(points),"vertices",len(faces),"triangles",
          "original albedo",albedo.shape,"roughmap",None if rough is None else rough.shape,flush=True)
    min_pos=np.min(points,axis=0)
    max_pos=np.max(points,axis=0)
    center=(min_pos+max_pos)/2
    dims=max_pos-min_pos
    destination.mkdir(parents=True,exist_ok=True)
    master_ranges=[]
    bank=array("f")
    info=[]
    for lod,count in enumerate(SAMPLE_COUNTS):
        arr,area,radius,scale=encode_samples(points,faces,vn,uv,albedo,rough,dims,center,count,seed=342+lod)
        master_ranges.append({"start":len(bank)//20,"count":len(arr)})
        bank.frombytes(arr.tobytes())
        info.append({"points":len(arr),"radius_m":float(radius),
                     "raw_surface_area":float(area),"scale":float(scale)})
        print("LIE34 CAPTURE",lod,len(arr),"radius",radius,flush=True)
    source_extents=(dims*info[0]["scale"]).tolist()
    source_extents=[source_extents[0],source_extents[2],source_extents[1]]
    raw=bank.tobytes()
    if len(raw)>64*1024*1024:raise ValueError("LIE bank too big")
    metadata={
        "schema":1,"stride":80,"sample_count":len(bank)//20,
        "bytes":len(raw),"sha256":hashlib.sha256(raw).hexdigest(),
        "source_original_triangles":len(faces),
        "source_original_vertices":len(points),
        "photogrammetric_source":lock["original_source_url"],
        "original_glb_sha256":lock["original_sha256"],
        "credit":SOURCE_CREDIT,
        "license":"CC BY 4.0",
        "source_object":"Photogrammetry of an entire building, not a single brick",
        "source_albedo_dimensions":[int(albedo.shape[1]),int(albedo.shape[0])],
        "source_mesh_drawn":False,
        "sampling_info":info,
        "masters":{"scan_building":{"levels":master_ranges,
                 "bounds_size":source_extents,
                 "origin_offset":[0,0,0]}}
    }
    (destination/"library.bin").write_bytes(raw)
    (destination/"catalog.json").write_text(json.dumps(metadata,indent=2))
    print("LIE34 TRUE SCAN SAMPLE BANK",len(bank)//20,hashlib.sha256(raw).hexdigest(),flush=True)
    return metadata


if __name__=="__main__":
    import argparse
    ap=argparse.ArgumentParser()
    ap.add_argument("--source",type=Path,required=True)
    ap.add_argument("--output",type=Path,default=OUTPUT)
    args=ap.parse_args()
    capture(args.source,args.output)
