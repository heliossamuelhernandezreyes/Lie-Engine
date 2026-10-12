"""Share native rim shading and extend intact skin through the chin.

Run in Blender against an attributed LIE-27 bank. This changes captured
normals/material identity, never positions, source meshes or sample counts.
"""
import argparse,hashlib,json,sys
from pathlib import Path
import numpy as np
from mathutils import Vector
from mathutils.bvhtree import BVHTree
sys.path.insert(0,str(Path(__file__).resolve().parent))
from lie27_skin_eyes import smooth_normals,head_integrity
from lie26_prepare_blender import barycentric

def polish(root):
    m=json.loads((root/'master.json').read_text())
    for name,item in m['buffers'].items():
        p=root/name
        if p.stat().st_size!=item['bytes'] or hashlib.file_digest(p.open('rb'),'sha256').hexdigest()!=item['sha256']:
            raise ValueError('Invalid input buffer: '+name)
    data=np.fromfile(root/'samples.bin',dtype='<f4').reshape(-1,20)
    r=np.load(root/'orbital-source-reference.npz');p=r['points'];f=r['faces']
    normals=smooth_normals(p,f);native=smooth_normals(r['original_points'],r['original_faces']);normals[:len(native)]=native
    tree=BVHTree.FromPolygons(p.tolist(),f.tolist(),all_triangles=True)
    head_count=sum(v['samples'] for v in m['native_head_galleries'])
    lid_count=sum(v['samples'] for gallery in m['orbital_galleries'] for v in gallery['views'])
    start=m['layers'][0]['sample_count']-head_count-lid_count-m.get('chin_sample_count',0);total=0
    for gallery in m['native_head_galleries']:
        path=root/gallery['file']
        with np.load(path) as z:arrays={key:z[key] for key in z.files}
        valid=np.isfinite(arrays['rest_xyz']).all(axis=2);xyz=arrays['rest_xyz'][valid]
        if len(xyz)!=gallery['samples'] or not np.array_equal(data[start:start+len(xyz),:3],xyz):
            raise ValueError('Capture row ordering mismatch: '+gallery['file'])
        values=np.empty_like(xyz)
        for i,point in enumerate(xyz):
            hit,n,ti,distance=tree.find_nearest(Vector(point),.00003)
            if hit is None:raise ValueError('Native captured point not on its source')
            ids=f[ti];value=barycentric(point,*p[ids])@normals[ids];values[i]=value/np.linalg.norm(value)
        data[start:start+len(xyz),4:7]=values;arrays['normal'][valid]=values
        np.savez_compressed(path,**arrays);gallery['sha256']=hashlib.sha256(path.read_bytes()).hexdigest()
        start+=len(xyz);total+=len(xyz)
        print('SHARED_RIM27',gallery['file'],len(xyz),flush=True)
    v=np.fromfile(root/'vertices.bin',dtype='<f4').reshape(-1,24)
    t=np.fromfile(root/'triangles.bin',dtype='<u4').reshape(-1,4)
    gates=head_integrity(data,p,f,m['eyes'],v,t)
    temporary=root/'samples.bin.tmp';data.astype('<f4').tofile(temporary)
    if temporary.stat().st_size!=m['sample_count']*80:raise ValueError('Truncated sample output')
    temporary.replace(root/'samples.bin')
    m['buffers']['samples.bin']['sha256']=hashlib.file_digest((root/'samples.bin').open('rb'),'sha256').hexdigest()
    m.update(skin_gate_contract='intact-head-region-v2',skin_gate_min_y_m=1.40,skin_gate_footprint_padding=2,
             skin_gate_samples=gates,boundary_normals_contract='shared-native-rim-v1',
             skin_gate_method='intact head region in source space, including footprint support; native eyes exempt; full inner anatomy restored when skin disabled')
    np.column_stack([data[:,15],data[:,19]]).astype('u1').tofile(root/'sample-material-reference.bin')
    (root/'master.json').write_text(json.dumps(m,indent=2)+'\n')
    print('FACE_POLISH27',total,'shared normal samples',gates,flush=True)

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--root',type=Path,required=True)
    args=parser.parse_args(sys.argv[sys.argv.index('--')+1:]);polish(args.root)

if __name__=='__main__':main()
