"""Three-way LIE-2.5 WALL06 diagnostic: captured sample disks -> compiled cells -> actual Vulkan.

The source here is the immutable *captured 80-byte sample bank*, NOT the
500,000-triangle original scanned GLB. The field oracle is the pre-existing
independent float64 finite-cell ray tracer. The GPU output is read from
test_lie_native_depth.gd at the exact recorded phone pose, not simulated here.

Requires scipy, numpy and the licensed sample bank; never invents a missing
bank. No FPS benchmark, source-mesh equivalence or engine patch.
"""
from __future__ import annotations
import argparse
import hashlib
import json
from pathlib import Path
import sys

import numpy as np
from scipy.spatial import cKDTree
import lie_native_oracle as cells
from lie_direct_surface import BANK_SHA

BRICK_SAMPLES = 220000
NODE_GROUP = 9
NODE_MORTAR = 864
POSE = dict(yaw=-72.90939846038818, elevation=2.0563994513617607, distance=.6)
SOURCE_THRESHOLD_M = .001
GPU_THRESHOLD_M = .00002


def verified(path: Path, expected: str) -> bytes:
    data = path.read_bytes()
    if hashlib.sha256(data).hexdigest() != expected:
        raise ValueError("SHA mismatch for "+str(path))
    return data


def build_masters(root: Path, proof: dict, catalog: dict):
    raw = verified(root/'library.bin', BANK_SHA)
    bank = np.frombuffer(raw, dtype='<f4').reshape(-1,20)
    level = catalog['masters']['joint_photo']['levels'][0]
    brick = bank[:BRICK_SAMPLES].astype(np.float64)
    mortar = bank[level['start']:level['start']+level['count']].astype(np.float64)
    result = []
    for idx, rec in enumerate((brick,mortar)):
        bounds = proof['boxes'][idx]
        r = np.maximum(rec[:,3], .0052 if idx==0 else 0.)
        if np.any(r<=0) or not np.isfinite(rec).all():
            raise ValueError('Invalid source sample radii or points')
        node=rec[:,9].astype(np.int64)
        if idx==0:
            n=rec[:,4:7];p=rec[:,:3];an=np.abs(n)
            node=np.where((an[:,0]>=an[:,1])&(an[:,0]>=an[:,2]),
                          np.where(n[:,0]>=0,0,1),
                          np.where(an[:,1]>=an[:,2],
                                   np.where(n[:,1]>=0,2,3),
                                   np.where(n[:,2]<0,4,5+(p[:,0]>=0)+2*(p[:,1]>=0))))
        else:
            if not np.all((node>=NODE_MORTAR)&(node<NODE_MORTAR+8)):
                raise ValueError('Non-mortar IDs in the mortar master')
        result.append(dict(rec=rec, radii=r, node=node, tree=cKDTree(rec[:,:3]),
                           maximum_radius=float(r.max()), box=bounds))
    return result


def intersect_single_master(eye, ray, low, high, master, *, eps=1e-9):
    """Earliest point of contact with actual recorded finite tangent disks.

    cKDTree only prunes candidates: spheres enclosing consecutive ray intervals
    conservatively contain EVERY disk with a possible intersection.
    """
    eye=np.asarray(eye,np.float64);ray=np.asarray(ray,np.float64)
    safe=np.where(np.abs(ray)>1e-14,ray,np.where(ray<0.,-1e-14,1e-14))
    ab=(np.asarray(low)-eye)/safe
    cd=(np.asarray(high)-eye)/safe
    near=np.minimum(ab,cd);far=np.maximum(ab,cd)
    start=max(0.,float(near.max()));end=float(far.min())
    if end<start: return None
    # Split long ray intervals to avoid querying the entire master in a
    # single large sphere. Every disk crossing an interval lies within
    # sqrt((segment_length/2)^2 + Rmax^2) of that segment's midpoint.
    length=end-start
    count=max(1,int(np.ceil(length/.015)))
    edges=np.linspace(start,end,count+1)
    mids=eye+(edges[:-1,None]+edges[1:,None])*.5*ray
    bound=np.sqrt(((edges[1:]-edges[:-1])*.5*np.linalg.norm(ray))**2+master['maximum_radius']**2)+1e-8
    selected=set()
    for point,radius in zip(mids,bound):
        selected.update(master['tree'].query_ball_point(point,float(radius)))
    if not selected: return None
    idx=np.fromiter(sorted(selected),dtype=np.int64)
    rec=master['rec'][idx];normal=rec[:,4:7]
    front=-normal@ray
    valid=front>.12*np.linalg.norm(ray)
    denom=normal@ray
    t=np.divide(np.einsum('ij,ij->i',normal,rec[:,:3]-eye),
                denom,out=np.full(len(idx),np.inf),where=np.abs(denom)>1e-12)
    valid&=np.isfinite(t)&(t>=start-eps)&(t<=end+eps)&(t>0.)
    if not valid.any():return None
    hit=eye+t[:,None]*ray
    delta=hit-rec[:,:3]
    valid&=(np.einsum('ij,ij->i',delta,delta)<=master['radii'][idx]**2+1e-13)
    if not valid.any():return None
    t=np.where(valid,t,np.inf)
    j=int(np.argmin(t))
    return float(t[j]),int(master['node'][idx[j]]),int(idx[j])


