"""A/B-only boundary guard for *staged* LIE native GLSL, not production.

Experiment deliberately rejects candidate patches within 0.001 capture cells
of their rectangle bounds. This can CREATE false negatives; it is an ablation
to test the float32-boundary hypothesis, NOT a final shader correction.
"""
from __future__ import annotations
import argparse
import json
from pathlib import Path
import numpy as np

ORIGINAL='if(any(lessThan(capture_cell,patch_cells.xy))||any(greaterThanEqual(capture_cell,patch_cells.zw)))discard;'
GUARD='''// EXPERIMENT ONLY: uncertain FP32 boundary region, NOT accepted production fix.
    const vec2 lie_edge_guard=vec2(0.001);
    if(any(lessThan(capture_cell,patch_cells.xy+lie_edge_guard))||
       any(greaterThanEqual(capture_cell,patch_cells.zw-lie_edge_guard)))discard;'''


def apply(shader: Path):
    old=shader.read_text()
    if old.count(ORIGINAL)!=1 or 'lie_edge_guard' in old:
        raise ValueError('Unexpected staged shader; refusing unverified replacement')
    shader.write_text(old.replace(ORIGINAL,GUARD))
    return {'shader':str(shader),'guard_capture_cell_units':.001,
            'note':'Staged experimental shader only; do not commit generated patched GLSL as accepted fix'}


def describe_frame(path: Path,index: int):
    pixels=np.fromfile(path,'<f4')
    if pixels.size!=720*720*4:raise ValueError('Expected real 720x720 native world readback')
    pixels=pixels.reshape(-1,4)
    hit=pixels[:,3]>.5
    p=pixels[index]
    return {'pixel_owner':float(p[3]),'pixel_world_xyz':p[:3].astype(float).tolist(),
            'visible_pixels':int(hit.sum()),'world':pixels}


def summarize(before: Path,after: Path,pose: int=1,x: int=416,y: int=434):
    pixel=y*720+x
    b=describe_frame(before/f'{pose}-native-world.bin',pixel)
    a=describe_frame(after/f'{pose}-native-world.bin',pixel)
    original=b.pop('world');modified=a.pop('world')
    hb=original[:,3]>.5;ha=modified[:,3]>.5
    owners_changed=(original[:,3]!=modified[:,3])&(hb&ha)
    changed_position=np.any(original[:,:3]!=modified[:,:3],axis=1)&(hb&ha)
    return {'schema':'lie-native-edge-guard-ablation/1','pose':pose,'pixel':[x,y],
            'baseline':b,'guard':a,
            'missing_vs_baseline':int((hb&~ha).sum()),
            'extra_vs_baseline':int((~hb&ha).sum()),
            'owner_changes_on_overlap':int(owners_changed.sum()),
            'position_changes_on_overlap':int(changed_position.sum()),
            'warning':'Comparison between two native Vulkan renderings; baseline is NOT source geometry ground truth. A guard can create holes. Independent captured-cell oracle must evaluate both.'}


def main():
    p=argparse.ArgumentParser(description=__doc__)
    subs=p.add_subparsers(dest='cmd',required=True)
    a=subs.add_parser('apply');a.add_argument('--shader',type=Path,required=True)
    b=subs.add_parser('summarize');b.add_argument('--before',type=Path,required=True)
    b.add_argument('--after',type=Path,required=True);b.add_argument('--output',type=Path,required=True)
    b.add_argument('--pose',type=int,default=1)
    args=p.parse_args()
    if args.cmd=='apply':data=apply(args.shader)
    else:
        data=summarize(args.before,args.after,args.pose)
        args.output.parent.mkdir(parents=True,exist_ok=True)
        args.output.write_text(json.dumps(data,indent=2)+'\n')
    print(json.dumps(data,indent=2))


if __name__=='__main__':main()
