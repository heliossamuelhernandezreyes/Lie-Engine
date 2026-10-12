"""Bind capture hits crossing weight-field seams to sparse source triangles.

The triangles are invisible deformation references. Their vertices move once
per pose; captured pixels interpolate those positions. Interior samples keep
the cheaper rigid/two-bone path. No source triangle is rasterized or shaded.
"""
import argparse,gc,hashlib,json,sys
from pathlib import Path
import numpy as np
from mathutils import Vector
from mathutils.bvhtree import BVHTree
sys.path.insert(0,str(Path(__file__).resolve().parent))
from lie26_prepare_blender import barycentric

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--root',type=Path,required=True);args=parser.parse_args(sys.argv[sys.argv.index('--')+1:]);root=args.root;master=json.loads((root/'master.json').read_text());data=np.fromfile(root/'samples.bin',dtype='<f4').reshape(-1,20)
    if master.get('sparse_joint_bindings'):raise ValueError('Already bound; restore the unbound bank before rebinding')
    vertices=list(np.fromfile(root/'vertices.bin',dtype='<f4').reshape(-1,24));triangles=list(np.fromfile(root/'triangles.bin',dtype='<u4').reshape(-1,4));bound=0
    for lid in [0,1,3]:
        cursor=master['layers'][lid]['sample_offset']
        for gallery in [v for v in master['capture_views'] if v['layer']==lid]:
            bid=gallery['bone'];count=gallery['samples'];rows=data[cursor:cursor+count];cursor+=count
            parts=[bid] if not gallery['pose'] else [master['bones'][bid]['parent'],bid];points=[];faces=[];a=[];b=[];w=[];offset=0
            for part in parts:
                source=np.load(root/f'source-{lid}-{part}.npz');p=source['points'];points.append(p);faces.append(source['faces']+offset);offset+=len(p);a.append(source['first']);b.append(source['second']);w.append(source['weight'])
            points=np.concatenate(points);faces=np.concatenate(faces);a=np.concatenate(a);b=np.concatenate(b);w=np.concatenate(w)
            mixed=np.any(a[faces]!=a[faces[:,0:1]],axis=1)|np.any(b[faces]!=b[faces[:,0:1]],axis=1)
            if not mixed.any():continue
            # Only source faces where the two-bone pair changes require the
            # sparse path. Include immediate pair gradients near those seams.
            selected=faces[mixed];tree=BVHTree.FromPolygons(points.tolist(),selected.tolist(),all_triangles=True);vmap={};tmap={};n=0
            for i,row in enumerate(rows):
                if not 0<row[13]<1:continue
                p,normal,ti,distance=tree.find_nearest(Vector(row[:3]),.000002)
                if p is None:continue
                ids=selected[ti];bc=barycentric(np.asarray(p),*points[ids])
                if ti not in tmap:
                    mapped=[]
                    for vi in ids:
                        vi=int(vi)
                        if vi not in vmap:
                            v=np.zeros(24,np.float32);v[:3]=points[vi];v[3]=a[vi];v[4]=b[vi];v[5]=w[vi];vmap[vi]=len(vertices);vertices.append(v)
                        mapped.append(vmap[vi])
                    tmap[ti]=len(triangles);triangles.append(np.asarray([*mapped,0],np.uint32))
                rows[i,:3]=bc;rows[i,3]=-float(tmap[ti]+1);rows[i,9:12]=0;n+=1
            bound+=n;del tree,points,faces,a,b,w;gc.collect();print('BIND_JOINT26',lid,bid,n,bound,flush=True)
        if cursor!=master['layers'][lid]['sample_offset']+master['layers'][lid]['sample_count']:raise ValueError('Capture range mismatch')
    payloads={'samples.bin':data.astype('<f4').tobytes(),'vertices.bin':np.asarray(vertices,dtype='<f4').tobytes(),'triangles.bin':np.asarray(triangles,dtype='<u4').tobytes()}
    for name,content in payloads.items():
        p=root/(name+'.pending');p.write_bytes(content);p.replace(root/name)
    master['vertex_count']=len(vertices);master['triangle_count']=len(triangles);master['sparse_joint_bindings']=dict(samples=bound,vertices=len(vertices)-8,triangles=len(triangles)-12);master['buffers']={name:dict(bytes=(root/name).stat().st_size,sha256=hashlib.file_digest((root/name).open('rb'),'sha256').hexdigest()) for name in payloads};master['sample_contract']+='; negative binding.w=-(source triangle+1), binding.xyz=barycentric coordinates';(root/'master.json').write_text(json.dumps(master,indent=2)+'\n');print('JOINT_BANK26',master['sparse_joint_bindings'],flush=True)

if __name__=='__main__':main()
