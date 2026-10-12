"""Capture native chin skin for coverage below the orbital head gallery."""
import argparse,hashlib,json,math,sys
from pathlib import Path
import bpy,numpy as np
from mathutils import Vector
from mathutils.bvhtree import BVHTree
sys.path.insert(0,str(Path(__file__).resolve().parent))
from lie27_prepare_blender import geometry,SOURCE_SHA
from lie27_skin_eyes import smooth_normals
from lie27_regions import bindings
from lie26_prepare_blender import barycentric

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--input',type=Path,required=True);parser.add_argument('--root',type=Path,required=True)
    args=parser.parse_args(sys.argv[sys.argv.index('--')+1:]);root=args.root
    if hashlib.file_digest(args.input.open('rb'),'sha256').hexdigest()!=SOURCE_SHA:raise ValueError('Unknown source')
    m=json.loads((root/'master.json').read_text())
    if m.get('chin_contract'):raise ValueError('Chin gallery already installed')
    for name,item in m['buffers'].items():
        if hashlib.file_digest((root/name).open('rb'),'sha256').hexdigest()!=item['sha256']:raise ValueError('Invalid bank buffer')
    bpy.ops.wm.open_mainfile(filepath=str(args.input.resolve()),load_ui=False,use_scripts=False)
    p,f=geometry(bpy.data.objects['skin']);normals=smooth_normals(p,f)
    tree=BVHTree.FromPolygons(p.tolist(),f.tolist(),all_triangles=True)
    size=80;scale=.16;target=Vector((0,1.435,.15));rows=[];views=[]
    for azimuth in [-35,0,35]:
        a=math.radians(azimuth);direction=Vector((math.sin(a),0,math.cos(a)));right=Vector((math.cos(a),0,-math.sin(a)));up=Vector((0,1,0))
        xyz=np.full((size,size,3),np.nan,np.float32);normal=np.full_like(xyz,np.nan);depth=np.full((size,size),np.nan,np.float32);count=0
        for y in range(size):
            for x in range(size):
                origin=target+direction*.35+right*((x+.5)/size-.5)*scale+up*((y+.5)/size-.5)*scale
                hit,gn,ti,distance=tree.ray_cast(origin,-direction,.7)
                if hit is None:continue
                point=np.asarray(hit)
                if not (1.418<point[1]<1.452 and abs(point[0])<.07 and point[2]>.13):continue
                ids=f[ti];sn=barycentric(point,*p[ids])@normals[ids];sn/=np.linalg.norm(sn)
                gn=np.asarray(gn);gn/=np.linalg.norm(gn)
                row=np.zeros(20,np.float32);row[:3]=point;row[4:7]=sn;row[7]=scale/size*.72
                row[8]=1;row[12]=.55;row[15]=0;row[16:19]=gn;row[19]=1;rows.append(row)
                xyz[y,x]=point;normal[y,x]=sn;depth[y,x]=distance;count+=1
        name=f'native-chin-a{azimuth:+03d}.npz';np.savez_compressed(root/name,rest_xyz=xyz,normal=normal,depth=depth)
        views.append(dict(file=name,resolution=size,azimuth=azimuth,samples=count,sha256=hashlib.sha256((root/name).read_bytes()).hexdigest()))
        print('CHIN_CAPTURE27',azimuth,count,flush=True)
    extra=np.asarray(rows,np.float32);a,b,w,g=bindings(extra[:,:3],m['bones']);extra[:,3]=a;extra[:,14]=b;extra[:,13]=w;extra[:,9:12]=g
    if m['sample_count']+len(extra)>6000000:raise ValueError('Chin capture exceeds accumulation sample contract')
    skin_count=m['layers'][0]['sample_count'];data=np.fromfile(root/'samples.bin',dtype='<f4').reshape(-1,20)
    data=np.concatenate([data[:skin_count],extra,data[skin_count:]])
    temporary=root/'samples.bin.tmp';data.astype('<f4').tofile(temporary)
    assert temporary.stat().st_size==len(data)*80;temporary.replace(root/'samples.bin')
    for name,keys in [('eyeball-sample-indices.json',['left','right']),('region-probes.json',['indices'])]:
        path=root/name;ref=json.loads(path.read_text())
        for key in keys:ref[key]=[index+len(extra) if index>=skin_count else index for index in ref[key]]
        path.write_text(json.dumps(ref,indent=2)+'\n')
    m['layers'][0]['sample_count']+=len(extra)
    for layer in m['layers'][1:]:layer['sample_offset']+=len(extra)
    m['sample_count']=len(data);m['invocation_count']=len(data)
    m['buffers']['samples.bin'].update(bytes=len(data)*80,sha256=hashlib.file_digest((root/'samples.bin').open('rb'),'sha256').hexdigest())
    m.update(chin_contract='native-chin-capture-v1',chin_sample_offset=skin_count,chin_sample_count=len(extra),chin_galleries=views)
    np.column_stack([data[:,15],data[:,19]]).astype('u1').tofile(root/'sample-material-reference.bin')
    (root/'master.json').write_text(json.dumps(m,indent=2)+'\n')
    print('CHIN_BANK27',len(data),'samples',len(extra),'new skin captures',flush=True)

if __name__=='__main__':main()
