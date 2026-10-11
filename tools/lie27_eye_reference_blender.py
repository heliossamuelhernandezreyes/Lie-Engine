"""Identify actual source eyeball captures for an independent occlusion check."""
import argparse,hashlib,json,sys
from pathlib import Path
import bpy,numpy as np
from mathutils import Vector
from mathutils.bvhtree import BVHTree
sys.path.insert(0,str(Path(__file__).resolve().parent))
from lie27_prepare_blender import geometry,SOURCE_SHA

def main():
    p=argparse.ArgumentParser();p.add_argument('--input',type=Path,required=True);p.add_argument('--root',type=Path,required=True)
    args=p.parse_args(sys.argv[sys.argv.index('--')+1:])
    if hashlib.file_digest(args.input.open('rb'),'sha256').hexdigest()!=SOURCE_SHA:raise ValueError('Unknown source')
    bpy.ops.wm.open_mainfile(filepath=str(args.input.resolve()),load_ui=False,use_scripts=False)
    points,faces=geometry(bpy.data.objects['eyeball']);tree=BVHTree.FromPolygons(points.tolist(),faces.tolist(),all_triangles=True)
    data=np.memmap(args.root/'samples.bin',dtype='<f4',mode='r').reshape(-1,20)
    candidates=np.flatnonzero((data[:,3]>=0)&np.all(data[:,:3]>=points.min(0)-.00003,axis=1)&np.all(data[:,:3]<=points.max(0)+.00003,axis=1))
    result={'left':[],'right':[],'tolerance_m':.00003,'source_sha256':SOURCE_SHA,'method':'distance to native eyeball triangle BVH; direct captures only'}
    for index in candidates:
        hit,normal,triangle,distance=tree.find_nearest(Vector(data[index,:3]),.00003)
        if hit is not None:result['left' if data[index,0]>0 else 'right'].append(int(index))
    if not result['left'] or not result['right']:raise ValueError('Both native eyeballs must have captured samples')
    (args.root/'eyeball-sample-indices.json').write_text(json.dumps(result,indent=2)+'\n')
    print('EYEBALL_REFERENCE27',len(result['left']),len(result['right']),flush=True)

if __name__=='__main__':main()
