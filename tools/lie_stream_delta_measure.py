"""Losslessly encode REAL pre-discard Vulkan candidate bitsets as P-frame tile deltas.

Explicitly uses the referenced captured-bank SHA; never compresses or invents
geometry. The pose-0 packet is only a codec demonstration: actual GOP must
start with an I-frame that populates the verified captured-cell cache.
"""
from __future__ import annotations
import argparse
import hashlib
import json
from pathlib import Path
import numpy as np
from lie_stream_candidate_metrics import load_risk
from lie_stream_delta_tiles import N, encode, decode

def measure(captures,bank,output,limit=2400):
    if limit<1:raise ValueError('Tile budget must be positive')
    library=bank/'library.bin'
    if not library.is_file():raise FileNotFoundError(library)
    sha=hashlib.file_digest(library.open('rb'),'sha256').hexdigest()
    if sha!='ca667dfc0e5f5de19190ef12c24395a99b2be66a418420bf30e61ba9ef253340':
        raise ValueError('Bank does not match authenticated LIE 2.5 reference')
    output.mkdir(parents=True,exist_ok=True)
    results=[]
    for pose in range(3):
        src=captures/f'{pose}-native-candidate-risk.bin'
        planes=load_risk(src)
        risk=planes.any(axis=0)
        result=encode(risk,sha,frame_index=pose+1,reference_index=0,max_tiles=limit)
        assert result['no_flags_dropped']
        entry={'pose':pose,'flagged_pixels':int(risk.sum()),
            'first_two_risk_planes_identical':bool(np.array_equal(planes[0],planes[1])),
            'flagged_tiles':result['flagged_tiles'],
            'delta_mode':result['mode'],
            'raw_single_mask_bytes':(N+7)//8,
            'raw_three_planes_bytes':src.stat().st_size}
        if result['mode']=='P':
            out=output/f'lie-risk-pose{pose}-delta.bin'
            out.write_bytes(result['encoded'])
            decoded,meta=decode(out.read_bytes(),sha,expected_reference_index=0)
            if not np.array_equal(decoded,risk):raise AssertionError('Tile delta lost a GPU risk flag!')
            entry.update({'delta_packet_bytes':out.stat().st_size,
                'saved_bytes_vs_raw_single_mask':(N+7)//8-out.stat().st_size,
                'reduction_vs_raw_single_mask':1-out.stat().st_size/((N+7)//8),
                'verified_byte_for_byte_risk_roundtrip':True,
                'encoded_path':str(out),'packet_sha256':hashlib.sha256(out.read_bytes()).hexdigest()})
        else:
            entry.update({'delta_packet_bytes':None,'keyframe_required':True,
                'reason':result['reason']})
        results.append(entry)
    report={'schema':'lie-stream-gop-delta-verified/1',
            'source_bank_sha256':sha,'tile_budget':limit,'tile_width':8,
            'results':results,
            'interpretation':'P-frame packet holds only a lossless first-hit risk worklist; not source surfaces',
            'limits':['Pose 0 is the I-frame reference in a real GOP; its encoded risk packet is a codec fixture only',
                      'Packet validation does not prove GPU rendering correctness',
                      'The real cache must revalidate on bank/proxy changes or camera cuts',
                      'No GPU compact pass or per-pixel ray solver is implemented']}
    (output/'lie-stream-delta-report.json').write_text(json.dumps(report,indent=2)+'\n')
    return report

def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--captures',type=Path,required=True)
    p.add_argument('--bank',type=Path,required=True)
    p.add_argument('--output',type=Path,required=True)
    p.add_argument('--tile-budget',type=int,default=2400)
    args=p.parse_args()
    result=measure(args.captures,args.bank,args.output,args.tile_budget)
    print(json.dumps({k:v for k,v in result.items() if k!='results'},indent=2))
    for row in result['results']:print(json.dumps(row,indent=2))

if __name__=='__main__':main()
