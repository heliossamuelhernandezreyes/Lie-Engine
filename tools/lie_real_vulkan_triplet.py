"""Independent captured-cell ray oracle vs ACTUAL Vulkan/Godot readback.

Consumes the original work/lie-native-depth oracle from a separate checkout.
Never substitutes regions for mesh source truth. Requires recovered attributed
wall bank and real *.bin readbacks; no fabricated fallback.
"""
from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import sys

import numpy as np

from lie_geometric_triplet_compare import _compare, _is_different


def digest(path: Path) -> str:
    with path.open('rb') as f:
        return hashlib.file_digest(f, 'sha256').hexdigest()


def load_world(path: Path, expected_pixels: int | None = None):
    data=np.fromfile(path,dtype='<f4')
    if data.size%4:
        raise ValueError(f'{path}: world packet size must be a multiple of 4 floats')
    pixels=data.size//4
    if expected_pixels is not None and pixels!=expected_pixels:
        raise ValueError(f'{path}: pixel count does not match reference')
    if pixels==0:raise ValueError(f'{path}: empty world packet')
    arr=data.reshape(-1,4)
    if not np.isfinite(arr).all():raise ValueError(f'{path}: nonfinite world data')
    return arr


def choose_pixels(regions,native,max_valid=1200,max_empty=1200,seed=343,all_pixels=False):
    if len(regions)!=len(native):raise ValueError('Readback pixel counts differ')
    if all_pixels:return np.arange(len(native),dtype=np.int64)
    rh,nh=regions[:,3]>.5,native[:,3]>.5
    changed=(rh!=nh)|((rh&nh)&(regions[:,3]!=native[:,3]))
    rng=np.random.default_rng(seed)
    same_hit=np.flatnonzero((rh&nh)&~changed)
    same_empty=np.flatnonzero((~rh&~nh)&~changed)
    ids=np.unique(np.r_[np.flatnonzero(changed),
            rng.choice(same_hit,min(max_valid,len(same_hit)),replace=False),
            rng.choice(same_empty,min(max_empty,len(same_empty)),replace=False)])
    return ids.astype(np.int64)


def load_oracle(experimental: Path, bank: Path):
    module_path=experimental/'tools'/'lie_native_oracle.py'
    if not module_path.is_file():
        raise FileNotFoundError('Needs work/lie-native-depth checkout with tools/lie_native_oracle.py')
    spec=importlib.util.spec_from_file_location('lie_native_legacy_oracle',module_path)
    module=importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    direct=bank/'direct'
    module.proof=json.loads((direct/'surface.json').read_text())
    h,w=module.proof['height'],module.proof['width']
    module.field=np.fromfile(direct/'depth.bin','<f4').reshape(h,w,4)
    module.normal=np.fromfile(direct/'normal.bin','<f2').reshape(4,h,w,4)
    if not np.isfinite(module.field).all() or not np.isfinite(module.normal).all():
        raise ValueError('Invalid captured-bank packets')
    return module