def source_trace(eye, rays, proxies, masters):
    """World closest sampled disk, using the SAME uploaded proxy matrices.

    This is the bank's disk-level reference, not an original triangle oracle.
    """
    length=len(rays)
    times=np.full(length,np.inf,np.float64)
    owners=np.zeros(length,np.float64)
    raw_samples=np.full(length,-1,np.int64)
    for instance,packet in enumerate(proxies):
        inv=packet[16:32].reshape(4,4).T.astype(np.float64)
        p=inv[:3,:3]@eye+inv[:3,3]
        local_rays=rays@inv[:3,:3].T
        lo=packet[32:35].astype(np.float64)
        hi=packet[36:39].astype(np.float64)
        master=masters[0 if instance<96 else 1]
        for k,d in enumerate(local_rays):
            # A cheap slab check avoids doing KDTree work for unrelated bricks.
            if not np.isfinite(times[k]): limit=np.inf
            else:limit=times[k]
            safe=np.where(np.abs(d)>1e-14,d,np.where(d<0,-1e-14,1e-14))
            near=np.minimum((lo-p)/safe,(hi-p)/safe)
            far=np.maximum((lo-p)/safe,(hi-p)/safe)
            if float(far.min())<max(float(near.max()),0.) or max(float(near.max()),0.)>=limit:
                continue
            hit=intersect_single_master(p,d,lo,hi,master)
            if hit and hit[0]<times[k]:
                times[k]=hit[0]
                owners[k]=float(hit[1]+packet[42]+1)
                raw_samples[k]=hit[2]
    return times,owners,raw_samples


def pixels_for_probe(regions, native, max_disagreements=128, stable_hits=96, empty=48):
    rng=np.random.default_rng(343)
    rm=regions[:,3]>.5; nm=native[:,3]>.5
    differences=np.flatnonzero((rm!=nm)|((rm&nm)&(np.rint(regions[:,3])!=np.rint(native[:,3]))))
    choose=[]
    if len(differences):
        pick=np.unique(np.linspace(0,len(differences)-1,min(max_disagreements,len(differences)),dtype=np.int64))
        choose.extend(differences[pick].tolist())
    for pool,limit in ((np.flatnonzero(rm&nm),stable_hits),
                       (np.flatnonzero(~rm&~nm),empty)):
        if len(pool):
            choose.extend(rng.choice(pool,size=min(limit,len(pool)),replace=False).tolist())
    return np.unique(np.asarray(choose,dtype=np.int64)),len(differences)


