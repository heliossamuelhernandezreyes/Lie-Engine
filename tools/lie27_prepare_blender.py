"""Reuse LIE-26 captures; author finger pivots and connected orbital galleries.

Run Blender with --disable-autoexec. No network or checkout details are used.
The new orbital patch shares its native skin boundary. Its closed/midpoint
keys follow the source eyeball; samples from all three poses share references.
"""
import argparse,hashlib,json,math,sys,gc
from pathlib import Path
import bpy,numpy as np
from mathutils import Vector
from mathutils.bvhtree import BVHTree
sys.path.insert(0,str(Path(__file__).resolve().parent))
from lie25_prepare_blender import SOURCE_SHA
from lie26_motion import rig
from lie26_prepare_blender import barycentric
from lie27_regions import bindings,joint_regions,facial_regions

def geometry(obj):
    mesh=obj.data;co=np.empty(len(mesh.vertices)*3,np.float32);mesh.vertices.foreach_get('co',co);co=co.reshape(-1,3)
    mat=np.asarray(obj.matrix_world);co=co@mat[:3,:3].T+mat[:3,3];co=co[:,[0,2,1]]*np.array([1,1,-1])
    mesh.calc_loop_triangles();faces=np.empty(len(mesh.loop_triangles)*3,np.int32);mesh.loop_triangles.foreach_get('vertices',faces)
    return co,faces.reshape(-1,3)

def endpoints(p):
    center=p.mean(0);v=np.linalg.eigh((p-center).T@(p-center))[1][:,-1]
    if v[1]>0:v=-v
    t=(p-center)@v
    return center+v*t.min(),center+v*t.max()

def finger_rig(objects):
    bones=rig();names=['thumb','index','middle','ring','little']
    for side,hand in [('right',5),('left',8)]:
        roots=[]
        for digit in names:
            source_names=[f'{part} phalanx of {side} {digit}'+('' if digit=='thumb' else ' finger') for part in ['proximal','middle','distal']]
            if digit=='thumb':source_names=[f'{side} first metacarpal bone',f'proximal phalanx of {side} thumb',f'distal phalanx of {side} thumb']
            ends=[endpoints(geometry(objects[name])[0]) for name in source_names]
            pivots=[ends[0][0]]+[(ends[k-1][1]+ends[k][0])*.5 for k in [1,2]]
            roots.append(pivots[0]);parent=hand
            for k in range(3):
                bid=len(bones);end=pivots[k+1] if k<2 else ends[k][1]
                bones.append(dict(id=bid,name=f'{side}_{digit}_{k}',parent=parent,pivot=pivots[k].tolist(),end=end.tolist(),radius=.0065 if k else .0085,band=.010,control=f'{side}_{digit}',axis=[-1,0,0],gain=[.75,1,.65][k]))
                parent=bid
        bones[hand]['end']=np.mean(roots[1:],axis=0).tolist();bones[hand]['radius']=.025
    return bones

