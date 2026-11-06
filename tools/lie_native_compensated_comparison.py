"""Matched-ray correctness gate for staged compensated FP32 A/B Vulkan.

Uses the union of oracle disagreements from BOTH runs. Also reports full-frame
coverage and owner changes. No synthetic pixels; no Blender source claim.
"""
from __future__ import annotations
import argparse
import hashlib
import json
from pathlib import Path
import numpy as np

TOL=2e-5


def compare(baseline:Path,trial:Path,reports:Path):
    cases=[]
    for pose in range(3):
        old=json.loads((reports/f'lie-native-triplet-pose{pose}.json').read_text())
        new=json.loads((reports/f'lie-native-compensated-triplet-pose{pose}.json').read_text())
        v=(trial/f'{pose}-native-views.bin').read_bytes()
        if hashlib.sha256(v).hexdigest()!=old['provenance']['view_sha256'] or old['provenance']['view_sha256']!=new['provenance']['view_sha256']:
            raise ValueError(f'Camera packet mismatch in pose {pose}')
        eye=np.frombuffer(v,'<f4')[:3].astype(float)
        original=np.fromfile(baseline/f'{pose}-native-world.bin','<f4')
        corrected=np.fromfile(trial/f'{pose}-native-world.bin','<f4')
        if original.size!=720*720*4 or corrected.size!=original.size:
            raise ValueError('Invalid native GPU readback size')
        original=original.reshape(-1,4)
        corrected=corrected.reshape(-1,4)
        truth={}
        for row in old['disagreement_pixels']+new['disagreement_pixels']:
            k=int(row['pixel_id'])
            t=(bool(row['representation_hit']),row['representation_owner'],row['representation_distance_m'])
            if k in truth and (truth[k][0]!=t[0] or truth[k][1]!=t[1] or
                    (t[2] is not None and abs(truth[k][2]-t[2])>1e-8)):
                raise ValueError(f'Independent oracle inconsistency at pixel {k}')
            truth[k]=t
        def wrong(world,k,t):
            hit=world[k,3]>.5
            if bool(hit)!=t[0]:return True
            if not hit:return False
            return round(float(world[k,3]))!=t[1] or abs(float(np.linalg.norm(world[k,:3].astype(float)-eye))-t[2])>TOL
        bad_old={k for k,t in truth.items() if wrong(original,k,t)}
        bad_new={k for k,t in truth.items() if wrong(corrected,k,t)}
        oldhit=original[:,3]>.5;newhit=corrected[:,3]>.5
        owner_changes=(original[:,3]!=corrected[:,3])&oldhit&newhit
        critical=434*720+416
        cases.append({
            'pose':pose,'same_oracle_pixel_union':len(truth),
            'baseline_errors':len(bad_old),'trial_errors':len(bad_new),
            'rescued_errors':len(bad_old-bad_new),'new_errors':len(bad_new-bad_old),
            'both_bad':len(bad_old&bad_new),
            'new_bad_examples':sorted(bad_new-bad_old)[:30],
            'baseline_hits_full_frame':int(oldhit.sum()),'trial_hits_full_frame':int(newhit.sum()),
            'lost_hits_vs_baseline_full_frame':int((oldhit&~newhit).sum()),
            'new_hits_vs_baseline_full_frame':int((~oldhit&newhit).sum()),
            'owner_changes_on_common_hits_full_frame':int(owner_changes.sum()),
            'critical_owner_baseline':float(original[critical,3]) if pose==1 else None,
            'critical_owner_trial':float(corrected[critical,3]) if pose==1 else None,
            'no_regression_on_union':len(bad_new-bad_old)==0,
            'no_new_holes_vs_baseline':not np.any(oldhit&~newhit),
        })
    return {
        'schema':'lie-native-compensated-fp32-common-union/1',
        'method':'Compare BOTH Vulkan executions against IDENTICAL captured-cell oracle predictions at union of disagreements; independent source mesh not available',
        'cases':cases,
        'strict_all_poses_pass':all(c['no_regression_on_union'] and c['no_new_holes_vs_baseline'] for c in cases),
        'limitations':['Biased union is not a full-frame error rate',
                       'Full frame coverage deltas are against baseline GPU, not source or oracle',
                       'No Android GPU speed or support inference from software Vulkan',
                       'FP32 compensated path remains an unapproved experiment']}


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--baseline',type=Path,required=True)
    p.add_argument('--trial',type=Path,required=True)
    p.add_argument('--reports',type=Path,required=True)
    p.add_argument('--output',type=Path,required=True)
    args=p.parse_args()
    result=compare(args.baseline,args.trial,args.reports)
    args.output.parent.mkdir(parents=True,exist_ok=True)
    args.output.write_text(json.dumps(result,indent=2,sort_keys=True)+'\n')
    print(json.dumps(result,indent=2))


if __name__=='__main__':main()
