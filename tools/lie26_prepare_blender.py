"""Capture each anatomical segment and actual bent joint surfaces separately.

The 934 original meshes are used offline only. NPZ images contain neutral
gray, normals, depth and source-space XYZ; the runtime consumes their samples.
"""
import argparse,gc,hashlib,json,math,struct,sys
from pathlib import Path
import bpy
import numpy as np
from mathutils import Vector,Quaternion
from mathutils.bvhtree import BVHTree
sys.path.insert(0,str(Path(__file__).resolve().parent))
from lie25_prepare_blender import SOURCE_SHA,LAYERS,PALETTE,save_npz
from lie26_motion import rig,bindings,skeleton_owner,CASES

def qmul(a,b):
    return np.concatenate([a[3]*b[:3]+b[3]*a[:3]+np.cross(a[:3],b[:3]),[a[3]*b[3]-a[:3]@b[:3]]])

def transforms(bones,pose):
    """Independent offline FK, matching the public degree-valued controls."""
    rotations=[];origins=[];dq=[]
    for i,b in enumerate(bones):
        name=b['name'];x=y=z=0
        if name=='pelvis':y=pose.get('root_yaw',0)
        elif name=='torso':x=-pose.get('torso_bend',0);y=pose.get('torso_twist',0)
        elif name=='head':x=-pose.get('head_pitch',0);y=pose.get('head_yaw',0)
        else:
            side=name.split('_')[0];sign=-1 if side=='right' else 1
            if name.endswith('upper_arm'):x=-pose.get(side+'_shoulder',0);z=sign*pose.get(side+'_abduction',0)
            elif name.endswith('forearm'):x=-pose.get(side+'_elbow',0)
            elif name.endswith('hand'):x=-pose.get(side+'_wrist',0)
            elif name.endswith('thigh'):x=-pose.get(side+'_hip',0)
            elif name.endswith('shin'):x=pose.get(side+'_knee',0)
            elif name.endswith('foot'):x=-pose.get(side+'_ankle',0)
        local=Quaternion((0,1,0),math.radians(y))@Quaternion((0,0,1),math.radians(z))@Quaternion((1,0,0),math.radians(x))
        pivot=Vector(b['pivot']);parent=b['parent']
        rotation=local if parent<0 else rotations[parent]@local
        origin=pivot+Vector(pose.get('root_position',[0,0,0])) if parent<0 else origins[parent]+rotations[parent]@(pivot-Vector(bones[parent]['pivot']))
        translation=origin-rotation@pivot
        r=np.asarray([rotation.x,rotation.y,rotation.z,rotation.w]);d=.5*qmul(np.asarray([*translation,0]),r)
        rotations.append(rotation);origins.append(origin);dq.append((r,d))
    return np.asarray(dq)

def deform(points,first,second,weight,dq):
    r0=dq[first,0];r1=dq[second,0];d0=dq[first,1];d1=dq[second,1]
    sign=np.where(np.sum(r0*r1,axis=1)<0,-1,1)[:,None];w=weight[:,None]
    r=r0*(1-w)+r1*sign*w;d=d0*(1-w)+d1*sign*w
    norm=np.linalg.norm(r,axis=1)[:,None];r/=norm;d/=norm
    p=np.asarray(points);q=r[:,:3]
    rotated=p+2*np.cross(q,np.cross(q,p)+r[:,3:4]*p)
    translation=2*(r[:,3:4]*d[:,:3]-d[:,3:4]*q+np.cross(q,d[:,:3]))
    return rotated+translation