def camera_rays(view, pixels, size):
    view=view.astype(np.float64)
    eye=view[:3]
    x=(pixels%size+.5)*(2/size)-1
    y=(pixels//size+.5)*(2/size)-1
    d=view[12:15]+view[4:7]*x[:,None]-view[8:11]*y[:,None]
    d*=view[18]
    # Shader uses forward + (right * x - up * y) * tangent.
    d=view[12:15]+(view[4:7]*x[:,None]-view[8:11]*y[:,None])*view[18]
    d/=np.linalg.norm(d,axis=1)[:,None]
    return eye,d


def classify(source, field, tolerance_m=SOURCE_THRESHOLD_M):
    source_t,source_id=source
    field_t,field_id=field
    a=np.isfinite(source_t)
    b=np.isfinite(field_t)
    both=a&b
    err=np.abs(source_t[both]-field_t[both])
    return dict(source_hits=int(a.sum()),compared_hits=int(b.sum()),
                missing=int((a&~b).sum()),extra=int((~a&b).sum()),
                owner_mismatches=int((np.rint(source_id[both])!=np.rint(field_id[both])).sum()),
                depth_gt_tolerance=int((err>tolerance_m).sum()),
                tolerance_m=tolerance_m,
                depth_error_m_max=float(err.max()) if len(err) else 0.,
                depth_error_m_p95=float(np.percentile(err,95)) if len(err) else 0.)


def analyze(root:Path,captures:Path,output:Path):
    direct=root/'direct'
    proof=json.loads((direct/'surface.json').read_text())
    catalog=json.loads((root/'catalog.json').read_text())
    if proof['source_bank_sha256']!=BANK_SHA:
        raise ValueError('Unexpected capture provenance')
    for name,meta in proof['packets'].items():
        data=verified(direct/name,meta['sha256'])
        if len(data)!=meta['bytes']:raise ValueError('Packet size: '+name)
    masters=build_masters(root,proof,catalog)
    regions=np.fromfile(captures/'0-regions-world.bin','<f4').reshape(-1,4)
    native=np.fromfile(captures/'0-native-world.bin','<f4').reshape(-1,4)
    if regions.shape!=native.shape:raise ValueError('Mismatched GPU pixels')
    size=int(round(np.sqrt(len(native))))
    if size*size!=len(native) or size!=720:raise ValueError('Unexpected phone pose resolution')
    px,total_differences=pixels_for_probe(regions,native)
    proxies=np.fromfile(captures/'0-native-proxies.bin','<f4').reshape(97,48)
    view=np.fromfile(captures/'0-native-views.bin','<f4')[:20]
    eye,rays=camera_rays(view,px,size)
    # The same finite cell oracle used in the original native-depth checkpoint.
    cells.proof=proof
    cells.field=np.fromfile(direct/'depth.bin','<f4').reshape(proof['height'],proof['width'],proof['layers'])
    cells.normal=np.fromfile(direct/'normal.bin','<f2').reshape(proof['layers'],proof['height'],proof['width'],4)
    field_t,field_id,_,_=cells.trace(eye,rays,proxies)
    bank_t,bank_id,sample_id=source_trace(eye,rays,proxies,masters)
    gpu_hits=native[px,3]>.5
    gpu_t=np.where(gpu_hits,np.linalg.norm(native[px,:3].astype(float)-eye,axis=1),np.inf)
    gpu_id=native[px,3].astype(float)
    regions_hits=regions[px,3]>.5
    regions_t=np.where(regions_hits,np.linalg.norm(regions[px,:3].astype(float)-eye,axis=1),np.inf)
    reg_id=regions[px,3].astype(float)
    report={
      'schema':'lie-wall25-real-bank-field-gpu/1',
      'claim':'Captured LIE sample bank (finite tangent disks) -> compiled layered cells -> actual Vulkan native output. NOT original scanned mesh (GLB).',
      'pose':POSE, 'resolution':size,'selected_rays':len(px),
      'disagreements_regions_native_total':total_differences,
      'bank_sha256':BANK_SHA,'field_sha256':proof['packets']['depth.bin']['sha256'],
      'source_bank_to_field':classify((bank_t,bank_id),(field_t,field_id)),
      'field_to_native_gpu':classify((field_t,field_id),(gpu_t,gpu_id),GPU_THRESHOLD_M),
      'bank_to_native_gpu':classify((bank_t,bank_id),(gpu_t,gpu_id)),
      'regions_to_field_reference_only':classify((regions_t,reg_id),(field_t,field_id),GPU_THRESHOLD_M),
      'source_mesh_reference_available':False,
      'source_sample_id_indices_are_local_to_master':True,
      'sample_examples':[
       dict(pixel=int(v),x=int(v%size),y=int(v//size),bank_hit=bool(np.isfinite(bank_t[j])),
            bank_t_m=float(bank_t[j]) if np.isfinite(bank_t[j]) else None,
            bank_id=int(round(bank_id[j])),
            cell_t_m=float(field_t[j]) if np.isfinite(field_t[j]) else None,
            cell_id=int(round(field_id[j])),
            gpu_t_m=float(gpu_t[j]) if gpu_hits[j] else None,
            gpu_id=int(round(gpu_id[j])) if gpu_hits[j] else 0)
       for j,v in enumerate(px)
       if (np.isfinite(bank_t[j])!=np.isfinite(field_t[j])) or
          (np.isfinite(field_t[j])!=gpu_hits[j]) or
          (np.isfinite(bank_t[j]) and np.isfinite(field_t[j]) and abs(bank_t[j]-field_t[j])>.001)
      ][:150]
    }
    output.parent.mkdir(parents=True,exist_ok=True)
    output.write_text(json.dumps(report,indent=2,allow_nan=False)+'\n')
    print(json.dumps({k:v for k,v in report.items() if k!='sample_examples'},indent=2))
    return report


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--bank',type=Path,required=True)
    p.add_argument('--captures',type=Path,required=True)
    p.add_argument('--output',type=Path,required=True)
    a=p.parse_args()
    analyze(a.bank,a.captures,a.output)


if __name__=='__main__':main()
