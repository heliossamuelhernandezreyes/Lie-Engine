"""Compile opaque captured disks into layered, six-direction surface fields.

This is a different representation, not an exact replacement for LIE's integer
material reductions. No photographs or meshes are synthesized. Missing cells
stay empty; additional layers and discarded/back-facing records are counted.
"""
import argparse
import hashlib
import json
import math
from pathlib import Path
import numpy as np

ROOT = Path(__file__).resolve().parents[1]
BANK_SHA = 'ca667dfc0e5f5de19190ef12c24395a99b2be66a418420bf30e61ba9ef253340'
LAYERS = 4

def sha(blob):
    return hashlib.sha256(blob).hexdigest()

def bake_face(records, lo, hi, axis, sign, longest, minimum_radius=0.):
    """Orthographic tangent-disk rasterization with explicit coverage/layers.

    Cluster overlapping disk estimates within 0.4 mm. The foremost captured
    tangent plane supplies geometry/provenance; compatible material samples
    are averaged, without interpolating across a different authored owner.
    """
    uv = [i for i in range(3) if i != axis]
    size = hi - lo
    wh = np.maximum(4, np.ceil(size[uv] / size.max() * longest).astype(int))
    w, h = map(int, wh)
    depth = np.full((h, w, LAYERS), np.inf, np.float32)
    normals = np.zeros((h, w, LAYERS, 4), np.float32)
    colors = np.zeros_like(normals)
    rough = np.zeros((h,w,LAYERS),np.float32)
    dropped = 0
    for s in records:
        n = s[4:7].astype(np.float64)
        if n[axis] * sign < .12:
            continue
        p = s[:3].astype(np.float64)
        radius = max(float(s[3]), minimum_radius)
        center = (p[uv]-lo[uv])/size[uv]*wh-.5
        extent = radius/size[uv]*wh
        a = np.maximum(0, np.floor(center-extent).astype(int))
        b = np.minimum(wh-1, np.ceil(center+extent).astype(int))
        if np.any(b<a):
            continue
        xx, yy = np.meshgrid(np.arange(a[0],b[0]+1), np.arange(a[1],b[1]+1))
        q = np.empty(xx.shape+(3,)); q[...,uv[0]]=lo[uv[0]]+(xx+.5)*size[uv[0]]/w
        q[...,uv[1]]=lo[uv[1]]+(yy+.5)*size[uv[1]]/h
        q[...,axis]=p[axis]-(n[uv[0]]*(q[...,uv[0]]-p[uv[0]])+n[uv[1]]*(q[...,uv[1]]-p[uv[1]]))/n[axis]
        mask = np.sum((q-p)**2,axis=-1) <= radius*radius
        mask &= (q[...,axis]>=lo[axis]) & (q[...,axis]<=hi[axis])
        y, x = yy[mask], xx[mask]
        if not len(x):
            continue
        d = ((hi[axis]-q[...,axis]) if sign>0 else (q[...,axis]-lo[axis]))[mask].astype(np.float32)
        old = depth[y,x]
        node = float(s[9])
        compatible = (np.abs(old-d[:,None])<.0004) & (normals[y,x,:,3]==node)
        merged = compatible.any(axis=1)
        # Retain the existing plane to keep depth/normal/provenance together.
        if merged.any():
            my,mx=y[merged],x[merged]; k=compatible[merged].argmax(axis=1)
            col=colors[my,mx,k]; weight=col[:,3]
            colors[my,mx,k,:3]=(col[:,:3]*weight[:,None]+s[12:15])/(weight[:,None]+1)
            rough[my,mx,k]=(rough[my,mx,k]*weight+s[10])/(weight+1)
            colors[my,mx,k,3]=weight+1
        y,x,d=y[~merged],x[~merged],d[~merged]
        if not len(x):
            continue
        old=depth[y,x]
        position=(old<d[:,None]).sum(axis=1)
        dropped += int((position>=LAYERS).sum())
        for k in range(LAYERS-1,-1,-1):
            move=position<k
            if move.any():
                my,mx=y[move],x[move]
                depth[my,mx,k]=depth[my,mx,k-1]
                normals[my,mx,k]=normals[my,mx,k-1]
                colors[my,mx,k]=colors[my,mx,k-1]
                rough[my,mx,k]=rough[my,mx,k-1]
            insert=position==k
            if insert.any():
                my,mx=y[insert],x[insert]
                depth[my,mx,k]=d[insert]
                normals[my,mx,k,:3]=n; normals[my,mx,k,3]=node
                colors[my,mx,k,:3]=s[12:15]; colors[my,mx,k,3]=1
                rough[my,mx,k]=s[10]
    coverage=np.isfinite(depth)
    depth[~coverage]=-1
    # Store authored roughness separately from averaging weights.
    colors[...,3]=np.where(coverage,rough,0)
    return depth,normals,colors,{'width':w,'height':h,'axis':axis,'sign':sign,'covered_layers':coverage.sum(axis=(0,1)).tolist(),'farther_insertions_dropped':dropped}

