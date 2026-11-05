"""Validate staged Vulkan compute ray resolver vs independent captured-cell oracle.

Compares the *same selected rays* for baseline native GPU and independent
compute first-hit GPU. Selection includes all known oracle errors plus seeded
flagged hits/background; not a full-frame error rate or original Blender mesh.
"""
from __future__ import annotations
import argparse
import hashlib
import json
from pathlib import Path
import numpy as np

from lie_real_vulkan_triplet import load_oracle,camera_rays
from lie_stream_candidate_metrics import load_risk,W,N

def validate_packet(packet,flags):
    arr=np.asarray(packet,dtype=np.float32)
    if arr.shape!=(N,16):raise ValueError('Expected 64-byte compute hit record per pixel')
    if not np.isfinite(arr).all():raise ValueError('Nonfinite GPU compute hit record')
    status=arr[:,13]
    if np.any(~np.isin(status,[0,1,2,3])):raise ValueError('Unknown compute first-hit status')
    if np.any(status[~flags]!=0):raise ValueError('Compute modified unflagged pixels')
    if np.any(status[flags]==0):raise ValueError('Compute silently omitted a flagged pixel')
    hit=(status==1)
    if np.any((arr[hit,3]<=.5)|(arr[hit,12]<0)|(arr[hit,12]>1)):
        raise ValueError('Invalid owner or reverse-Z for first-hit')
    if np.any(np.abs(arr[~hit,3])>1e-6):
        raise ValueError('Non-hit status must not publish owner')
    return {
        'records_all_pixels':int(N),
        'flagged_pixels':int(flags.sum()),
        'resolved_hit_status':int(hit.sum()),
        'resolved_miss_status':int((status==2).sum()),
        'overflow_status':int((status==3).sum()),
        'max_cell_iterations':int(arr[flags,14].max()) if flags.any() else 0,
        'untouched_pixels_zero':bool(np.all(arr[~flags]==0))}

def selection(flags,known_ids,seed=343,samples=1200):
    known=np.asarray(known_ids,dtype=np.int64)
    if len(set(known))!=len(known) or np.any(known<0) or np.any(known>=N):
        raise ValueError('Invalid reference pixel IDs')
    if np.any(~flags[known]):
        raise ValueError('The native candidate detector MISSED known oracle errors')
    candidate=np.flatnonzero(flags)
    rng=np.random.default_rng(seed)
    extra=rng.choice(candidate,min(samples,len(candidate)),replace=False)
    return np.unique(np.r_[known,extra]).astype(np.int64)

def scores(records,original,indices,eye,reference_depth,reference_owner,tolerance=2e-5):
    expected=np.isfinite(reference_depth)
    if records is None:
        has=original[indices,3]>.5
        owner=original[indices,3]
        d=np.linalg.norm(original[indices,:3].astype(float)-eye,axis=1)
        incomplete=np.zeros(len(indices),bool)
    else:
        status=records[indices,13]
        has=status==1
        incomplete=status==3
        owner=records[indices,3]
        d=np.linalg.norm(records[indices,:3].astype(float)-eye,axis=1)
    missing=(expected&~has&~incomplete)
    extra=(~expected&has)
    owner_bad=(expected&has)&(np.rint(owner)!=np.rint(reference_owner))
    depth_bad=(expected&has)&(np.abs(d-reference_depth)>tolerance)
    wrong=missing|extra|owner_bad|depth_bad|incomplete
    return wrong, {
        'wrong_sampled':int(wrong.sum()),'missing':int(missing.sum()),
        'extra':int(extra.sum()),'wrong_owner':int(owner_bad.sum()),
        'wrong_depth_over_20um':int(depth_bad.sum()),
        'incomplete_overflow':int(incomplete.sum()),
        'wrong_pixel_ids':[int(i) for i in indices[wrong]][:120]
    }