def extract(root,bones):
    chunks=[[[] for _ in bones] for _ in LAYERS];counts=[]
    for lid,layer in enumerate(LAYERS):
        names=[];vertex_count=triangle_count=0
        for obj in list(bpy.data.collections[layer].objects):
            if obj.type!='MESH':continue
            mesh=obj.data
            if 'hair' in obj.name or 'eyebrow' in obj.name:
                bpy.data.objects.remove(obj,do_unlink=True)
                if mesh.users==0:bpy.data.meshes.remove(mesh)
                continue
            co=np.empty(len(mesh.vertices)*3,dtype=np.float32);mesh.vertices.foreach_get('co',co);co=co.reshape(-1,3)
            matrix=np.asarray(obj.matrix_world);co=co@matrix[:3,:3].T+matrix[:3,3];co=co[:,[0,2,1]]*np.array([1,1,-1])
            loops=np.empty(len(mesh.loops),dtype=np.int32);mesh.loops.foreach_get('vertex_index',loops)
            starts=np.empty(len(mesh.polygons),dtype=np.int32);mesh.polygons.foreach_get('loop_start',starts)
            totals=np.empty(len(mesh.polygons),dtype=np.int32);mesh.polygons.foreach_get('loop_total',totals)
            faces=np.concatenate([np.stack([loops[starts[totals>k]],loops[starts[totals>k]+k-1],loops[starts[totals>k]+k]],axis=1) for k in range(2,int(totals.max()))])
            first,second,weight,gradient=bindings(co,bones)
            if lid==2:
                owner=np.full(len(co),skeleton_owner(obj.name,co.mean(axis=0),bones));first=owner;second=owner;weight=np.zeros(len(co));gradient=np.zeros_like(co)
            else:owner=np.where(weight<.5,first,second)
            # Stable triangle identities are retained in each offline segment.
            tri_owner=owner[faces[:,0]]
            for bid in np.unique(tri_owner):
                chosen=faces[tri_owner==bid];ids=np.unique(chosen);remap=np.full(len(co),-1,dtype=np.int32);remap[ids]=np.arange(len(ids))
                chunks[lid][bid].append((co[ids].astype(np.float32),remap[chosen],first[ids].astype(np.int32),second[ids].astype(np.int32),weight[ids].astype(np.float32)))
            vertex_count+=len(co);triangle_count+=len(faces);names.append(obj.name)
            bpy.data.objects.remove(obj,do_unlink=True)
            if mesh.users==0:bpy.data.meshes.remove(mesh)
            del co,faces,first,second,weight,gradient,owner;gc.collect()
            print('EXTRACT26',lid,len(names),vertex_count,triangle_count,flush=True)
        counts.append(dict(id=lid,name=layer,source_vertices=vertex_count,source_triangles=triangle_count,source_objects=names))
        for bid,parts in enumerate(chunks[lid]):
            if not parts:continue
            offset=0;fs=[]
            for part in parts:fs.append(part[1]+offset);offset+=len(part[0])
            save_npz(root/f'source-{lid}-{bid}.npz',points=np.concatenate([p[0] for p in parts]),faces=np.concatenate(fs),first=np.concatenate([p[2] for p in parts]),second=np.concatenate([p[3] for p in parts]),weight=np.concatenate([p[4] for p in parts]))
            parts.clear();gc.collect()
    (root/'source-counts.json').write_text(json.dumps(counts,indent=2)+'\n')
    return counts

def bvh(points,faces):
    return BVHTree.FromPolygons(points.tolist(),faces.tolist(),all_triangles=True)

def barycentric(p,a,b,c):
    v0=b-a;v1=c-a;v2=p-a;d00=v0@v0;d01=v0@v1;d11=v1@v1;den=d00*d11-d01*d01
    if abs(den)<1e-20:return np.array([1.,0,0])
    v=(d11*(v2@v0)-d01*(v2@v1))/den;w=(d00*(v2@v1)-d01*(v2@v0))/den
    return np.array([1-v-w,v,w])

