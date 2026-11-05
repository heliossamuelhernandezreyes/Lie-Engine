"""Optional independent ORIGINAL scanned-mesh oracle for WALL06.

NOT the LIE sample bank. Reads only the authenticated 500K-triangle GLB,
reconstructs its published legacy frame and WALL06 rigid alignment, then
ray-tests actual source triangles from the recorded phone camera.

We compare source mesh vs the matching BRICK's captured disk/field/GPU.
Mortar is authored from a different source: it is explicitly EXCLUDED.
A result for one brick cannot certify its entire scene or lighting.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import sys

import numpy as np

from lie_brick02_capture_scan import load_source,frame_for_brick
from lie_wall25_sufficiency import (build_masters,source_trace,
                                  pixels_for_probe,camera_rays)
import lie_native_oracle as cell_oracle
from lie_direct_surface import BANK_SHA

ORIGINAL_SHA='b55b9d584fcfa6d7baf9e1d815c02578d91e092efc4cf88a47c23bbee643031b'


def transform_original(meshes, catalog):
    brick_catalog=json.loads((Path(__file__).resolve().parents[1]/
         'gpu_compute/assets/lie_brick02/catalog.json').read_text())
    perm,scale,center=frame_for_brick(meshes,float(brick_catalog['brick_measurement_m']))
    if list(map(int,perm)) != list(map(int,brick_catalog['permutation_source_to_lie'])):
        raise ValueError('Original GLB legacy frame changed')
    R=np.asarray(catalog['wall06']['rotation'],dtype=np.float64)
    t=np.asarray(catalog['wall06']['translation_m'],dtype=np.float64)
    if R.shape!=(3,3) or not np.allclose(R@R.T,np.eye(3),atol=2e-4):
        raise ValueError('Wall orientation is not the preserved rigid transform')
    if t.shape!=(3,):raise ValueError('Missing wall alignment translation')
    import trimesh
    transformed=[]
    for mesh in meshes:
        points=(np.asarray(mesh.vertices,dtype=np.float64)-center)[:,perm]*scale
        aligned=points@R.T+t
        transformed.append(trimesh.Trimesh(vertices=aligned,
            faces=np.asarray(mesh.faces,dtype=np.int64),process=False,validate=False))
    return trimesh.util.concatenate(transformed)


def hit_original_mesh(mesh, eye, dirs, proxy_packet):
    """Ray intersections in exactly the recorded GPU proxy's local frame."""
    local=proxy_packet[16:32].reshape(4,4).T.astype(np.float64)
    p=local[:3,:3]@eye+local[:3,3]
    d=dirs@local[:3,:3].T
    from trimesh.ray.ray_triangle import RayMeshIntersector
    if len(d)==0:return np.zeros(0,dtype=np.float64)
    # One multi-ray query against original triangles, NOT LIE's cell field.
    loc,rayidx,_=RayMeshIntersector(mesh).intersects_location(
        ray_origins=np.repeat(p[None,:],len(d),axis=0),
        ray_directions=d,multiple_hits=False)
    t=np.full(len(d),np.inf,np.float64)
    if len(rayidx):
        w=loc-p
        param=np.einsum('ij,ij->i',w,d[rayidx]) / np.einsum('ij,ij->i',d[rayidx],d[rayidx])
        okay=param>1e-7
        t[rayidx[okay]]=param[okay]
    return t