def camera_rays(captures: Path, pose: int, pixel_ids, size: int):
    prefix=str(pose)+'-native-'
    proxies_path=captures/(prefix+'proxies.bin')
    views_path=captures/(prefix+'views.bin')
    proxies=np.fromfile(proxies_path,'<f4')
    if proxies.size!=97*48:raise ValueError('Expected original 97x48 instance proxy packet')
    proxies=proxies.reshape(97,48)
    view=np.fromfile(views_path,'<f4')
    if view.size<20:raise ValueError('Invalid native view packet')
    view=view[:20].astype(float)
    eye=view[:3]
    xy=np.c_[pixel_ids%size+.5,pixel_ids//size+.5]*(2/size)-1
    dirs=view[12:15]+(view[4:7]*xy[:,0,None]-view[8:11]*xy[:,1,None])*view[18]
    length=np.linalg.norm(dirs,axis=1)
    if not np.isfinite(eye).all() or not np.isfinite(dirs).all() or np.any(length<=0):
        raise ValueError('Invalid camera directions')
    dirs/=length[:,None]
    return eye,dirs,proxies,views_path,proxies_path


def layer(hits,distances,owners):
    return {'hit':[bool(h) for h in hits],
            'depth_m':[float(x) if h else None for h,x in zip(hits,distances)],
            'owner_id':[int(x) if h else None for h,x in zip(hits,owners)]}


def assess_layers(rep,gpu,source=None,tolerance_m=2e-5):
    n=len(rep['hit'])
    if len(gpu['hit'])!=n:raise ValueError('representation/GPU sample sizes differ')
    if source is not None and len(source['hit'])!=n:raise ValueError('source sample size differs')
    out={'representation_to_vulkan':_compare(rep,gpu,n,tolerance_m),
         'source_status':'provided-independent-original-geometry' if source is not None else 'NOT PROVIDED - source-vs-capture cannot be established'}
    if source is not None:
        out['source_to_representation']=_compare(source,rep,n,tolerance_m)
        out['source_to_vulkan']=_compare(source,gpu,n,tolerance_m)
        categories={'source_only':0,'gpu_only':0,'both':0,'neither':0}
        for i in range(n):
            a=_is_different(source,rep,i,tolerance_m)
            b=_is_different(rep,gpu,i,tolerance_m)
            categories['both' if a and b else 'source_only' if a else 'gpu_only' if b else 'neither']+=1
        out['attribution_sample_counts']=categories
    return out


def load_source(path: Path,indices,view_digest):
    with np.load(path,allow_pickle=False) as packet:
        keys=set(packet.files)
        required={'pixel_ids','distance_m','owner_id','manifest'}
        if not required.issubset(keys):raise ValueError('Source raycast NPZ lacks '+str(sorted(required-keys)))
        meta=json.loads(str(packet['manifest'].item()))
        if meta.get('kind')!='independent-original-mesh-raycast':
            raise ValueError('Source raycast must identify the ORIGINAL mesh, not captured cells')
        if meta.get('view_packet_sha256')!=view_digest:
            raise ValueError('Source raycast and Vulkan camera packets differ')
        if not isinstance(meta.get('source_mesh_sha256'),str) or len(meta['source_mesh_sha256'])!=64:
            raise ValueError('Original source geometry hash required')
        pix=packet['pixel_ids'].astype(np.int64)
        if len(pix)!=len(np.unique(pix)) or not np.array_equal(np.sort(pix),np.sort(indices)):
            raise ValueError('Source-raycast pixel IDs must match chosen oracle pixel IDs exactly')
        lookup={int(p):i for i,p in enumerate(pix)}
        selected=np.array([lookup[int(i)] for i in indices])
        d=packet['distance_m'][selected]
        owners=packet['owner_id'][selected]
        if len(d)!=len(indices) or len(owners)!=len(indices):raise ValueError('Source arrays have wrong lengths')
        hits=owners>=0
        if not np.isfinite(d[hits]).all() or np.any(d[hits]<0):raise ValueError('Invalid source ray distances')
        return layer(hits,d,owners),meta


def analyze(captures: Path,bank: Path,experimental: Path,pose=0,
            source_path=None,max_valid=1200,max_empty=1200,
            all_pixels=False,seed=343,tolerance_m=2e-5,details=False):
    prefix=str(pose)+'-'
    region_file=captures/(prefix+'regions-world.bin')
    native_file=captures/(prefix+'native-world.bin')
    region_world=load_world(region_file)
    native_world=load_world(native_file,len(region_world))
    size=int(round(len(native_world)**.5))
    if size*size!=len(native_world):
        raise ValueError('Native reference script requires square viewport')
    indices=choose_pixels(region_world,native_world,max_valid,max_empty,seed,all_pixels)
    eye,dirs,proxies,views_path,proxies_path=camera_rays(captures,pose,indices,size)
    oracle=load_oracle(experimental,bank)
    distances,owners,second,edge=oracle.trace(eye,dirs,proxies)
    truth_hits=np.isfinite(distances)
    rep=layer(truth_hits,distances,owners)
    gpu_hits=native_world[indices,3]>.5
    actual=np.linalg.norm(native_world[indices,:3].astype(float)-eye,axis=1)
    gpu=layer(gpu_hits,actual,native_world[indices,3])
    src=meta=None
    if source_path is not None:
        src,meta=load_source(source_path,indices,digest(views_path))
    stats=assess_layers(rep,gpu,src,tolerance_m)
    region=layer(region_world[indices,3]>.5,
                 np.linalg.norm(region_world[indices,:3].astype(float)-eye,axis=1),
                 region_world[indices,3])
    stats['regions_to_vulkan']=_compare(region,gpu,len(indices),tolerance_m)
    stats['representation_to_regions']=_compare(rep,region,len(indices),tolerance_m)
    status=[]
    for i in range(len(indices)):
        if _is_different(rep,gpu,i,tolerance_m):status.append(i)
    diagnostics=[]
    for j in (range(len(indices)) if details else status):
        k=int(indices[j])
        item={'pixel_id':k,'x':k%size,'y':k//size,
            'representation_hit':bool(rep['hit'][j]),
            'gpu_hit':bool(gpu['hit'][j]),
            'representation_owner':rep['owner_id'][j],
            'gpu_owner':gpu['owner_id'][j],
            'representation_distance_m':rep['depth_m'][j],
            'gpu_distance_m':gpu['depth_m'][j]}
        if src is not None:
            item['source_hit']=bool(src['hit'][j])
            item['source_owner']=src['owner_id'][j]
            item['source_distance_m']=src['depth_m'][j]
        diagnostics.append(item)
    return {'schema':'lie-real-readback-oracle/1','scope':'actual Vulkan readback vs float64 finite captured-cell oracle, NEVER original mesh without separately supplied source NPZ',
        'pose':pose,'viewport':[size,size],'samples':len(indices),
        'sampling':'ALL pixels, expensive' if all_pixels else 'ALL disagreement pixels (regions/native coverage or owner) plus seeded unchanged hits/background; TARGETED, not a population estimate',
        'seed':seed,'depth_tolerance_m':tolerance_m,
        'provenance':{'captured_bank_surface_sha256':digest(bank/'direct'/'surface.json'),
            'captured_bank_depth_sha256':digest(bank/'direct'/'depth.bin'),
            'captured_bank_normal_sha256':digest(bank/'direct'/'normal.bin'),
            'view_sha256':digest(views_path),'proxies_sha256':digest(proxies_path),
            'regions_world_sha256':digest(region_file),'native_world_sha256':digest(native_file),
            'experimental_oracle':str(experimental/'tools'/'lie_native_oracle.py'),
            **({'source_manifest':meta} if meta is not None else {})},
        'summary':stats,'disagreement_pixels':diagnostics,
        'limits':['CPU float64 against capture cells, not original mesh unless sourced independently',
            'software Vulkan is not Mali FPS',
            'selected samples are not a random population rate',
            'differences may arise at precision ties and discontinuities',
            'does not test RGB, normals or lighting',
            'both-stage mismatch cannot be uniquely attributed']}


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--captures',required=True,type=Path,help='Native Vulkan binary readbacks (0-*-world.bin etc)')
    p.add_argument('--bank',required=True,type=Path,help='Captured wall bank with direct/surface.json and original packets')
    p.add_argument('--experimental-checkout',required=True,type=Path,help='work/lie-native-depth checkout with original oracle')
    p.add_argument('--pose',type=int,default=0)
    p.add_argument('--source-npz',type=Path,help='OPTIONAL independent ORIGINAL-MESH raycast, same exact camera/IDs')
    p.add_argument('--all-pixels',action='store_true',help='Trace entire viewport: expensive')
    p.add_argument('--max-valid',type=int,default=1200)
    p.add_argument('--max-empty',type=int,default=1200)
    p.add_argument('--seed',type=int,default=343)
    p.add_argument('--depth-tolerance-m',type=float,default=2e-5)
    p.add_argument('--all-details',action='store_true')
    p.add_argument('--output',required=True,type=Path)
    args=p.parse_args()
    if args.max_valid<0 or args.max_empty<0 or not np.isfinite(args.depth_tolerance_m) or args.depth_tolerance_m<0:
        p.error('Invalid selection/precision controls')
    result=analyze(args.captures,args.bank,args.experimental_checkout,args.pose,args.source_npz,
            args.max_valid,args.max_empty,args.all_pixels,args.seed,args.depth_tolerance_m,args.all_details)
    args.output.parent.mkdir(parents=True,exist_ok=True)
    args.output.write_text(json.dumps(result,indent=2,allow_nan=False)+'\n')
    print(json.dumps({k:v for k,v in result.items() if k!='disagreement_pixels'},indent=2,allow_nan=False))
    print('Disagreement pixels saved:',len(result['disagreement_pixels']),args.output)


if __name__=='__main__':main()
