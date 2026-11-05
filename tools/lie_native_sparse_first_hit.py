"""Sparse first-hit risk worklist using ONLY actual native Vulkan outputs.

Native-only detection: independent finite-cell boundary proximity of the
VISIBLE owner plus small 4-connected background gaps. Does not render regions,
consult oracle to choose flags, or pretend the selected sample covers all
errors. Optional second stage independently traces the selected worklist against
the captured-cell bank on CPU: an OFFLINE correctness upper bound, not a GPU fix.
"""
from __future__ import annotations
import argparse
import hashlib
import json
from pathlib import Path
import numpy as np

from lie_real_vulkan_triplet import load_oracle, camera_rays

WIDTH=720
N=WIDTH*WIDTH
# The 96 bricks have 9 owner codes each: p.material.z == instance*9.
BRICK_OWNER_MAX=864


def neighbor_counts(hit: np.ndarray):
    """4-neighbor hit counts, with empty space outside the viewport."""
    m=np.asarray(hit,dtype=bool).reshape(WIDTH,WIDTH)
    out=np.zeros((WIDTH,WIDTH),dtype=np.uint8)
    out[1:,:]+=m[:-1,:]
    out[:-1,:]+=m[1:,:]
    out[:,1:]+=m[:,:-1]
    out[:,:-1]+=m[:,1:]
    return out.ravel()


