"""Offline access alternatives derived only from the accepted layered captures.

Regions conservatively enclose every occupied layer. The envelope is an
explicit approximation: adaptive planar quads, split at holes/owner boundaries,
with a recorded cell-centre depth-error bound. It is not the captured source mesh.
"""
import argparse
import hashlib
import json
from pathlib import Path
import struct
import numpy as np

ROOT = Path(__file__).resolve().parents[1]
REGION_SIZE = 8


def region_bounds(depth, block=REGION_SIZE):
    h, w = depth.shape[:2]
    out = np.zeros(((h + block - 1)//block, (w + block - 1)//block, 4), '<f4')
    out[..., :2] = -1
    for y in range(out.shape[0]):
        for x in range(out.shape[1]):
            d = depth[y*block:min((y+1)*block,h), x*block:min((x+1)*block,w)]
            valid = d[d >= 0]
            if len(valid):
                out[y,x] = (float(valid.min()), float(valid.max()), len(valid), 0)
    return out


def envelope_quads(depth, owner, face, layer, tolerance=.0008, max_block=32):
    """Return quads with no inferred coverage across an empty cell or new owner.

    Each packet: cell-edge rectangle, four fitted corner depths (00,10,11,01),
    and uint face/layer metadata. Corner positions are bounded by the compiler's
    actual field; depth error is evaluated against all covered cell centres.
    """
    h, w = depth.shape
    quads = []
    worst = 0.

    def visit(x0, y0, x1, y1):
        nonlocal worst
        d = depth[y0:y1,x0:x1]
        valid = d >= 0
        if not valid.any():
            return
        ww, hh = x1-x0, y1-y0
        accept = valid.all() and np.all(owner[y0:y1,x0:x1] == owner[y0,x0])
        corners = None
        error = float('inf')
        if accept:
            xs = np.arange(ww, dtype=np.float64)+.5-ww*.5
            ys = np.arange(hh, dtype=np.float64)+.5-hh*.5
            mean = float(d.mean(dtype=np.float64))
            sx = float(np.sum(d*xs[None,:])/(hh*np.sum(xs*xs))) if ww>1 else 0.
            sy = float(np.sum(d*ys[:,None])/(ww*np.sum(ys*ys))) if hh>1 else 0.
            fit = mean+xs[None,:]*sx+ys[:,None]*sy
            error = float(np.max(np.abs(d-fit)))
            corners = [mean-sx*ww*.5-sy*hh*.5, mean+sx*ww*.5-sy*hh*.5,
                       mean+sx*ww*.5+sy*hh*.5, mean-sx*ww*.5+sy*hh*.5]
            # Avoid extrapolated negative capture depth at silhouette edges.
            accept = error <= tolerance and min(corners) >= -tolerance
        if accept or ww==hh==1:
            corners = np.maximum(corners, 0).astype('<f4')
            # Quantization and clamping belong in the recorded error too.
            fit2 = ((corners[0]+corners[1]+corners[2]+corners[3])*.25
                    + xs[None,:]*(corners[1]-corners[0])/ww
                    + ys[:,None]*(corners[3]-corners[0])/hh)
            worst = max(worst, float(np.max(np.abs(d-fit2))))
            quads.append(struct.pack('<8f4I',x0,y0,x1,y1,*corners,face,layer,0,0))
            return
        xm = x0+max(1,ww//2); ym = y0+max(1,hh//2)
        for a,b in [(y0,ym),(ym,y1)] if hh>1 else [(y0,y1)]:
            for c,e in [(x0,xm),(xm,x1)] if ww>1 else [(x0,x1)]:
                visit(c,a,e,b)

    for y in range(0,h,max_block):
        for x in range(0,w,max_block):
            visit(x,y,min(x+max_block,w),min(y+max_block,h))
    return b''.join(quads), worst


def coarse_envelope(depth, face, step=4):
    """One front sheet per direction, fixed coarse patches, full-res coverage mask.

    This deliberately trades geometry accuracy for native triangle depth.
    Discontinuous depth and holes are NOT claimed to meet the planar tolerance.
    The fragment shader must test the original cell's layer-0 coverage.
    """
    h,w=depth.shape;quads=[];worst=0.
    for y in range(0,h,step):
        for x in range(0,w,step):
            d=depth[y:min(y+step,h),x:min(x+step,w)]
            valid=d>=0
            if not valid.any():continue
            hh,ww=d.shape;yy,xx=np.mgrid[:hh,:ww]
            xx=xx+.5-ww*.5;yy=yy+.5-hh*.5
            design=np.column_stack([np.ones(valid.sum()),xx[valid],yy[valid]])
            fit=np.linalg.lstsq(design,d[valid],rcond=None)[0]
            # A poorly constrained thin boundary must not extrapolate a cliff.
            corners=np.array([fit[0]-fit[1]*ww*.5-fit[2]*hh*.5,
                              fit[0]+fit[1]*ww*.5-fit[2]*hh*.5,
                              fit[0]+fit[1]*ww*.5+fit[2]*hh*.5,
                              fit[0]-fit[1]*ww*.5+fit[2]*hh*.5])
            corners=np.clip(corners,d[valid].min(),d[valid].max()).astype('<f4')
            # Shader draws two triangles, not a bilinear patch: evaluate both.
            u=(xx+ww*.5)/ww;v=(yy+hh*.5)/hh
            a=corners[0]+u*(corners[1]-corners[0])+v*(corners[2]-corners[1])
            b=corners[0]+u*(corners[2]-corners[3])+v*(corners[3]-corners[0])
            actual=np.where(u>=v,a,b)
            error=float(np.max(np.abs(actual[valid]-d[valid])))
            if error>.003 and step>1:
                finer,sub_error=coarse_envelope(d,face,max(1,step//2))
                for off in range(0,len(finer),48):
                    q=list(struct.unpack_from('<8f4I',finer,off))
                    q[0]+=x;q[2]+=x;q[1]+=y;q[3]+=y
                    quads.append(struct.pack('<8f4I',*q))
                worst=max(worst,sub_error)
                continue
            worst=max(worst,error)
            quads.append(struct.pack('<8f4I',x,y,x+ww,y+hh,*corners,face,0,0,0))
    return b''.join(quads),worst


def compile_access(root=None, tolerance=.0008):
    root = Path(root or ROOT/'gpu_compute/captures/liewall06/direct')
    proof = json.loads((root/'surface.json').read_text())
    # Refuse mismatched inputs rather than silently compiling a stale field.
    for name, meta in proof['packets'].items():
        data = (root/name).read_bytes()
        if len(data)!=meta['bytes'] or hashlib.sha256(data).hexdigest()!=meta['sha256']:
            raise ValueError('Layered packet identity: '+name)
    h,w,L = proof['height'],proof['width'],proof['layers']
    depth = np.fromfile(root/'depth.bin',dtype='<f4').reshape(h,w,L)
    normals = np.fromfile(root/'normal.bin',dtype='<f2').reshape(L,h,w,4)
    bounds = []; rects = []; packets = []; groups=[]; offset=0; qcount=0; worst=0.
    for master in range(len(proof['boxes'])):
        start=qcount
        for face_index in range(master*6,master*6+6):
            face=proof['faces'][face_index]; x,y,fw,fh=(face[k] for k in ['x','y','width','height'])
            d=depth[y:y+fh,x:x+fw]
            b=region_bounds(d); bounds.append(b)
            rects.append([0,offset,b.shape[1],b.shape[0]]); offset+=b.shape[0]
            mesh,error=coarse_envelope(d[...,0],face_index,4)
            packets.append(mesh);qcount+=len(mesh)//48;worst=max(worst,error)
        groups.append({'first_quad':start,'quads':qcount-start,'triangles':(qcount-start)*2})
    width=max(b.shape[1] for b in bounds)
    atlas=np.zeros((offset,width,4),'<f4');atlas[...,:2]=-1; at=0
    for b in bounds:
        atlas[at:at+b.shape[0],:b.shape[1]]=b;at+=b.shape[0]
    blobs={'regions.bin':atlas.tobytes(),'envelope.bin':b''.join(packets)}
    meta={'schema':'lie-surface-access/1','source_bank_sha256':proof['source_bank_sha256'],
          'source_packets':proof['packets'],'region_size':REGION_SIZE,'region_width':width,
          'region_height':offset,'region_rects':rects,'envelope_groups':groups,
          'envelope_max_step_cells':4,'envelope_layers_per_direction':1,'envelope_cell_center_max_error_m':worst,
          'envelope_quad_stride':48,'packets':{},
          'scope':'conservative all-layer region ranges; coarse front-layer capture envelope; full-resolution original coverage/owner/material lookup in fragment; envelope may change silhouette, depth and shadows; measured cell-centre error is not an acceptance tolerance; no source mesh'}
    for name,data in blobs.items():
        (root/name).write_bytes(data);meta['packets'][name]={'bytes':len(data),'sha256':hashlib.sha256(data).hexdigest()}
    (root/'access.json').write_text(json.dumps(meta,indent=2)+'\n')
    return meta


if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--root',type=Path);p.add_argument('--tolerance',type=float,default=.0008)
    a=p.parse_args();print(json.dumps(compile_access(a.root,a.tolerance),indent=2))