def capture(points,faces,bones,lid,bid,root,resolution,pose=None,reuse=False):
    first,second,weight,gradient=bindings(points,bones,lid==2)
    if lid==2:first[:]=bid;second[:]=bid
    posed=deform(points,first,second,weight,transforms(bones,pose or {})) if pose else points
    tree=bvh(points if reuse and pose else posed,faces) if not reuse or pose else None;low=posed.min(axis=0);high=posed.max(axis=0);center=(low+high)/2;scale=float(max(high-low)*1.08)
    rows=[];views=[];elevations=[-35,0,35] if not pose else [-35,0,35]
    azimuths=range(0,360,30) if not pose else range(0,360,60)
    for el in elevations:
        for az in azimuths:
            a,e=math.radians(az),math.radians(el);direction=Vector((math.sin(a)*math.cos(e),math.sin(e),math.cos(a)*math.cos(e)));right=Vector((math.cos(a),0,-math.sin(a)));up=direction.cross(right)
            filename=f'l{lid}-b{bid}-{"bend" if pose else "rest"}-a{az}-e{el}.npz'
            if reuse:
                cached=np.load(root/filename);mask=cached['gray']>0;ps=cached['xyz'][mask];ns=cached['normal'][mask]
                if pose:ns=np.asarray([tree.find_nearest(Vector(p))[1] for p in ps])
                f,s,w,g=bindings(ps,bones,lid==2)
                if lid==2:f[:]=bid;s[:]=bid
                data=np.zeros((len(ps),20),np.float32);data[:,:3]=ps;data[:,3]=f;data[:,4:7]=ns;data[:,7]=float(cached['scale'])/resolution*(.45 if lid==2 else .50);data[:,8]=1;data[:,9:12]=g;data[:,12]=PALETTE[lid][3];data[:,13]=w;data[:,14]=s;data[:,15]=lid;data[:,16:19]=ns;data[:,19]=1
                rows.append(data);views.append(filename);continue
            gray=np.zeros((resolution,resolution),np.float32);normal=np.zeros((resolution,resolution,3),np.float32);depth=np.zeros((resolution,resolution),np.float32);xyz=np.zeros_like(normal)
            hits=[]
            for y in range(resolution):
                for x in range(resolution):
                    origin=Vector(center)+direction*2+right*((x+.5)/resolution-.5)*scale+up*((y+.5)/resolution-.5)*scale
                    p,n,ti,t=tree.ray_cast(origin,-direction,4)
                    if p is None or n.dot(direction)<.025:continue
                    ids=faces[ti];bc=barycentric(np.asarray(p),*posed[ids]);rest=bc@points[ids]
                    rn=np.cross(points[ids[1]]-points[ids[0]],points[ids[2]]-points[ids[0]]);rn/=max(np.linalg.norm(rn),1e-20)
                    gray[y,x]=1;normal[y,x]=n;depth[y,x]=t;xyz[y,x]=rest
                    hits.append((rest,rn))
            if hits:
                ps=np.asarray([p for p,n in hits]);ns=np.asarray([n for p,n in hits]);f,s,w,g=bindings(ps,bones,lid==2)
                if lid==2:f[:]=bid;s[:]=bid
                data=np.zeros((len(hits),20),np.float32);data[:,:3]=ps;data[:,3]=f;data[:,4:7]=ns;data[:,7]=scale/resolution*(.45 if lid==2 else .50);data[:,8]=1;data[:,9:12]=g;data[:,12]=PALETTE[lid][3];data[:,13]=w;data[:,14]=s;data[:,15]=lid;data[:,16:19]=ns;data[:,19]=1
                rows.append(data)
            filename=f'l{lid}-b{bid}-{"bend" if pose else "rest"}-a{az}-e{el}.npz'
            save_npz(root/filename,gray=gray,normal=normal,depth=depth,xyz=xyz,direction=np.asarray(direction),right=np.asarray(right),up=np.asarray(up),center=center,scale=scale,pose=json.dumps(pose or {}))
            views.append(filename)
    del tree;gc.collect()
    return np.concatenate(rows) if rows else np.zeros((0,20),np.float32),views