def boundary_risk(world: np.ndarray,view: np.ndarray,proxies: np.ndarray,
                  surface: dict):
    """Distance to nearest original captured texel edge for the winning pixel.

    This is a detector; it does NOT check competing candidates that were
    discarded by Vulkan. Does not need source depth/color/normal packets.
    """
    if world.shape!=(N,4) or proxies.shape!=(97,48) or view.size<20:
        raise ValueError('Wrong native readback packet dimensions')
    if not np.isfinite(world).all() or not np.isfinite(view).all():
        raise ValueError('Nonfinite native readback')
    hit=(world[:,3]>.5)
    dist=np.full(N,np.inf,dtype=np.float64)
    owners=world[:,3]
    selected=np.flatnonzero(hit&(owners<=BRICK_OWNER_MAX)&(owners>=1))
    inst=((owners[selected]-1).astype(np.int64)//9)
    if np.any((inst<0)|(inst>=96)):
        raise ValueError('Owner instance outside 96-brick bank')

    view=view[:20].astype(np.float64)
    for i in np.unique(inst):
        ix=selected[inst==i]
        p=proxies[i].astype(np.float64)
        inv=p[16:32].reshape(4,4).T
        lo=p[32:35];hi=p[36:39]
        pixel=np.c_[ix%WIDTH+.5,ix//WIDTH+.5]*(2/WIDTH)-1
        dirs=view[12:15]+(view[4:7]*pixel[:,0,None]-view[8:11]*pixel[:,1,None])*view[18]
        o=inv[:3,:3]@view[:3]+inv[:3,3]
        r=dirs@inv[:3,:3].T
        safe=np.where(abs(r)>1e-14,r,np.where(r<0,-1e-14,1e-14))
        ta=(lo-o)/safe;tb=(hi-o)/safe
        entry=np.minimum(ta,tb)
        axis=entry.argmax(axis=1)
        faces=axis*2+(r[np.arange(len(ix)),axis]>0)
        local=world[ix,:3].astype(np.float64)@inv[:3,:3].T+inv[:3,3]
        for face in range(6):
            chosen=faces==face
            if not chosen.any():continue
            ax=face//2
            uv=[k for k in range(3) if k!=ax]
            rect=surface['faces'][surface['boxes'][0]['first_face']+face]
            dims=np.asarray([rect['width'],rect['height']],dtype=np.float64)
            coords=(local[chosen][:,uv]-lo[uv])/(hi[uv]-lo[uv])*dims
            # Numerically distant values and exact integer boundaries are
            # allowed as a detection signal, not interpreted as proof of an error.
            fraction=np.mod(coords,1.)
            dist[ix[chosen]]=np.minimum(fraction,1.-fraction).min(axis=1)
    return dist


def flag_native(world, view, proxies, surface, threshold_cells=0.002,
                gap_neighbors=3):
    if not 0<=threshold_cells<=.5 or gap_neighbors not in (2,3,4):
        raise ValueError('Invalid worklist configuration')
    hit=world[:,3]>.5
    distances=boundary_risk(world,view,proxies,surface)
    edge=(distances<threshold_cells)&hit
    hole=(~hit)&(neighbor_counts(hit)>=gap_neighbors)
    flags=edge|hole
    return flags,{'edge':edge,'small_gap':hole,'nearest_cell_boundary':distances}


def evaluate_known_errors(flags,diagnosis):
    wrong=diagnosis['disagreement_pixels']
    ids=np.asarray([int(row['pixel_id']) for row in wrong],dtype=np.int64)
    if np.any(ids<0) or np.any(ids>=N) or len(np.unique(ids))!=len(ids):
        raise ValueError('Invalid targeted error IDs')
    caught=ids[flags[ids]]
    missed=ids[~flags[ids]]
    return {'known_errors':len(ids),'caught':len(caught),'missed':len(missed),
            'known_error_recall':float(len(caught)/len(ids)) if len(ids) else None,
            'caught_pixel_ids':[int(x) for x in caught],
            'missed_pixel_ids':[int(x) for x in missed],
            'caveat':'Known errors are from a biased oracle sample; recall is NOT a frame-wide probability'}


def oracle_worklist(worklist,world,captures,pose,bank,experimental,
                    tolerance_m=2e-5):
    """Optional OFFLINE CPU oracle replay for *selected* pixels ONLY.

    The same captured-cell oracle defines the reference; it is an upper bound
    for potential corrections and does not validate an independent resolver.
    """
    oracle=load_oracle(experimental,bank)
    eye,dirs,proxies,_,_=camera_rays(captures,pose,worklist,WIDTH)
    distance,owner,second,edge=oracle.trace(eye,dirs,proxies)
    hit=np.isfinite(distance)
    gpu_hit=world[worklist,3]>.5
    gpu_distance=np.linalg.norm(world[worklist,:3].astype(np.float64)-eye,axis=1)
    different=(hit!=gpu_hit)
    different|=(hit&gpu_hit)&((np.rint(world[worklist,3]).astype(np.int64)!=np.rint(owner).astype(np.int64))|
                            (np.abs(gpu_distance-distance)>tolerance_m))
    disagreements=[]
    for local_i in np.flatnonzero(different):
        k=int(worklist[local_i])
        present=bool(hit[local_i])
        disagreements.append({
            'pixel_id':k,'pixel':[k%WIDTH,k//WIDTH],
            'native_owner':int(round(world[k,3])) if gpu_hit[local_i] else None,
            'oracle_owner':int(round(owner[local_i])) if present else None,
            'native_distance_m':float(gpu_distance[local_i]) if gpu_hit[local_i] else None,
            'oracle_distance_m':float(distance[local_i]) if present else None,
            'oracle_world_xyz':(eye+dirs[local_i]*distance[local_i]).tolist() if present else None,
        })
    return {'oracle_rays':len(worklist),'native_vs_oracle_disagreements_on_flags':len(disagreements),
            'correction_plan_world_only':disagreements,
            'warning':'NOT a render, not a distinct algorithmic oracle, and does not resolve normals/materials/reverse-Z'}


def inspect(captures:Path,bank:Path,pose:int,
            threshold_cells=.002,gap_neighbors=3,
            diagnostic:Path|None=None,
            experimental:Path|None=None,resolve=False):
    native_path=captures/f'{pose}-native-world.bin'
    world=np.fromfile(native_path,'<f4')
    if world.size!=N*4:raise ValueError('Expected 720x720 actual native RGBA32F')
    world=world.reshape(N,4)
    vpath=captures/f'{pose}-native-views.bin'
    ppath=captures/f'{pose}-native-proxies.bin'
    view=np.fromfile(vpath,'<f4')
    proxies=np.fromfile(ppath,'<f4')
    if proxies.size!=97*48:raise ValueError('Expected original 97x48 proxy packet')
    proxies=proxies.reshape(97,48)
    surface_path=bank/'direct'/'surface.json'
    surface=json.loads(surface_path.read_text())
    flags,masks=flag_native(world,view,proxies,surface,threshold_cells,gap_neighbors)
    ids=np.flatnonzero(flags).astype(np.int64)
    report={'schema':'lie-native-sparse-risk/1','pose':pose,
       'native_only_detector':True,'width':WIDTH,'height':WIDTH,
       'threshold_cells':threshold_cells,'gap_neighbors':gap_neighbors,
       'flagged_pixels':len(ids),'frame_fraction':float(len(ids)/N),
       'edge_flags':int(masks['edge'].sum()),
       'small_gap_flags':int(masks['small_gap'].sum()),
       'worklist_pixel_ids':[int(k) for k in ids],
       'input_sha256':{
            'native_world':hashlib.sha256(native_path.read_bytes()).hexdigest(),
            'view_packet':hashlib.sha256(vpath.read_bytes()).hexdigest(),
            'proxy_packet':hashlib.sha256(ppath.read_bytes()).hexdigest(),
            'surface_layout':hashlib.sha256(surface_path.read_bytes()).hexdigest()},
       'limits':['Screen-space final-owner boundary detector cannot see rejected contenders',
                 'Owner IDs 865+ (mortar) are not decoded by this brick detector',
                 'Camera-dependent code validated only for archived LIE 2.5 wall',
                 'No fullscreen reference backend is used for flag selection',
                 'No GPU correction, source-mesh fidelity, normals/materials or FPS claim']}
    if diagnostic:
        old=json.loads(diagnostic.read_text())
        if old.get('provenance',{}).get('native_world_sha256')!=report['input_sha256']['native_world']:
            raise ValueError('Oracle diagnosis not based on this exact native GPU readback')
        if old['provenance']['view_sha256']!=report['input_sha256']['view_packet']:
            raise ValueError('Oracle camera packet mismatch')
        report['known_targeted_errors']=evaluate_known_errors(flags,old)
    if resolve:
        if experimental is None:raise ValueError('Experimental branch oracle required')
        report['cpu_oracle_upper_bound']=oracle_worklist(ids,world,captures,pose,bank,experimental)
    return report


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--captures',type=Path,required=True)
    p.add_argument('--bank',type=Path,required=True)
    p.add_argument('--diagnostics',type=Path,help='Directory with lie-native-triplet-pose#.json')
    p.add_argument('--experimental-checkout',type=Path)
    p.add_argument('--resolve-with-oracle',action='store_true',
                   help='OFFLINE CPU reference replay; NOT a production GPU repair')
    p.add_argument('--threshold-cells',type=float,default=.002)
    p.add_argument('--gap-neighbors',type=int,default=3)
    p.add_argument('--pose',type=int,default=1)
    p.add_argument('--output',type=Path,required=True)
    a=p.parse_args()
    diag=a.diagnostics/f'lie-native-triplet-pose{a.pose}.json' if a.diagnostics else None
    out=inspect(a.captures,a.bank,a.pose,a.threshold_cells,a.gap_neighbors,
                diag,a.experimental_checkout,a.resolve_with_oracle)
    a.output.parent.mkdir(parents=True,exist_ok=True)
    a.output.write_text(json.dumps(out,indent=2,allow_nan=False)+'\n')
    summary={k:v for k,v in out.items() if k not in ('worklist_pixel_ids','input_sha256','cpu_oracle_upper_bound')}
    if 'cpu_oracle_upper_bound' in out:
        upper=out['cpu_oracle_upper_bound']
        summary['cpu_oracle_upper_bound']={k:v for k,v in upper.items() if k!='correction_plan_world_only'}
    print(json.dumps(summary,indent=2,allow_nan=False))


if __name__=='__main__':main()
