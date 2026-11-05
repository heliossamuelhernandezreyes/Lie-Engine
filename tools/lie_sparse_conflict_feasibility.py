"""Offline lower bound for sparse LIE first-hit conflict detection from REAL readbacks.

Important: compares TWO complete reference backends. The counts are diagnostic
only; they do not imply an inexpensive in-game detector or solve depth-only
errors where owners agree. The oracle reports target a biased pixel sample.
"""
from __future__ import annotations
import argparse
import json
from pathlib import Path
import zipfile
import numpy as np

N=720*720


def flags(regions,native):
    if regions.shape!=native.shape or regions.shape!=(N,4):
        raise ValueError('Readbacks must be aligned 720x720 RGBA32F packets')
    if not np.isfinite(regions).all() or not np.isfinite(native).all():
        raise ValueError('Nonfinite readback values')
    r=regions[:,3]>.5;n=native[:,3]>.5
    return (r!=n)|((r&n)&(regions[:,3]!=native[:,3]))


def evaluate(regions,native,diagnosis):
    mask=flags(regions,native)
    errors=diagnosis['disagreement_pixels']
    positions=np.asarray([r['pixel_id'] for r in errors],dtype=np.int64)
    if (positions.size and
        (np.any(positions<0) or np.any(positions>=N) or len(np.unique(positions))!=len(positions))):
        raise ValueError('Invalid oracle pixel selection')
    flagged=positions[mask[positions]]
    missed=positions[~mask[positions]]
    return {'full_frame_owner_or_coverage_disagreements':int(mask.sum()),
            'full_frame_fraction':float(mask.mean()),
            'oracle_errors_in_targeted_sample':int(len(positions)),
            'oracle_errors_flagged':int(len(flagged)),
            'oracle_errors_unflagged':int(len(missed)),
            'unflagged_error_pixel_ids':[int(i) for i in missed]}


def analyze_zip(path:Path):
    with zipfile.ZipFile(path) as zip:
        files=zip.namelist()
        def get(suffix):
            f=[n for n in files if n.endswith(suffix)]
            if len(f)!=1:raise ValueError('Expected one archive member '+suffix+', found '+str(len(f)))
            return zip.read(f[0])
        cases=[]
        for pose in range(3):
            native=np.frombuffer(get(f'/lie-native-before/{pose}-native-world.bin'),'<f4')
            regions=np.frombuffer(get(f'/native-depth/{pose}-regions-world.bin'),'<f4')
            if native.size!=N*4 or regions.size!=N*4:
                raise ValueError('Malformed native/regions readback packet')
            diagnosis=json.loads(get(f'/lie-native-triplet-pose{pose}.json'))
            case=evaluate(regions.reshape(N,4),native.reshape(N,4),diagnosis)
            case['pose']=pose
            cases.append(case)
    return {
      'schema':'lie-sparse-conflict-offline-feasibility/1',
      'method':'Compare both full-frame readbacks and targeted captured-cell oracle diagnosis; NOT an in-game cheap conflict detector',
      'cases':cases,
      'limitations':[
          'Region/native disagreement requires both renderers in this offline test; its cost is not measured',
          'Ownership/coverage flags do not capture all same-owner wrong-depth pixels',
          'Targeted oracle errors are not a full-frame population census',
          'No claim of fidelity to original Blender mesh or Android performance']}


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--artifact',type=Path,required=True)
    p.add_argument('--output',type=Path,required=True)
    a=p.parse_args()
    result=analyze_zip(a.artifact)
    a.output.parent.mkdir(parents=True,exist_ok=True)
    a.output.write_text(json.dumps(result,indent=2,sort_keys=True)+'\n')
    print(json.dumps(result,indent=2))


if __name__=='__main__':main()