def references(root,bones):
    size=512;tangent=math.tan(math.radians(35)/2);distance=3.5;target=np.array([0,.82,.09])
    for case in CASES:
        owners=np.full((size,size),-1,np.int32);depths=np.full((size,size),np.inf,np.float32)
        angle=math.radians(case['camera_yaw']);direction=np.array([math.sin(angle),0,math.cos(angle)]);eye=target+direction*distance;right=np.array([math.cos(angle),0,-math.sin(angle)]);up=np.array([0,1,0]);forward=-direction
        # Full source triangles transformed independently, never sample splats.
        for lid in [0,2]:
            if not case['mask']&(1<<lid):continue
            for bid in range(len(bones)):
                path=root/f'source-{lid}-{bid}.npz'
                if not path.exists():continue
                source=np.load(path);posed=deform(source['points'],source['first'],source['second'],source['weight'],transforms(bones,case['pose']));tree=bvh(posed,source['faces'])
                low=posed.min(axis=0);high=posed.max(axis=0);corners=np.array([[x,y,z] for x in [low[0],high[0]] for y in [low[1],high[1]] for z in [low[2],high[2]]])-eye
                z=corners@forward;screen=np.stack([(corners@right/z/tangent+1)*size/2,(1-corners@up/z/tangent)*size/2],axis=1)
                bounds_min=np.maximum(np.floor(screen.min(axis=0)).astype(int)-2,0);bounds_max=np.minimum(np.ceil(screen.max(axis=0)).astype(int)+2,size)
                for y in range(bounds_min[1],bounds_max[1]):
                    for x in range(bounds_min[0],bounds_max[0]):
                        ray=forward+right*((2*(x+.5)/size-1)*tangent)+up*((1-2*(y+.5)/size)*tangent);ray/=np.linalg.norm(ray)
                        p,n,ti,t=tree.ray_cast(Vector(eye),Vector(ray),5)
                        if p is not None:
                            z=np.dot(np.asarray(p)-eye,forward)
                            if z<depths[y,x]:owners[y,x]=lid;depths[y,x]=z
                del tree,source,posed;gc.collect()
        save_npz(root/f'native-{case["name"]}.npz',owners=owners,depth=depths)
        print('NATIVE26',case['name'],flush=True)

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--input',type=Path,required=True);parser.add_argument('--out',type=Path,required=True);parser.add_argument('--resolution',type=int,default=72);parser.add_argument('--reuse-source',action='store_true');parser.add_argument('--reuse-captures',action='store_true');parser.add_argument('--references-only',action='store_true');parser.add_argument('--no-references',action='store_true');options=parser.parse_args(sys.argv[sys.argv.index('--')+1:]);root=options.out;root.mkdir(parents=True,exist_ok=True)
    if not 48<=options.resolution<=128:raise ValueError('Capture resolution 48..128')
    if hashlib.file_digest(options.input.open('rb'),'sha256').hexdigest()!=SOURCE_SHA:raise ValueError('Unknown anatomy source')
    bones=rig()
    if options.reuse_source or options.references_only:counts=json.loads((root/'source-counts.json').read_text())
    else:
        bpy.ops.wm.open_mainfile(filepath=str(options.input.resolve()),load_ui=False,use_scripts=False);counts=extract(root,bones)
    if not options.references_only:
        layers=[];blocks=[];count=0;capture_views=[]
        for lid in range(4):
            start=count
            for bid,b in enumerate(bones):
                path=root/f'source-{lid}-{bid}.npz'
                if not path.exists():continue
                source=np.load(path);resolution=144 if bid==2 else int(options.resolution*1.25) if lid==2 else options.resolution
                rows,views=capture(source['points'],source['faces'],bones,lid,bid,root,resolution,reuse=options.reuse_captures);blocks.append(rows);count+=len(rows);capture_views.append(dict(layer=lid,bone=bid,pose={},resolution=resolution,views=views,samples=len(rows)))
                print('CAPTURE26',lid,bid,count,flush=True)
                del source;gc.collect()
            # Small joint catalog at a bent pose. New source hits map back to
            # rest coordinates, then use the same rig for all runtime angles.
            if lid in [0,1]:
                for child,key,angle in [(2,'head_pitch',25),(3,'right_abduction',60),(6,'left_abduction',60),(4,'right_elbow',100),(7,'left_elbow',100),(9,'right_hip',45),(12,'left_hip',45),(10,'right_knee',70),(13,'left_knee',70)]:
                    parts=[];offset=0
                    for bid in [bones[child]['parent'],child]:
                        source=np.load(root/f'source-{lid}-{bid}.npz');p=source['points'];f=source['faces'];joint=np.asarray(bones[child]['pivot']);selected=np.max(np.linalg.norm(p[f]-joint,axis=2),axis=1)<bones[child]['band']*2.8;f=f[selected]
                        if len(f):ids=np.unique(f);remap=np.full(len(p),-1,np.int32);remap[ids]=np.arange(len(ids));parts.append((p[ids],remap[f]+offset));offset+=len(ids)
                    if not parts:continue
                    pose={key:angle};rows,views=capture(np.concatenate([p[0] for p in parts]),np.concatenate([p[1] for p in parts]),bones,lid,child,root,96,pose,reuse=options.reuse_captures);blocks.append(rows);count+=len(rows);capture_views.append(dict(layer=lid,bone=child,pose=pose,resolution=96,views=views,samples=len(rows)))
                    print('JOINT26',lid,child,count,flush=True)
            layers.append(dict(counts[lid],sample_offset=start,sample_count=count-start))
        if count>6000000:raise ValueError(f'{count} samples exceed 6M memory contract; lower --resolution')
        data=np.concatenate(blocks);(root/'samples.bin').write_bytes(data.astype('<f4').tobytes())
        # Reference envelope remains invisible, not a drawn skin proxy.
        corners=[(x*.37,y*.85+.82,z*.21+.09) for x in [-1,1] for y in [-1,1] for z in [-1,1]];faces=[(0,1,3),(0,3,2),(4,6,7),(4,7,5),(0,4,5),(0,5,1),(2,3,7),(2,7,6),(0,2,6),(0,6,4),(1,5,7),(1,7,3)]
        (root/'vertices.bin').write_bytes(b''.join(struct.pack('<24f',*p,*([0.]*21)) for p in corners));(root/'triangles.bin').write_bytes(b''.join(struct.pack('<4I',*f,0) for f in faces))
        manifest=dict(schema=3,kind='lie-anatomy26-articulated',vertex_stride=96,sample_stride=80,sample_count=count,invocation_count=count,vertex_count=8,triangle_count=12,bone_count=len(bones),bones=bones,layers=layers,capture_views=capture_views,palette=PALETTE,target=[0,.82,.09],source_sha256=SOURCE_SHA,source='https://always3d.gumroad.com/l/haJWL',author='Always3D',license='CC-BY-SA-2.1-JP',license_url='https://creativecommons.org/licenses/by-sa/2.1/jp/',credit='3DAnatomyman by Always3D; derivative of BodyParts3D © DBCLS. Segmented, captured and rigged for Lie.',rig='15-bone authored FK + constrained two-link IK; DQ joints',sample_contract='binding.w=bone0; material.y=weight1; material.z=bone1; gray_filter.yzw=gradient(weight1)',cases=CASES,buffers={name:dict(bytes=(root/name).stat().st_size,sha256=hashlib.file_digest((root/name).open('rb'),'sha256').hexdigest()) for name in ['vertices.bin','triangles.bin','samples.bin']},omissions=['individual fingers','physiological muscle contraction','cloth','ragdoll','cut surfaces','physical GPU performance'])
        (root/'master.json').write_text(json.dumps(manifest,indent=2)+'\n');print('MASTER26',count,flush=True)
    if not options.no_references:references(root,bones)

if __name__=='__main__':main()