def compare(root:Path,glb:Path,captures:Path,output:Path,limit:int=96):
    if hashlib.sha256(glb.read_bytes()).hexdigest()!=ORIGINAL_SHA:
        raise ValueError('Exact original Stratford scan GLB SHA mismatch')
    cat=json.loads((root/'catalog.json').read_text())
    proof=json.loads((root/'direct/surface.json').read_text())
    if proof['source_bank_sha256']!=BANK_SHA:
        raise ValueError('Only the verified WALL06 captured bank is accepted')
    meshes=load_source(glb)
    triangle_count=sum(len(m.faces) for m in meshes)
    if triangle_count!=500000:raise ValueError('Original mesh triangle count changed')
    mesh=transform_original(meshes,cat)
    regions=np.fromfile(captures/'0-regions-world.bin','<f4').reshape(-1,4)
    native=np.fromfile(captures/'0-native-world.bin','<f4').reshape(-1,4)
    size=int(round(np.sqrt(len(native))))
    if size*size!=len(native) or size!=720:raise ValueError('Mismatched native outputs')
    px,disagreements=pixels_for_probe(regions,native,128,144,64)
    packets=np.fromfile(captures/'0-native-proxies.bin','<f4').reshape(97,48)
    view=np.fromfile(captures/'0-native-views.bin','<f4')[:20]
    eye,dirs=camera_rays(view,px,size)
    masters=build_masters(root,proof,cat)
    bank_t,bank_id,_=source_trace(eye,dirs,packets,masters)
    cell_oracle.proof=proof
    cell_oracle.field=np.fromfile(root/'direct/depth.bin','<f4').reshape(proof['height'],proof['width'],proof['layers'])
    cell_oracle.normal=np.fromfile(root/'direct/normal.bin','<f2').reshape(proof['layers'],proof['height'],proof['width'],4)
    cell_t,cell_id,_,_=cell_oracle.trace(eye,dirs,packets)

    # Only bricks that appear as the foremost bank surface: a mortar winner
    # is not compared to the original scan of a different physical object.
    bk_group=np.floor_divide(np.maximum(np.rint(bank_id).astype(int)-1,0),9)
    eligible=np.flatnonzero((bank_id>0)&(bank_id<=864)&np.isfinite(bank_t))
    if not len(eligible):raise ValueError('No eligible brick rays in phone pose')
    rng=np.random.default_rng(344)
    chosen=rng.choice(eligible,size=min(limit,len(eligible)),replace=False)
    chosen=np.sort(chosen)
    source_t=np.full(len(chosen),np.inf)
    for instance in np.unique(bk_group[chosen]):
        ids=np.flatnonzero(bk_group[chosen]==instance)
        source_t[ids]=hit_original_mesh(mesh,eye,dirs[chosen[ids]],packets[int(instance)])
    bank_depth=bank_t[chosen];cell_depth=cell_t[chosen]
    gpu_world=native[px[chosen]]
    gpu_t=np.linalg.norm(gpu_world[:,:3].astype(float)-eye,axis=1)
    source_hits=np.isfinite(source_t)
    bank_hits=np.isfinite(bank_depth)
    matched=source_hits&bank_hits
    error=np.abs(source_t[matched]-bank_depth[matched])
    rows=[]
    for j,i in enumerate(chosen):
        rows.append(dict(pixel=int(px[i]),x=int(px[i]%size),y=int(px[i]//size),
          brick_instance=int(bk_group[i]),source_t_m=float(source_t[j]) if np.isfinite(source_t[j]) else None,
          bank_t_m=float(bank_depth[j]),field_t_m=float(cell_depth[j]) if np.isfinite(cell_depth[j]) else None,
          field_brick_group=(int((round(cell_id[i])-1)//9) if 0<cell_id[i]<=864 else None),
          gpu_t_m=(float(gpu_t[j]) if gpu_world[j,3]>.5 else None),
          gpu_id=(int(round(gpu_world[j,3])) if gpu_world[j,3]>.5 else 0)))
    report={
      'schema':'lie25-original-glb-brick-vs-captured-bank/1',
      'source_mesh_sha256':ORIGINAL_SHA,'source_mesh_triangles':triangle_count,
      'source':'original authorized CC BY 4.0 scanned mesh, transformed using original frame and WALL06 alignment',
      'scope':'ONLY target brick original geometry vs matching finite source disks at bank-visible pixels. Mortar not in this oracle; no complete scene/source proof.',
      'camera':'exact stored phone pose packets',
      'candidate_disagreements_regions_native':int(disagreements),
      'eligible_bank_brick_rays':int(len(eligible)),
      'tested_brick_rays':int(len(chosen)),
      'source_mesh_hit_count':int(source_hits.sum()),
      'original_mesh_missing_where_bank_hits':int((~source_hits&bank_hits).sum()),
      'depth_error_vs_bank_m_p50':float(np.percentile(error,50)) if len(error) else None,
      'depth_error_vs_bank_m_p95':float(np.percentile(error,95)) if len(error) else None,
      'depth_error_vs_bank_m_max':float(error.max()) if len(error) else None,
      'depth_gt_1mm':int((error>.001).sum()),
      'depth_gt_5mm':int((error>.005).sum()),
      'rows':rows
    }
    output.parent.mkdir(parents=True,exist_ok=True)
    output.write_text(json.dumps(report,indent=2,allow_nan=False)+'\n')
    print(json.dumps({k:v for k,v in report.items() if k!='rows'},indent=2))
    return report


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--bank',type=Path,required=True)
    p.add_argument('--source-glb',type=Path,required=True)
    p.add_argument('--captures',type=Path,required=True)
    p.add_argument('--output',type=Path,required=True)
    p.add_argument('--limit',type=int,default=96)
    a=p.parse_args()
    compare(a.bank,a.source_glb,a.captures,a.output,a.limit)


if __name__=='__main__':main()
