"""Independent source-triangle ray masks for intact orbital skin and eyes.

Run with Blender. The union excludes a two-pixel boundary; a 16-pixel
skin/eye footprint band accepts only those two native surfaces. Lower tissues
remain enabled in the GPU test; disabling skin separately exposes them.
"""
import argparse,json,math,sys
from pathlib import Path
import numpy as np
from mathutils import Vector
from mathutils.bvhtree import BVHTree
sys.path.insert(0,str(Path(__file__).resolve().parent))
from lie27_reference import fk,rotate,CASES
from lie27_regions import deform_face,FACIAL_KEYS

CASES_EXTRA=[dict(name='half_closed',pose={},face={'blink_left':.5,'blink_right':.5}),
             dict(name='orbit_right',pose={},face={},camera_yaw=35),
             dict(name='orbit_right_closed',pose={},face={'blink_left':1,'blink_right':1},camera_yaw=35),
             dict(name='orbit_left',pose={},face={},camera_yaw=-35),
             dict(name='orbit_left_closed',pose={},face={'blink_left':1,'blink_right':1},camera_yaw=-35)]

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--root',type=Path,required=True);args=parser.parse_args(sys.argv[sys.argv.index('--')+1:]);root=args.root
    m=json.loads((root/'master.json').read_text());r=np.load(root/'orbital-source-reference.npz');size=1024;tangent=math.tan(math.radians(35)*.5);cases=[]
    for case in [c for c in CASES if c['name']!='fist']+CASES_EXTRA:
        dq,origins,qs=fk(m['bones'],case['pose']);q=qs[2];translation=origins[2]-rotate(q,np.asarray(m['bones'][2]['pivot']))
        values=[case['face'].get(key,0) for key in FACIAL_KEYS]
        def world(p,soft=True):
            if soft:p=deform_face(p,m['facial_regions'],values)[0]
            return rotate(q,p)+translation
        points=world(r['points']);faces=r['faces'].copy();rest=r['points'].copy()
        for index in range(2):
            v=r[f'rest{index}'];blink=values[0 if m['eyes'][index][0]>0 else 1]
            posed=v+(r[f'closed{index}']-v)*blink+(r[f'middle{index}']-(v+r[f'closed{index}'])*.5)*4*blink*(1-blink)
            faces=np.concatenate([faces,r[f'faces{index}']+len(points)]);points=np.concatenate([points,world(posed)]);rest=np.concatenate([rest,v])
        tree=BVHTree.FromPolygons(points.tolist(),faces.tolist(),all_triangles=True)
        ep=world(r['eye_points'],False);eye_tree=BVHTree.FromPolygons(ep.tolist(),r['eye_faces'].tolist(),all_triangles=True)
        angle=math.radians(case.get('camera_yaw',0));direction=np.array([math.sin(angle),0,math.cos(angle)]);right=np.array([math.cos(angle),0,-math.sin(angle)]);up=np.array([0,1,0]);forward=-direction;eye=np.array([0,1.525,.16])+direction*.35
        boxes=[]
        for center in m['eyes']:
            c=np.asarray(center);corners=world(np.array([c+[x,y,z] for x in [-.035,.035] for y in [-.032,.032] for z in [-.008,.055]]),False)
            d=corners-eye;z=d@forward;xy=np.column_stack([(d@right/z/tangent+1)*.5,(1-d@up/z/tangent)*.5])*size
            lo=np.maximum(np.floor(xy.min(0)).astype(int),0);hi=np.minimum(np.ceil(xy.max(0)).astype(int),size-1);boxes.append((lo,hi))
        mask=np.zeros((size,size),np.uint8);visited=np.zeros_like(mask,bool)
        for lo,hi in boxes:
            for y in range(lo[1],hi[1]+1):
                for x in range(lo[0],hi[0]+1):
                    if visited[y,x]:continue
                    visited[y,x]=True;ray=forward+right*((2*(x+.5)/size-1)*tangent)+up*((1-2*(y+.5)/size)*tangent);ray/=np.linalg.norm(ray)
                    hit,n,ti,dist=tree.ray_cast(Vector(eye),Vector(ray),2)
                    eh,en,et,ed=eye_tree.ray_cast(Vector(eye),Vector(ray),2)
                    if hit is None and eh is None:continue
                    if eh is not None and (hit is None or ed<dist):point=rotate(np.r_[-q[:3],q[3]],np.asarray(eh)-translation);kind=2
                    else:
                        ids=faces[ti];a,b,c=points[ids];u=b-a;v=c-a;h=np.asarray(hit)-a;uv=u@v;den=(u@u)*(v@v)-uv*uv
                        b1=((v@v)*(h@u)-uv*(h@v))/den;b2=((u@u)*(h@v)-uv*(h@u))/den;point=rest[ids[0]]*(1-b1-b2)+rest[ids[1]]*b1+rest[ids[2]]*b2;kind=1
                    protected=min(((point[0]-c[0])/.028)**2+((point[1]-c[1])/.026)**2 for c in m['eyes'])<1
                    if protected and point[2]>.13:mask[y,x]=kind
        # Pixel footprints may straddle a genuine eye/skin boundary. Keep only
        # the interior of each independently ray-classified material region.
        clean=mask.copy();union=mask>0
        for dy in range(-2,3):
            for dx in range(-2,3):union&=np.roll(np.roll(mask>0,dy,0),dx,1)
        # A native head sample has a 1.125 mm radius, transported by the
        # facial Jacobian. At this zoom its maximum projected footprint is
        # conservatively bounded by 16 pixels. Material labels can straddle
        # that genuine skin/eye boundary; the union still forbids any inner
        # tissue or missing surface at EVERY protected pixel.
        for dy in range(-16,17):
            for dx in range(-16,17):clean[np.roll(np.roll(mask,dy,0),dx,1)!=mask]=0
        clean[union&(clean==0)]=3;clean[~union]=0
        name='coverage-'+case['name']+'.bin';(root/name).write_bytes(clean.tobytes())
        cases.append(dict(case,file=name,skin_pixels=int((clean==1).sum()),eye_pixels=int((clean==2).sum())))
        print('COVERAGE_REFERENCE27',case['name'],cases[-1]['skin_pixels'],cases[-1]['eye_pixels'],flush=True)
    (root/'coverage-reference.json').write_text(json.dumps(dict(internal_size=size,boundary_margin_pixels=2,material_boundary_margin_pixels=16,boundary_materials=['skin','native_eyeball'],cases=cases),indent=2)+'\n')

if __name__=='__main__':main()