def orbital_patches(points,faces,eyes,width=.026,height=.024):
    from collections import Counter,defaultdict
    keep=faces.copy();patches=[]
    for eye in eyes:
        center=points[keep].mean(1)
        cut=((center[:,0]-eye[0])/width)**2+((center[:,1]-eye[1])/height)**2<1
        cut&=center[:,2]>.125
        removed=keep[cut];keep=keep[~cut]
        # Include incident fans if the native cut touches itself at a vertex.
        for _ in range(30):
            edges=Counter(tuple(sorted((int(t[k]),int(t[(k+1)%3])))) for t in removed for k in range(3))
            neighbors=defaultdict(list)
            for (a,b),count in edges.items():
                if count==1:neighbors[a].append(b);neighbors[b].append(a)
            pinch={k for k,v in neighbors.items() if len(v)!=2}
            if not pinch:break
            extra=np.array([any(int(k) in pinch for k in t) for t in keep])
            removed=np.concatenate([removed,keep[extra]]);keep=keep[~extra]
        if any(len(v)!=2 for v in neighbors.values()):raise ValueError('Non-simple orbital boundary')
        unused=set(neighbors);loops=[]
        while unused:
            start=min(unused);loop=[start];old=None;current=start
            while True:
                nxt=next(k for k in neighbors[current] if k!=old)
                if nxt==start:break
                loop.append(nxt);old,current=current,nxt
            unused.difference_update(loop);loops.append(loop)
        def winding(loop):
            d=points[loop,:2]-eye[:2];e=np.roll(d,-1,axis=0)
            return np.arctan2(d[:,0]*e[:,1]-d[:,1]*e[:,0],np.sum(d*e,axis=1)).sum()/math.tau
        enclosing=[loop for loop in loops if abs(winding(loop))>.9]
        if not enclosing:raise ValueError('Orbital rim does not surround the native eyeball')
        loop=max(enclosing,key=len);outer=points[loop];theta=np.arctan2((outer[:,1]-eye[1])/height,(outer[:,0]-eye[0])/width)
        area=np.sum(outer[:,0]*np.roll(outer[:,1],-1)-np.roll(outer[:,0],-1)*outer[:,1])
        if area<0:outer=outer[::-1];theta=theta[::-1]
        rest=[];closed=[];middle=[];n=len(outer);rings=7;radius=.0172
        def target(angle,blink):
            x=eye[0]+.0152*np.cos(angle)
            # Independently sampled upper/lower rims approximate a curved
            # seam with different segments. Give their captured tissue a
            # 0.2 mm contact overlap at closure, avoiding geometric cracks.
            y=eye[1]+(.0060*(1-blink)-.0002*blink)*np.sin(angle)
            z=eye[2]+np.sqrt(np.maximum(radius**2-(x-eye[0])**2-(y-eye[1])**2,1e-7))+.0007
            return np.stack([x,y,z],axis=1)
        for j in range(rings):
            u=j/(rings-1)
            for value,blink in [(rest,0),(middle,.5),(closed,1)]:
                inner=target(theta,blink);p=outer*(1-u)+inner*u
                sphere=eye[2]+np.sqrt(np.maximum(radius**2-(p[:,0]-eye[0])**2-(p[:,1]-eye[1])**2,0))+.0007
                # Interpolating the shell depth with the boundary penetrates
                # the globe between rings. Preserve the exact native rim, but
                # keep every interior ring on or in front of the ocular shell.
                if j>0:p[:,2]=np.maximum(p[:,2],sphere)
                value.extend(p)
        fs=[]
        for j in range(rings-1):
            for i in range(n):
                a=j*n+i;b=j*n+(i+1)%n;c=(j+1)*n+i;d=(j+1)*n+(i+1)%n
                fs.extend([(a,b,c),(b,d,c)])
        patches.append(dict(rest=np.asarray(rest),closed=np.asarray(closed),middle=np.asarray(middle),faces=np.asarray(fs,np.int32),boundary=outer,eye=eye))
    return keep,patches

