"""Measure REAL native Vulkan candidate SSBO bitsets and streaming temporal residuals.

Flags come from the native fragment shader BEFORE half-open discard. The
independent captured-cell oracle labels errors but NEVER selects flagged pixels.
Previous-frame reprojection is a quality/risk signal, NOT geometry truth.
"""
from __future__ import annotations
import argparse
import hashlib
import json
from pathlib import Path
import numpy as np

W=720
N=W*W
WORDS=(N+31)//32

def load_risk(path:Path):
    raw=path.read_bytes()
    if len(raw)!=3*WORDS*4:raise ValueError(f'Expected three R32UI packed planes, got {len(raw)} bytes')
    arr=np.frombuffer(raw,dtype='<u4').reshape(3,WORDS)
    return np.unpackbits(arr.view('u1'),bitorder='little',axis=1)[:,:N].astype(bool)

def load_view(captures,pose):
    path=captures/f'{pose}-native-views.bin'
    data=np.fromfile(path,'<f4')
    if data.size<20:raise ValueError('Missing original camera packet')
    return data[:20].astype(float),hashlib.sha256(path.read_bytes()).hexdigest()

def temporal_mask(current,previous,previous_view,tolerance_m=.0015):
    if current.shape!=(N,4) or previous.shape!=(N,4) or tolerance_m<=0:
        raise ValueError('Invalid temporal packet dimensions or tolerance')
    ids=np.flatnonzero(current[:,3]>.5)
    d=current[ids,:3].astype(float)-previous_view[:3]
    depth=d@previous_view[12:15]
    safe=np.where(abs(depth)>1e-14,depth,np.inf)
    x=((d@previous_view[4:7]/(safe*previous_view[18]))+1)*W/2-.5
    y=(-(d@previous_view[8:11]/(safe*previous_view[18]))+1)*W/2-.5
    inside=(depth>0)&(x>=0)&(x<W-1)&(y>=0)&(y<W-1)
    sample=np.clip(np.rint(y).astype('int64'),0,W-1)*W+np.clip(np.rint(x).astype('int64'),0,W-1)
    old=previous[sample]
    stable=inside&(old[:,3]==current[ids,3])&(old[:,3]>.5)&(
        np.linalg.norm(old[:,:3].astype(float)-current[ids,:3].astype(float),axis=1)<=tolerance_m)
    flags=np.zeros(N,dtype=bool)
    flags[ids[~stable]]=True
    return flags,{'positive_pixels':len(ids),'stable_reprojected':int(stable.sum()),
       'temporal_residual_pixels':int((~stable).sum()),'tolerance_m':tolerance_m,
       'blind_spot':'Cannot see current empty pixels or stable wrong geometry'}

def stats(mask,reference,tile_size=8):
    if W%tile_size:raise ValueError('Invalid tile size')
    ids=np.asarray([int(row['pixel_id']) for row in reference['disagreement_pixels']],dtype=np.int64)
    if len(np.unique(ids))!=len(ids) or np.any(ids<0) or np.any(ids>=N):
        raise ValueError('Invalid oracle error IDs')
    t=mask.reshape(W//tile_size,tile_size,W//tile_size,tile_size).any(axis=(1,3))
    return {'flagged_pixels':int(mask.sum()),'fraction_of_frame':float(mask.mean()),
            'flagged_tiles':int(t.sum()),'total_tiles':int(t.size),
            'fraction_of_tiles':float(t.mean()),
            'known_oracle_errors':len(ids),'flagged_known_errors':int(mask[ids].sum()),
            'unflagged_known_pixel_ids':[int(k) for k in ids[~mask[ids]]],
            'known_errors_are_biased_sample':True}

def inspect(captures,baseline,diagnostics,tile_size=8):
    results=[]
    for pose in range(3):
        fresh_path=captures/f'{pose}-native-world.bin'
        old_path=baseline/f'{pose}-native-world.bin'
        fresh=np.fromfile(fresh_path,'<f4')
        old=np.fromfile(old_path,'<f4')
        if fresh.size!=N*4 or old.size!=N*4:raise ValueError('Wrong native GPU world readback dimensions')
        fresh=fresh.reshape(N,4)
        old=old.reshape(N,4)
        same=bool(np.array_equal(fresh,old))
        view,view_sha=load_view(captures,pose)
        oracle=json.loads((diagnostics/f'lie-native-triplet-pose{pose}.json').read_text())
        if hashlib.sha256(old_path.read_bytes()).hexdigest()!=oracle['provenance']['native_world_sha256']:
            raise ValueError('Baseline does not match independent original oracle diagnosis')
        if view_sha!=oracle['provenance']['view_sha256']:
            raise ValueError('Test camera differs from independently recorded oracle')
        risk_path=captures/f'{pose}-native-candidate-risk.bin'
        risk=load_risk(risk_path)
        candidate=np.any(risk,axis=0)
        residual=np.zeros(N,dtype=bool)
        temporal_info={'not_applicable':'I-frame / reference pose'}
        if pose>0:
            previous_view,_=load_view(captures,0)
            previous=np.fromfile(baseline/'0-native-world.bin','<f4').reshape(N,4)
            residual,temporal_info=temporal_mask(fresh,previous,previous_view)
        results.append({'pose':pose,'no_modified_native_geometry':same,
           'different_world_pixel_count':int(np.any(fresh!=old,axis=1).sum()),
           'risk_planes':['pre-discard-patch-boundary','pre-discard-captured-texel-grid','pre-discard-entry-face-tie'],
           'risk_counts':[int(x.sum()) for x in risk],
           'candidate_only':stats(candidate,oracle,tile_size),
           'temporal_only':stats(residual,oracle,tile_size),
           'candidate_or_temporal':stats(candidate|residual,oracle,tile_size),
           'temporal_details':temporal_info,
           'critical_owner80_pixel_flagged':bool(candidate[434*W+416]) if pose==1 else None,
           'critical_pixel_planes':[bool(x[434*W+416]) for x in risk] if pose==1 else None,
           'provenance':{'instrumented_world':hashlib.sha256(fresh_path.read_bytes()).hexdigest(),
              'original_world':hashlib.sha256(old_path.read_bytes()).hexdigest(),
              'candidate_risk':hashlib.sha256(risk_path.read_bytes()).hexdigest(),'view':view_sha}})
    return {'schema':'lie-stream-pre-discard-candidate/1',
       'method':'Real Vulkan atomic mask, before support discard, combined with frame-to-frame reprojection of source World+Owner; no oracle used for flags',
       'tile_size':tile_size,'poses':results,
       'strict_geometry_unchanged':all(x['no_modified_native_geometry'] for x in results),
       'limitations':['Non-rasterized candidates cannot be detected by fragment atomics',
          'Prediction cannot replace geometry; a wrong stable hit may stay temporally consistent',
          'Flags are candidates for a future full first-hit resolver, not a solution',
          'No full-frame oracle, original Blender mesh or hardware/mobile performance proof']}

def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--captures',type=Path,required=True)
    p.add_argument('--baseline',type=Path,required=True)
    p.add_argument('--diagnostics',type=Path,required=True)
    p.add_argument('--output',type=Path,required=True)
    args=p.parse_args()
    result=inspect(args.captures,args.baseline,args.diagnostics)
    args.output.parent.mkdir(parents=True,exist_ok=True)
    args.output.write_text(json.dumps(result,indent=2)+'\n')
    print(json.dumps({k:v for k,v in result.items() if k!='poses'},indent=2))
    for row in result['poses']:
        print(json.dumps({k:v for k,v in row.items() if k!='provenance'},indent=2))

if __name__=='__main__':main()
