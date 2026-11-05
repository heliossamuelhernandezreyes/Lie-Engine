"""Blender-side original wall mesh raycast at the exact LIE captured Vulkan camera.

Run ONLY against the authentic, inspected original mesh scene. Never use this
script against regenerated capture cells: that would not be independent source.
The object->native-owner IDs and runtime->Blender coordinates must be supplied
and reviewed explicitly; unknown intersected objects fail closed.

blender --background ORIGINAL.blend --python tools/lie_blender_original_raycast.py -- \
  --captures /path/native-depth --ray-report /tmp/lie-wall-rep-gpu.json \
  --owner-map /path/original-owner-map.json \
  --runtime-to-blender /path/runtime-to-blender.json \
  --output /tmp/lie-wall-original-rays.npz
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path
import sys

import numpy as np


def digest(path):
    with Path(path).open('rb') as f:
        return hashlib.file_digest(f,'sha256').hexdigest()


def matrix_from_file(path):
    data=json.loads(Path(path).read_text())
    raw=data.get('runtime_to_blender',None)
    mat=np.asarray(raw,dtype=np.float64)
    if mat.shape!=(4,4) or not np.isfinite(mat).all() or not np.allclose(mat[3,:],[0,0,0,1],atol=1e-12):
        raise ValueError('runtime_to_blender must be a finite affine 4x4 row-major matrix')
    if abs(np.linalg.det(mat[:3,:3]))<1e-12:
        raise ValueError('runtime_to_blender matrix is singular')
    return mat


def camera(captures,pose,pixel_ids,size):
    view_path=Path(captures)/(str(pose)+'-native-views.bin')
    view=np.fromfile(view_path,'<f4')
    if view.size<20:raise ValueError('Incomplete original Vulkan view packet')
    view=view[:20].astype(float)
    eye=view[:3]
    xy=np.c_[pixel_ids%size+.5,pixel_ids//size+.5]*(2/size)-1
    dirs=view[12:15]+view[4:7]*xy[:,0,None]-view[8:11]*xy[:,1,None]
    # The native shader scales the XY offsets with view[18].
    dirs=view[12:15]+(view[4:7]*xy[:,0,None]-view[8:11]*xy[:,1,None])*view[18]
    lengths=np.linalg.norm(dirs,axis=1)
    if not np.isfinite(dirs).all() or np.any(lengths<=0):
        raise ValueError('Invalid view ray directions')
    return eye,dirs/lengths[:,None],view_path


def original_rays(scene,depsgraph,eye,dirs,runtime_to_blender,owner_map):
    """Cast against Blender's original scene in the supplied coordinate frame."""
    from mathutils import Vector
    inv=np.linalg.inv(runtime_to_blender)
    origin_b=runtime_to_blender[:3,:3]@eye+runtime_to_blender[:3,3]
    owners=np.full(len(dirs),-1,dtype=np.int64)
    depths=np.full(len(dirs),np.inf,dtype=np.float64)
    for i,ray in enumerate(dirs):
        vec=runtime_to_blender[:3,:3]@ray
        norm=np.linalg.norm(vec)
        if norm<=1e-16:raise ValueError('Ray direction degenerated under coordinate conversion')
        hit,pos,normal,face,obj,matrix=scene.ray_cast(depsgraph,Vector(origin_b),Vector(vec/norm),distance=1e6)
        if not hit:continue
        if obj is None or obj.name not in owner_map:
            raise ValueError(f'Original scene hit unmapped object: {obj.name if obj else "<no object>"}; source is not attributable')
        owners[i]=owner_map[obj.name]
        position=np.asarray(pos,dtype=float)
        original=inv[:3,:3]@position+inv[:3,3]
        depths[i]=float(np.linalg.norm(original-eye))
    return depths,owners


def main():
    import bpy
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--captures',required=True,type=Path)
    parser.add_argument('--ray-report',required=True,type=Path,help='First run the captured-cell comparison to select exact pixel IDs')
    parser.add_argument('--owner-map',required=True,type=Path,help='JSON {object_name: native_owner_id}; must match native owner identity scheme')
    parser.add_argument('--runtime-to-blender',required=True,type=Path,help='JSON {runtime_to_blender: [[...],...]} with verified axis/scale alignment')
    parser.add_argument('--output',required=True,type=Path)
    args=parser.parse_args(sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else [])
    original=Path(bpy.data.filepath)
    if not original.is_file():parser.error('Open the exact original .blend file first')
    report=json.loads(args.ray_report.read_text())
    if report.get('schema')!='lie-real-readback-oracle/1':
        parser.error('Ray selection must come from real readback adapter')
    pose=report['pose']
    size=report['viewport'][0]
    if report['viewport']!=[size,size]:parser.error('Square native camera required')
    ids=np.asarray(report['selected_pixel_ids'],dtype=np.int64)
    if len(ids)!=int(report['samples']) or len(np.unique(ids))!=len(ids) or np.any(ids<0) or np.any(ids>=size**2):
        parser.error('Invalid saved pixel selection')
    if not ids.size:parser.error('Empty selection')
    owner_map=json.loads(args.owner_map.read_text())
    if not isinstance(owner_map,dict) or not owner_map or not all(isinstance(k,str) and k and type(v) is int and v>=0 for k,v in owner_map.items()):
        parser.error('owner-map must contain nonnegative integer owner IDs and named objects')
    mat=matrix_from_file(args.runtime_to_blender)
    eye,dirs,view_path=camera(args.captures,pose,ids,size)
    if report['provenance']['view_sha256']!=digest(view_path):
        parser.error('Ray report and current Vulkan view packet differ')
    depsgraph=bpy.context.evaluated_depsgraph_get()
    depths,owners=original_rays(bpy.context.scene,depsgraph,eye,dirs,mat,owner_map)
    manifest={'kind':'independent-original-mesh-raycast',
        'source_mesh_sha256':digest(original),
        'source_mesh_path_name':original.name,
        'owner_namespace':'lie-native-wall-owner-v1',
        'owner_mapping_sha256':digest(args.owner_map),
        'runtime_to_blender_sha256':digest(args.runtime_to_blender),
        'view_packet_sha256':digest(view_path),
        'pose':pose,'viewport':[size,size],
        'scope':'independent Blender scene BVH rays; original .blend only; verified owner map and coordinate transform supplied by operator',
        'limitations':['Same geometry provenance must be established by operator; image comparison cannot prove scene identity',
                       'Unmapped non-hit objects outside selected rays are not validated',
                       'Owner IDs only comparable if mapping matches runtime native ownership semantics']}
    args.output.parent.mkdir(parents=True,exist_ok=True)
    np.savez_compressed(args.output,
        pixel_ids=ids,distance_m=depths,owner_id=owners,
        manifest=json.dumps(manifest,sort_keys=True))
    print(json.dumps({'output':str(args.output),'rays':int(len(ids)),
        'original_hits':int(np.sum(owners>=0)),'original_blend_sha256':manifest['source_mesh_sha256'],
        'view_packet_sha256':manifest['view_packet_sha256'],
        'warning':'This counts as original source ONLY if authentic source and transforms are verified.'},indent=2))


if __name__=='__main__':main()
