"""Independent native-skin ray ownership masks around the chin."""
import argparse,hashlib,json,math,sys
from pathlib import Path
import bpy,numpy as np
from mathutils import Vector
from mathutils.bvhtree import BVHTree
sys.path.insert(0,str(Path(__file__).resolve().parent))
from lie27_prepare_blender import geometry,SOURCE_SHA
from lie27_reference import fk
from lie27_regions import deform_face,FACIAL_KEYS
from lie26_prepare_blender import barycentric

CASES=[dict(name='neutral',pose={},face={}),dict(name='jaw_open',pose={},face={'jaw_open':1}),
       dict(name='head_turn',pose={'head_yaw':25,'head_pitch':15},face={}),
       dict(name='orbit_left',pose={},face={},camera_yaw=-35),dict(name='orbit_right',pose={},face={},camera_yaw=35)]

def world(p,m,case):
    dq,_,_=fk(m['bones'],case['pose'])
    t=np.clip((p[:,1]-1.36)/.08,0,1);w=t*t*(3-2*t)
    a=dq[1];b=dq[2].copy()
    if a[0]@b[0]<0:b=-b
    r=a[0]*(1-w[:,None])+b[0]*w[:,None];d=a[1]*(1-w[:,None])+b[1]*w[:,None]
    length=np.linalg.norm(r,axis=1)[:,None];r/=length;d/=length
    translation=2*(-d[:,3,None]*r[:,:3]+r[:,3,None]*d[:,:3]-np.cross(d[:,:3],r[:,:3]))
    posed=deform_face(p,m['facial_regions'],[case['face'].get(key,0) for key in FACIAL_KEYS])[0]
    return posed+2*np.cross(r[:,:3],np.cross(r[:,:3],posed)+r[:,3,None]*posed)+translation

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--input',type=Path,required=True);parser.add_argument('--root',type=Path,required=True)
    args=parser.parse_args(sys.argv[sys.argv.index('--')+1:]);root=args.root
    if hashlib.file_digest(args.input.open('rb'),'sha256').hexdigest()!=SOURCE_SHA:raise ValueError('Unknown source')
    bpy.ops.wm.open_mainfile(filepath=str(args.input.resolve()),load_ui=False,use_scripts=False)
    p,f=geometry(bpy.data.objects['skin']);f=f[np.any(p[f,1]>1.40,axis=1)]
    m=json.loads((root/'master.json').read_text());size=1024;tangent=math.tan(math.radians(35)*.5);cases=[]
    for case in CASES:
        points=world(p,m,case);tree=BVHTree.FromPolygons(points.tolist(),f.tolist(),all_triangles=True)
        angle=math.radians(case.get('camera_yaw',0));direction=np.array([math.sin(angle),0,math.cos(angle)]);right=np.array([math.cos(angle),0,-math.sin(angle)]);up=np.array([0,1,0]);forward=-direction;eye=np.array([0,1.525,.16])+direction*.35
        region=(p[:,1]>1.423)&(p[:,1]<1.448)&(abs(p[:,0])<.060)&(p[:,2]>.135)
        corners=points[region];delta=corners-eye;depth=delta@forward
        xy=np.column_stack([(delta@right/depth/tangent+1)*.5,(1-delta@up/depth/tangent)*.5])*size
        low=np.maximum(np.floor(xy.min(0)).astype(int)-3,0);high=np.minimum(np.ceil(xy.max(0)).astype(int)+3,size-1)
        mask=np.zeros((size,size),np.uint8)
        for y in range(low[1],high[1]+1):
            for x in range(low[0],high[0]+1):
                ray=forward+right*((2*(x+.5)/size-1)*tangent)+up*((1-2*(y+.5)/size)*tangent);ray/=np.linalg.norm(ray)
                hit,n,ti,distance=tree.ray_cast(Vector(eye),Vector(ray),2)
                if hit is None:continue
                ids=f[ti];point=barycentric(np.asarray(hit),*points[ids])@p[ids]
                if 1.423<point[1]<1.448 and abs(point[0])<.060 and point[2]>.135:mask[y,x]=1
        clean=mask.astype(bool)
        for dy in range(-2,3):
            for dx in range(-2,3):clean&=np.roll(np.roll(mask,dy,0),dx,1)>0
        name='jaw-coverage-'+case['name']+'.bin';(root/name).write_bytes(clean.astype('u1').tobytes())
        cases.append(dict(case,file=name,protected_pixels=int(clean.sum())))
        print('JAW_REFERENCE27',case['name'],int(clean.sum()),flush=True)
    (root/'jaw-coverage-reference.json').write_text(json.dumps(dict(source_sha256=SOURCE_SHA,internal_size=size,boundary_margin_pixels=2,cases=cases),indent=2)+'\n')

if __name__=='__main__':main()
