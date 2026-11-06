"""Compare actual archived baseline/guard Vulkan results on the SAME oracle rays.

Input: GitHub Actions evidence ZIP from native A/B experiment. This deliberately
uses the UNION of disagreement pixels in both runs. It is not a population
estimate or proof of original Blender geometry.
"""
from __future__ import annotations
import argparse
import hashlib
import json
from pathlib import Path
import zipfile
import numpy as np


def run(archive: Path):
    with zipfile.ZipFile(archive) as z:
        names=z.namelist()
        def read(suffix):
            hits=[n for n in names if n.endswith(suffix)]
            if len(hits)!=1: raise ValueError(f'Expected exactly one {suffix}, found {hits}')
            return z.read(hits[0])
        cases=[]
        for pose in range(3):
            before=json.loads(read(f'/lie-native-triplet-pose{pose}.json'))
            after=json.loads(read(f'/lie-native-guard-triplet-pose{pose}.json'))
            view=read(f'/native-depth/{pose}-native-views.bin')
            if before['provenance']['view_sha256']!=after['provenance']['view_sha256'] or hashlib.sha256(view).hexdigest()!=before['provenance']['view_sha256']:
                raise ValueError('Camera readbacks differ between A/B reports')
            eye=np.frombuffer(view,'<f4')[:3].astype(float)
            original=np.frombuffer(read(f'/lie-native-before/{pose}-native-world.bin'),'<f4').reshape(-1,4)
            guarded=np.frombuffer(read(f'/native-depth/{pose}-native-world.bin'),'<f4').reshape(-1,4)
            if original.shape!=(720*720,4) or guarded.shape!=(720*720,4):
                raise ValueError('Expected exactly 720x720 RGBA32F world packets')
            truth={}
            for row in before['disagreement_pixels']+after['disagreement_pixels']:
                k=row['pixel_id']
                candidate=(row['representation_hit'],row['representation_owner'],row['representation_distance_m'])
                if k in truth:
                    existing=truth[k]
                    if (existing[0]!=candidate[0] or existing[1]!=candidate[1] or
                        (existing[2] is not None and abs(existing[2]-candidate[2])>1e-8)):
                        raise ValueError('Inconsistent independent oracle result at pixel '+str(k))
                truth[k]=candidate
            def wrong(world,k,t):
                hit=world[k,3]>.5
                if bool(hit)!=bool(t[0]):return True
                if not hit:return False
                return round(float(world[k,3]))!=t[1] or abs(np.linalg.norm(world[k,:3].astype(float)-eye)-t[2])>2e-5
            baseline_bad={k for k,t in truth.items() if wrong(original,k,t)}
            guard_bad={k for k,t in truth.items() if wrong(guarded,k,t)}
            b_hit=original[:,3]>.5
            g_hit=guarded[:,3]>.5
            cases.append({'pose':pose,'union_of_wrong_pixel_ids':len(truth),
               'baseline_errors_on_union':len(baseline_bad),
               'guard_errors_on_union':len(guard_bad),
               'rescued_by_guard':len(baseline_bad-guard_bad),
               'new_errors_by_guard':len(guard_bad-baseline_bad),
               'errors_in_both':len(baseline_bad&guard_bad),
               'baseline_visible_pixels_full_frame':int(b_hit.sum()),
               'guard_visible_pixels_full_frame':int(g_hit.sum()),
               'guard_missing_vs_baseline_full_frame':int((b_hit&~g_hit).sum()),
               'guard_extra_vs_baseline_full_frame':int((~b_hit&g_hit).sum()),
               'critical_owner_baseline':float(original[434*720+416,3]) if pose==1 else None,
               'critical_owner_guard':float(guarded[434*720+416,3]) if pose==1 else None})
        return {'schema':'lie-vulkan-edge-guard-common-union/1',
           'method':'Union of oracle-disagreement pixels from baseline and guard, reevaluating both GPUs on every such pixel; camera packets and oracle hits must agree',
           'cases':cases,
           'limitations':['Biased union; not a population error rate',
                          'This compares GPU to finite captured-cell oracle, never original Blender source',
                          'Guard is ablation only and may introduce false negatives',
                          'No Mali/Android physical performance claim']}


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--artifact',type=Path,required=True)
    p.add_argument('--output',type=Path,required=True)
    args=p.parse_args()
    data=run(args.artifact)
    args.output.parent.mkdir(parents=True,exist_ok=True)
    args.output.write_text(json.dumps(data,indent=2,sort_keys=True)+'\n')
    print(json.dumps(data,indent=2))


if __name__=='__main__':main()