def capture_patch(patch,vertex_offset,tri_offset,root,side,scale=.075,resolution=96):
    rest=patch['rest'];faces=patch['faces'];eye=patch['eye'];rows=[];counts=[]
    for blink in [0,.5,1]:
        posed=rest+(patch['closed']-rest)*blink+(patch['middle']-(rest+patch['closed'])*.5)*(4*blink*(1-blink))
        tree=BVHTree.FromPolygons(posed.tolist(),faces.tolist(),all_triangles=True)
        inverse_cov=[]
        for ids in faces:
            a,b,c=rest[ids];pa,pb,pc=posed[ids];rn=np.cross(b-a,c-a);rn/=np.linalg.norm(rn)
            pn=np.cross(pb-pa,pc-pa);pn/=max(np.linalg.norm(pn),1e-15)
            tangent=np.cross(rn,[0,1,0] if abs(rn[1])<.9 else [1,0,0]);tangent/=np.linalg.norm(tangent);basis=np.column_stack([tangent,np.cross(rn,tangent)])
            pt=pb-pa;pt/=max(np.linalg.norm(pt),1e-15);posed_basis=np.column_stack([pt,np.cross(pn,pt)])
            jac=np.column_stack([pb-pa,pc-pa,pn])@np.linalg.inv(np.column_stack([b-a,c-a,rn]))
            matrix=posed_basis.T@jac@basis;inverse=np.linalg.pinv(matrix,rcond=1e-8);inverse_cov.append(inverse@inverse.T)
        for az in [-45,0,45]:
            angle=math.radians(az);direction=Vector((math.sin(angle),0,math.cos(angle)));right=Vector((math.cos(angle),0,-math.sin(angle)));up=Vector((0,1,0));count=0
            gray=np.full((resolution,resolution),np.nan,np.float32);normals=np.full((resolution,resolution,3),np.nan,np.float32)
            depth=np.full((resolution,resolution),np.nan,np.float32);xyz=np.full((resolution,resolution,3),np.nan,np.float32)
            triangle=np.full((resolution,resolution),-1,np.int32);bary=np.full((resolution,resolution,3),np.nan,np.float32)
            for y in range(resolution):
                for x in range(resolution):
                    origin=Vector(eye)+direction*.3+right*((x+.5)/resolution-.5)*scale+up*((y+.5)/resolution-.5)*scale
                    hit,normal,ti,distance=tree.ray_cast(origin,-direction,.6)
                    if hit is None:continue
                    ids=faces[ti];bc=barycentric(np.asarray(hit),*posed[ids]);rn=np.cross(rest[ids[1]]-rest[ids[0]],rest[ids[2]]-rest[ids[0]])
                    if np.linalg.norm(rn)<1e-12:continue
                    rn/=np.linalg.norm(rn)
                    gray[y,x]=1;normals[y,x]=rn;depth[y,x]=distance;xyz[y,x]=bc@rest[ids];triangle[y,x]=tri_offset+ti;bary[y,x]=bc
                    row=np.zeros(20,np.float32);row[:3]=bc;row[3]=-(tri_offset+ti+1);row[4:7]=rn;row[7]=scale/resolution*.68;row[8]=1;row[12]=.55;row[14]=2;row[15]=0;row[16:19]=rn;row[19]=1;rows.append(row);count+=1
                    # Captured pixel footprints live in the POSED tangent
                    # plane. Undo that Jacobian before storing rest-space
                    # covariance; applying a pose twice shrinks corner disks.
                    posed_normal=np.asarray(normal);cov=inverse_cov[ti]*(row[7]/max(abs(posed_normal@np.asarray(direction)),.3))**2
                    row[9:12]=[cov[0,0],cov[0,1],cov[1,1]]
            name=f'orbital-{side}-{int(blink*100):03d}-{az:+03d}.npz'
            np.savez_compressed(root/name,gray=gray,normal=normals,depth=depth,rest_xyz=xyz,triangle=triangle,barycentric=bary)
            counts.append(dict(blink=blink,azimuth=az,resolution=resolution,samples=count,file=name,sha256=hashlib.sha256((root/name).read_bytes()).hexdigest()))
        # Subpixel triangles can be missed by every fixed image grid. Capture
        # a local normal ray for each valid face, with a conservative disk
        # clipped to that triangle at runtime. This preserves small corners.
        count=0
        for ti,ids in enumerate(faces):
            a,b,c=posed[ids];pn=np.cross(b-a,c-a);area=np.linalg.norm(pn)
            if area<1e-12:continue
            pn/=area;center=(a+b+c)/3
            hit,normal,hit_ti,distance=tree.ray_cast(Vector(center+pn*.000002),Vector(-pn),.000004)
            if hit is None or hit_ti!=ti:continue
            rn=np.cross(rest[ids[1]]-rest[ids[0]],rest[ids[2]]-rest[ids[0]]);length=np.linalg.norm(rn)
            if length<1e-12:continue
            rn/=length;bc=barycentric(np.asarray(hit),*posed[ids]);radius=np.linalg.norm(posed[ids]-center,axis=1).max()+scale/resolution*.5
            cov=inverse_cov[ti]*radius**2;row=np.zeros(20,np.float32);row[:3]=bc;row[3]=-(tri_offset+ti+1);row[4:7]=rn;row[7]=radius;row[8]=1;row[9:12]=[cov[0,0],cov[0,1],cov[1,1]];row[12]=.55;row[14]=2;row[16:19]=rn;row[19]=1;rows.append(row);count+=1
        counts.append(dict(blink=blink,method='adaptive-native-triangle-normal-ray',samples=count))
        del tree
    return np.asarray(rows,np.float32),counts

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--input',type=Path,required=True);parser.add_argument('--base',type=Path,required=True);parser.add_argument('--out',type=Path,required=True)
    args=parser.parse_args(sys.argv[sys.argv.index('--')+1:]);root=args.out;root.mkdir(parents=True,exist_ok=True)
    if hashlib.file_digest(args.input.open('rb'),'sha256').hexdigest()!=SOURCE_SHA:raise ValueError('Unknown source')
    bpy.ops.wm.open_mainfile(filepath=str(args.input.resolve()),load_ui=False,use_scripts=False)
    objects={o.name:o for o in bpy.data.objects if o.type=='MESH'};bones=finger_rig(objects)
    eye_points,_=geometry(objects['eyeball']);eyes=[]
    for sign in [-1,1]:
        p=eye_points[eye_points[:,0]*sign>0];eyes.append((p.min(0)+p.max(0))*.5)
    skin,skin_faces=geometry(objects['skin']);head_faces=skin_faces[np.all(skin[skin_faces,1]>1.44,axis=1)]
    native_keep,patches=orbital_patches(skin,head_faces,eyes)
    master=json.loads((args.base/'master.json').read_text());data=np.fromfile(args.base/'samples.bin',dtype='<f4').reshape(-1,20)
    vertices=np.fromfile(args.base/'vertices.bin',dtype='<f4').reshape(-1,24);triangles=np.fromfile(args.base/'triangles.bin',dtype='<u4').reshape(-1,4)
    a,b,w,g=bindings(vertices[:,:3],bones);vertices[:,3]=a;vertices[:,4]=b;vertices[:,5]=w
    # Preserve exact rigid skeleton interiors; split its former hand owners
    # among the authored phalanges using their source-space volumes.
    for layer in master['layers']:
        start=layer['sample_offset'];end=start+layer['sample_count'];lid=layer['id']
        for begin in range(start,end,100000):
            rows=data[begin:min(begin+100000,end)];direct=rows[:,3]>=0
            if lid==2:
                hand=direct&np.isin(rows[:,3],[5,8]);a,b,w,g=bindings(rows[hand,:3],bones,True)
                # Carpals remain owned by the hand; only native digit interiors
                # acquire a phalanx owner. A nearby forearm must not steal them.
                a=np.where(a>=15,a,rows[hand,3]);rows[hand,3]=a;rows[hand,14]=a
            else:
                a,b,w,g=bindings(rows[direct,:3],bones);rows[direct,3]=a;rows[direct,14]=b;rows[direct,13]=w;rows[direct,9:12]=g
        print('SPHERE_REBIND27',lid,flush=True)
    skin_layer=master['layers'][0];original_skin=data[:skin_layer['sample_count']];keep=np.ones(len(original_skin),bool)
    for eye in eyes:
        p=original_skin[:,:3];cut=((p[:,0]-eye[0])/.026)**2+((p[:,1]-eye[1])/.024)**2<1
        keep&=~(cut&(p[:,2]>.125)&(original_skin[:,3]>=0))
    extra=[];captures=[];boundaries=[]
    for index,patch in enumerate(patches):
        start_v=len(vertices);start_t=len(triangles);v=np.zeros((len(patch['rest']),24),np.float32);v[:,:3]=patch['rest'];v[:,3]=2;v[:,4]=2
        v[:,8:11]=patch['closed']-patch['rest'];v[:,11]=1 if eyes[index][0]>0 else 0
        v[:,12:15]=patch['middle']-(patch['rest']+patch['closed'])*.5;v[:,15]=1
        vertices=np.concatenate([vertices,v]);triangles=np.concatenate([triangles,np.column_stack([patch['faces']+start_v,np.zeros(len(patch['faces']),np.int32)])])
        side='left' if eyes[index][0]>0 else 'right'
        rows,views=capture_patch(patch,start_v,start_t,root,side);extra.append(rows);captures.append(dict(side=side,vertex_offset=start_v,vertex_count=len(v),triangle_offset=start_t,triangle_count=len(patch['faces']),views=views))
        boundaries.append(dict(side=captures[-1]['side'],points=patch['boundary'].tolist(),max_rest_error_m=0))
        print('ORBITAL_CAPTURE27',captures[-1]['side'],len(v),len(rows),flush=True)
    added=sum(len(a) for a in extra);old_end=skin_layer['sample_count'];data=np.concatenate([original_skin[keep],*extra,data[old_end:]])
    shift=int(keep.sum())+added-old_end;skin_layer['sample_count']+=shift
    for l in master['layers'][1:]:l['sample_offset']+=shift
    if len(data)>6000000:raise ValueError(f'{len(data)} exceeds existing accumulation budget')
    if 'capture_views' in master:master['base_capture_catalog']=master.pop('capture_views')
    if 'cases' in master:master['base_reference_cases']=master.pop('cases')
    master['capture_catalog_note']='Base catalog records LIE-26 provenance; orbital filtering and rebinding change its old sample ranges. Only layers contain current contiguous sample ranges.'
    master['rig']='45-bone authored FK + constrained body two-link IK; compact spherical DQ joints; 30 digit segments'
    master['orbital_footprint_scale']=.68
    master['sparse_joint_bindings'].pop('probe_samples',None)
    master.update(kind='lie-anatomy27-regions',bones=bones,bone_count=len(bones),sample_count=len(data),invocation_count=len(data),vertex_count=len(vertices),triangle_count=len(triangles),joint_regions=joint_regions(bones),facial_regions=facial_regions([e.tolist() for e in eyes]),eyes=[e.tolist() for e in eyes],orbital_galleries=captures,orbital_boundaries=boundaries,region_contract='compact-sphere-cubic-v1',blink_contract='connected-orbit-closed-mid-v1',base_sample_sha256=master['buffers']['samples.bin']['sha256'])
    payloads={'samples.bin':data.astype('<f4').tobytes(),'vertices.bin':vertices.astype('<f4').tobytes(),'triangles.bin':triangles.astype('<u4').tobytes()}
    for name,content in payloads.items():(root/name).write_bytes(content)
    master['buffers']={name:dict(bytes=len(content),sha256=hashlib.sha256(content).hexdigest()) for name,content in payloads.items()}
    master['omissions']=['physiological muscle contraction','cloth','ragdoll','cut surfaces','physical GPU performance','tongue and detailed oral cavity','artist-authored corrective finger poses']
    (root/'master.json').write_text(json.dumps(master,indent=2)+'\n')
    np.savez_compressed(root/'orbital-source-reference.npz',points=skin,faces=native_keep,**{f'{key}{i}':p[key] for i,p in enumerate(patches) for key in ['rest','closed','middle','faces']})
    print('MASTER27',len(data),'samples',len(bones),'bones',len(vertices),'vertices',len(triangles),'triangles',flush=True)

if __name__=='__main__':main()