def compile_fields(root=ROOT/'gpu_compute/captures/liewall06', destination=None, brick_size=192, mortar_size=1024):
    root=Path(root); destination=Path(destination or root/'direct'); destination.mkdir(parents=True,exist_ok=True)
    raw=(root/'library.bin').read_bytes()
    if sha(raw)!=BANK_SHA:
        raise ValueError('Unrecognized attributed source bank')
    bank=np.frombuffer(raw,dtype='<f4').reshape(-1,20)
    cat=json.loads((root/'catalog.json').read_text())
    joint=cat['masters']['joint_photo']['levels'][0]
    assets=[bank[:220000].copy(),bank[joint['start']:joint['start']+joint['count']].copy()]
    # The brick's nine local finite-patch IDs use exactly fetch_sample's rule.
    s=assets[0];n=s[:,4:7];p=s[:,:3];an=np.abs(n)
    s[:,9]=np.where((an[:,0]>=an[:,1])&(an[:,0]>=an[:,2]),np.where(n[:,0]>=0,0,1),np.where(an[:,1]>=an[:,2],np.where(n[:,1]>=0,2,3),np.where(n[:,2]<0,4,5+(p[:,0]>=0)+2*(p[:,1]>=0))))
    sheets=[]; boxes=[]
    for index,records in enumerate(assets):
        radius=np.maximum(records[:,3],.0052 if index==0 else 0)
        lo=(records[:,:3]-radius[:,None]).min(axis=0); hi=(records[:,:3]+radius[:,None]).max(axis=0)
        boxes.append({'lo':lo.tolist(),'hi':hi.tolist(),'first_face':len(sheets),'samples':len(records)})
        for axis in range(3):
            for sign in [1,-1]:
                sheets.append(bake_face(records,lo,hi,axis,sign,brick_size if index==0 else mortar_size,.0052 if index==0 else 0))
    width=max(s[0].shape[1] for s in sheets)
    height=sum(s[0].shape[0] for s in sheets)
    depth=np.full((height,width,LAYERS),-1,np.float32)
    normal=np.zeros((LAYERS,height,width,4),np.float16); color=np.zeros_like(normal)
    faces=[]; offset=0
    for d,n,c,meta in sheets:
        h,w=d.shape[:2];depth[offset:offset+h,:w]=d
        normal[:,offset:offset+h,:w]=n.transpose(2,0,1,3)
        color[:,offset:offset+h,:w]=c.transpose(2,0,1,3)
        faces.append(dict(meta,x=0,y=offset));offset+=h
    packets={'depth.bin':depth.astype('<f4').tobytes(),'normal.bin':normal.astype('<f2').tobytes(),'color.bin':color.astype('<f2').tobytes()}
    proof={'schema':'lie-layered-surface/1','source_bank_sha256':sha(raw),'width':width,'height':height,'layers':LAYERS,'boxes':boxes,'faces':faces,'packets':{},'scope':'immutable captured opaque tangent disks; four nearest separated layers per face; half-float linear material and normals; full brick master replaces per-instance sparse subsets; finite resolution and layer truncation are approximations; no source mesh'}
    for name,blob in packets.items():
        (destination/name).write_bytes(blob);proof['packets'][name]={'bytes':len(blob),'sha256':sha(blob)}
    (destination/'surface.json').write_text(json.dumps(proof,indent=2)+'\n')
    return proof

if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--root',type=Path,default=ROOT/'gpu_compute/captures/liewall06');parser.add_argument('--output',type=Path)
    args=parser.parse_args();proof=compile_fields(args.root,args.output)
    print(json.dumps(proof,indent=2))