def inspect(captures:Path,baseline:Path,bank:Path,experimental:Path,
            diagnostics:Path,pose=0,random_flagged=1200):
    world_path=captures/f'{pose}-native-world.bin'
    old_path=baseline/f'{pose}-native-world.bin'
    gpu=np.fromfile(world_path,'<f4')
    old=np.fromfile(old_path,'<f4')
    record_path=captures/f'{pose}-native-first-hit.bin'
    packet=np.fromfile(record_path,'<f4')
    if gpu.size!=N*4 or old.size!=N*4 or packet.size!=N*16:
        raise ValueError('Unexpected Vulkan world or compute record lengths')
    gpu=gpu.reshape(N,4);old=old.reshape(N,4);packet=packet.reshape(N,16)
    flags=load_risk(captures/f'{pose}-native-candidate-risk.bin').any(axis=0)
    st=validate_packet(packet,flags)
    report=json.loads((diagnostics/f'lie-native-triplet-pose{pose}.json').read_text())
    if hashlib.sha256(old_path.read_bytes()).hexdigest()!=report['provenance']['native_world_sha256']:
        raise ValueError('Archived reference does not match original native world packet')
    view_path=captures/f'{pose}-native-views.bin'
    if hashlib.sha256(view_path.read_bytes()).hexdigest()!=report['provenance']['view_sha256']:
        raise ValueError('Ray camera packet does not match original oracle')
    if not np.array_equal(old,gpu):
        raise ValueError('Compute probe changed baseline native GPU G-buffer')
    known_ids=[x['pixel_id'] for x in report['disagreement_pixels']]
    indices=selection(flags,known_ids,samples=random_flagged)
    eye,dirs,proxies,_,_=camera_rays(captures,pose,indices,W)
    oracle=load_oracle(experimental,bank)
    depth,owner,_,_=oracle.trace(eye,dirs,proxies)
    oldwrong,oldscores=scores(None,old,indices,eye,depth,owner)
    newwrong,newscores=scores(packet,old,indices,eye,depth,owner)
    critical=int(434*W+416)
    known_mask=np.isin(indices,known_ids)
    data={'schema':'lie-stream-first-hit-gpu-oracle/1','pose':pose,
        'samples':len(indices),'known_directed_error_samples':len(known_ids),
        'random_seed':343,'seeded_flagged_samples':random_flagged,
        'readback_status':st,
        'baseline':oldscores,'gpu_compute':newscores,
        'repaired_from_baseline':int((oldwrong&~newwrong).sum()),
        'regressed_from_baseline':int((~oldwrong&newwrong).sum()),
        'known_errors_repaired':int((oldwrong&~newwrong&known_mask).sum()),
        'known_errors_remain':int((newwrong&known_mask).sum()),
        'known_errors_regressed':int((~oldwrong&newwrong&known_mask).sum()),
        'critical_pixel_416_434':({
            'baseline_owner':float(old[critical,3]),'compute_owner':float(packet[critical,3]),
            'compute_status':int(packet[critical,13]),'compute_reverse_z':float(packet[critical,12])
            } if pose==1 else None),
        'exact_same_native_render':True,
        'input_provenance':{
            'compute_record_sha256':hashlib.sha256(record_path.read_bytes()).hexdigest(),
            'candidate_bits_sha256':hashlib.sha256((captures/f'{pose}-native-candidate-risk.bin').read_bytes()).hexdigest(),
            'view_sha256':report['provenance']['view_sha256'],
            'original_native_world_sha256':report['provenance']['native_world_sha256']},
        'limitations':['This GPU record is NOT composited into G-buffer or reverse-Z attachment',
            'Finite-cell CPU oracle reference is not independent original Blender mesh',
            'Sample contains all previously diagnosed errors and a fixed random flagged subset; not full-frame census',
            'No GPU/mobile performance claim'] }
    data['strict_gate_passed']=bool(st['overflow_status']==0 and
        newscores['wrong_sampled']==0 and data['known_errors_remain']==0 and
        data['regressed_from_baseline']==0)
    return data

def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--captures',type=Path,required=True)
    p.add_argument('--baseline',type=Path,required=True)
    p.add_argument('--bank',type=Path,required=True)
    p.add_argument('--experimental-checkout',type=Path,required=True)
    p.add_argument('--diagnostics',type=Path,required=True)
    p.add_argument('--pose',type=int,default=0)
    p.add_argument('--random-flagged',type=int,default=1200)
    p.add_argument('--output',type=Path,required=True)
    a=p.parse_args()
    if a.random_flagged<0:p.error('random-flagged cannot be negative')
    data=inspect(a.captures,a.baseline,a.bank,a.experimental_checkout,a.diagnostics,a.pose,a.random_flagged)
    a.output.parent.mkdir(parents=True,exist_ok=True)
    a.output.write_text(json.dumps(data,indent=2,allow_nan=False)+'\n')
    print(json.dumps({k:v for k,v in data.items() if k!='input_provenance'},indent=2,allow_nan=False))

if __name__=='__main__':main()
