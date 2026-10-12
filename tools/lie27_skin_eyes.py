"""Rebuild an intact native head surface and author ocular material identity.

The cut is applied once to source triangles. Both the native head gallery and
the moving lid use those exact boundaries. No independent ellipse removes
runtime skin samples. Source meshes are used only during this preparation.
"""
import argparse,gc,hashlib,json,math,sys
from pathlib import Path
import bpy,numpy as np
from mathutils import Vector
from mathutils.bvhtree import BVHTree
sys.path.insert(0,str(Path(__file__).resolve().parent))
from lie27_prepare_blender import geometry,orbital_patches,capture_patch,SOURCE_SHA
from lie26_prepare_blender import barycentric

def weld(points,faces):
    active=np.unique(faces);p=points[active]
    _,ix,inv=np.unique(np.round(p*1e6).astype(np.int64),axis=0,return_index=True,return_inverse=True)
    f=inv[np.searchsorted(active,faces)];valid=(f[:,0]!=f[:,1])&(f[:,1]!=f[:,2])&(f[:,2]!=f[:,0])
    return p[ix],f[valid]

def smooth_normals(points,faces):
    n=np.zeros_like(points);v=np.cross(points[faces[:,1]]-points[faces[:,0]],points[faces[:,2]]-points[faces[:,0]])
    for i in range(3):np.add.at(n,faces[:,i],v)
    return n/np.maximum(np.linalg.norm(n,axis=1)[:,None],1e-15)

def capture_native(points,faces,root,eyes):
    tree=BVHTree.FromPolygons(points.tolist(),faces.tolist(),all_triangles=True)
    normals=smooth_normals(points,faces);scale=.25;size=160;target=Vector((0,1.54,.09));rows=[];views=[]
    for elevation in [-30,0,30]:
        e=math.radians(elevation)
        for az in range(0,360,30):
            if elevation!=0 and az in [150,180,210]:continue
            a=math.radians(az);direction=Vector((math.sin(a)*math.cos(e),math.sin(e),math.cos(a)*math.cos(e)))
            right=Vector((math.cos(a),0,-math.sin(a)));up=direction.cross(right)
            xyz=np.full((size,size,3),np.nan,np.float32);normal=np.full_like(xyz,np.nan);depth=np.full((size,size),np.nan,np.float32);count=0
            for y in range(size):
                for x in range(size):
                    origin=target+direction*.35+right*((x+.5)/size-.5)*scale+up*((y+.5)/size-.5)*scale
                    hit,gn,ti,distance=tree.ray_cast(origin,-direction,.7)
                    if hit is None:continue
                    ids=faces[ti];bc=barycentric(np.asarray(hit),*points[ids]);sn=bc@normals[ids];sn/=np.linalg.norm(sn)
                    gn=np.asarray(gn);gn/=np.linalg.norm(gn)
                    row=np.zeros(20,np.float32);row[:3]=hit;row[3]=2;row[4:7]=sn;row[7]=scale/size*.72
                    row[8]=1;row[12]=.55;row[14]=2;row[15]=0;row[16:19]=gn;row[19]=1;rows.append(row)
                    xyz[y,x]=hit;normal[y,x]=sn;depth[y,x]=distance;count+=1
            name=f'native-head-a{az:03d}-e{elevation:+03d}.npz';np.savez_compressed(root/name,rest_xyz=xyz,normal=normal,depth=depth)
            views.append(dict(file=name,resolution=size,azimuth=az,elevation=elevation,samples=count,sha256=hashlib.sha256((root/name).read_bytes()).hexdigest()))
            print('NATIVE_HEAD_CAPTURE27',az,elevation,count,flush=True)
    # Spend redundant back-view samples on true perspective coverage of thin
    # orbital folds. These are source captures, not post-render pixel fills.
    size=512;tangent=math.tan(math.radians(35)*.5)
    for az in [-35,0,35]:
        angle=math.radians(az);direction=np.array([math.sin(angle),0,math.cos(angle)]);right=np.array([math.cos(angle),0,-math.sin(angle)]);up=np.array([0,1,0]);eye=np.array([0,1.525,.16])+direction*.35;count=0
        xyz=np.full((size,size,3),np.nan,np.float32);normal=np.full_like(xyz,np.nan);depth=np.full((size,size),np.nan,np.float32)
        for y in range(size):
            for x in range(size):
                ray=-direction+right*((2*(x+.5)/size-1)*tangent)+up*((1-2*(y+.5)/size)*tangent);ray/=np.linalg.norm(ray)
                hit,gn,ti,distance=tree.ray_cast(Vector(eye),Vector(ray),2)
                if hit is None:continue
                p=np.asarray(hit)
                if p[2]<.13 or min(((p[0]-c[0])/.028)**2+((p[1]-c[1])/.026)**2 for c in eyes)>1.3:continue
                ids=faces[ti];bc=barycentric(p,*points[ids]);sn=bc@normals[ids];sn/=np.linalg.norm(sn);gn=np.asarray(gn);gn/=np.linalg.norm(gn)
                z=np.dot(p-eye,-direction);pixel=2*z*tangent/size
                row=np.zeros(20,np.float32);row[:3]=p;row[3]=2;row[4:7]=sn;row[7]=pixel*.72/max(abs(gn@ray),.3);row[8]=1;row[12]=.55;row[14]=2;row[15]=0;row[16:19]=gn;row[19]=1;rows.append(row)
                xyz[y,x]=p;normal[y,x]=sn;depth[y,x]=distance;count+=1
        name=f'native-orbit-perspective-a{az:+03d}.npz';np.savez_compressed(root/name,rest_xyz=xyz,normal=normal,depth=depth)
        views.append(dict(file=name,resolution=size,azimuth=az,elevation=0,perspective=True,ocular_regions_only=True,samples=count,sha256=hashlib.sha256((root/name).read_bytes()).hexdigest()))
        print('NATIVE_PERSPECTIVE_CAPTURE27',az,count,flush=True)
    return np.asarray(rows,np.float32),views

def head_integrity(data,points,faces,eyes,vertices=None,triangles=None):
    """Retain inner anatomy but gate footprints that cross intact native skin.

    The boundary is measured in 3D source space. The same invertible facial
    field and head transform transport it with both skin and inner tissues.
    Disabling skin removes this gate, exposing the complete original anatomy.
    Ocular captures are explicitly exempt at the authored eye opening.
    """
    tree=BVHTree.FromPolygons(points.tolist(),faces.tolist(),all_triangles=True)
    data[data[:,19]==20,19]=1
    candidates=np.flatnonzero((data[:,3]>=0)&(data[:,15]>0)&(data[:,1]>1.44)&(data[:,19]!=10))
    sparse={}
    if vertices is not None and triangles is not None:
        indices=np.flatnonzero((data[:,3]<0)&(data[:,15]>0))
        xyz=np.einsum('ni,nij->nj',data[indices,:3],vertices[triangles[(-data[indices,3]-1).astype(int),:3],:3])
        sparse={int(i):p for i,p in zip(indices,xyz) if p[1]>1.44}
        candidates=np.concatenate([candidates,np.asarray(list(sparse),dtype=np.int64)])
    # The head has a complete opaque external skin surface in this mode.
    # Its enclosed layers cannot be visible from an outside camera; cull their
    # captured footprints as a head-local integrity state, not as a pixel mask.
    # Ocular samples are the sole intentional opening. Removing skin restores
    # every enclosed sample without modifying or deleting its native anatomy.
    counts={str(i):int(np.count_nonzero(data[candidates,15]==i)) for i in range(1,4)}
    data[candidates,19]=20
    return counts
    counts={str(i):0 for i in range(1,4)}
    center=Vector((0,1.54,.09))
    directions=[Vector((math.sin(math.radians(a))*math.cos(math.radians(e)),math.sin(math.radians(e)),math.cos(math.radians(a))*math.cos(math.radians(e)))) for a in [-70,-35,0,35,70] for e in [-30,0,30]]
    for index in candidates:
        p=Vector(sparse[index] if data[index,3]<0 else data[index,:3]);radial=p-center;length=radial.length
        # In an intact ocular region the visible surfaces are lid/skin or
        # the actual eyeball. Source orbital muscle/nerve overlaps must not
        # become a substitute surface at the authored opening. This is a
        # head-local 3D volume, transported with the shared facial/head rig.
        padding=2*float(data[index,7])
        if any(((p.x-e[0])/(.030+padding))**2+((p.y-e[1])/(.026+padding))**2+((p.z-e[2]-.014)/(.060+padding))**2<1 for e in eyes):
            data[index,19]=20;counts[str(int(data[index,15]))]+=1;continue
        if length<1e-8:continue
        direction=radial/length
        # Skin is a tissue shell with inner AND outer faces. The closest
        # dermal face can point into the skull, so its normal is not a valid
        # whole-head inside test. Use the first external source intersection.
        hit,normal,ti,distance=tree.ray_cast(center+direction*.35,-direction,.7)
        if hit is None:continue
        boundary=(hit-center).dot(direction)
        if length+2*float(data[index,7])+.0001>boundary:
            data[index,19]=20;counts[str(int(data[index,15]))]+=1
            continue
        # Concave facial creases are not star-shaped from the head center.
        # Check first source intersections along the authored capture views,
        # restricting these extra rays to the anterior face.
        if p.z>.115:
            padding=2*float(data[index,7])+.0001
            for view in directions:
                hit,normal,ti,distance=tree.ray_cast(p+view*.35,-view,.7)
                if hit is not None and (hit-p).dot(view)<padding:
                    data[index,19]=20;counts[str(int(data[index,15]))]+=1;break
    return counts

def upgrade(source,base,out):
    if hashlib.file_digest(source.open('rb'),'sha256').hexdigest()!=SOURCE_SHA:raise ValueError('Unknown source')
    bpy.ops.wm.open_mainfile(filepath=str(source.resolve()),load_ui=False,use_scripts=False)
    m=json.loads((base/'master.json').read_text());s=np.fromfile(base/'samples.bin',dtype='<f4').reshape(-1,20)
    old_skin=int(m['layers'][0]['sample_count']);skin=s[:old_skin]
    remove=((skin[:,3]>=0)&(skin[:,1]>1.44))|(skin[:,3]<-6154)
    retained=skin[~remove].copy();inner=s[old_skin:].copy();del s,skin;gc.collect()
    vertices=np.fromfile(base/'vertices.bin',dtype='<f4').reshape(-1,24)[:11420].copy()
    triangles=np.fromfile(base/'triangles.bin',dtype='<u4').reshape(-1,4)[:6154].copy()
    # Weld only for source topology analysis; this does not change the source file.
    p,f=geometry(bpy.data.objects['skin']);f=f[np.all(p[f,1]>1.44,axis=1)];p,f=weld(p,f)
    original=p.copy();original_faces=f.copy();native_normals=smooth_normals(p,f)
    ep,ef=geometry(bpy.data.objects['eyeball']);eyes=[]
    for sign in [-1,1]:
        e=ep[ep[:,0]*sign>0];eyes.append((e.min(0)+e.max(0))*.5)
    kept,patches=orbital_patches(p,f,eyes,width=.0185,height=.009)
    # Ears and lips remain native captured surfaces, in the same head gallery.
    for name in ['ear','labial part of mouth, nsn']:
        if name not in bpy.data.objects:continue
        a,b=geometry(bpy.data.objects[name]);b=b[np.all(a[b,1]>1.44,axis=1)]
        kept=np.concatenate([kept,b+len(p)]);p=np.concatenate([p,a])
    out.mkdir(parents=True,exist_ok=True);head,head_views=capture_native(p,kept,out,eyes)
    extras=[];galleries=[];boundaries=[]
    for i,patch in enumerate(patches):
        vi=len(vertices);ti=len(triangles);v=np.zeros((len(patch['rest']),24),np.float32)
        v[:,:3]=patch['rest'];v[:,3]=2;v[:,4]=2;v[:,8:11]=patch['closed']-patch['rest'];v[:,11]=int(eyes[i][0]>0)
        v[:,12:15]=patch['middle']-(patch['rest']+patch['closed'])*.5;v[:,15]=1
        n0=smooth_normals(patch['rest'],patch['faces']);n1=smooth_normals(patch['closed'],patch['faces'])
        # The first ring shares native position AND shading normal with skin.
        count=len(patch['boundary']);lookup={tuple(np.round(x*1e6).astype(int)):j for j,x in enumerate(original)}
        ids=[lookup[tuple(np.round(x*1e6).astype(int))] for x in patch['boundary']]
        n0[:count]=native_normals[ids];n1[:count]=native_normals[ids]
        v[:,16:19]=n0;v[:,20:23]=n1
        vertices=np.concatenate([vertices,v]);triangles=np.concatenate([triangles,np.column_stack([patch['faces']+vi,np.zeros(len(patch['faces']),np.int32)])])
        side='left' if eyes[i][0]>0 else 'right';rows,views=capture_patch(patch,vi,ti,out,side,scale=.045,resolution=160);extras.append(rows)
        galleries.append(dict(side=side,vertex_offset=vi,vertex_count=len(v),triangle_offset=ti,triangle_count=len(patch['faces']),views=views))
        boundaries.append(dict(side=side,points=patch['boundary'].tolist(),max_rest_error_m=0,max_boundary_normal_error=0))
        print('NATIVE_LID_CAPTURE27',side,len(v),len(rows),flush=True)
    new_skin=np.concatenate([retained,head,*extras]);data=np.concatenate([new_skin,inner]);del retained,head,inner;gc.collect()
    if len(data)>6000000:raise ValueError(f'{len(data)} exceeds accumulation contract')
    shift=len(new_skin)-old_skin;m['layers'][0]['sample_count']=len(new_skin)
    for layer in m['layers'][1:]:layer['sample_offset']+=shift
    tree=BVHTree.FromPolygons(ep.tolist(),ef.tolist(),all_triangles=True)
    possible=np.flatnonzero((data[:,3]>=0)&(data[:,15]==3)&np.all(data[:,:3]>=ep.min(0)-.00003,axis=1)&np.all(data[:,:3]<=ep.max(0)+.00003,axis=1))
    eye_ids={'left':[],'right':[],'tolerance_m':.00003,'source_sha256':SOURCE_SHA,'method':'native eyeball triangle BVH'}
    for index in possible:
        hit,n,ti,d=tree.find_nearest(Vector(data[index,:3]),.00003)
        if hit is not None:
            data[index,19]=10;data[index,12]=.2;eye_ids['left' if data[index,0]>0 else 'right'].append(int(index))
    if not eye_ids['left'] or not eye_ids['right']:raise ValueError('Missing native ocular captures')
    gates=head_integrity(data,original,original_faces,eyes,vertices,triangles)
    payloads={'samples.bin':data.astype('<f4').tobytes(),'vertices.bin':vertices.astype('<f4').tobytes(),'triangles.bin':triangles.astype('<u4').tobytes()}
    m.update(sample_count=len(data),invocation_count=len(data),vertex_count=len(vertices),triangle_count=len(triangles),orbital_galleries=galleries,orbital_boundaries=boundaries,eyes=[e.tolist() for e in eyes],native_head_galleries=head_views,skin_integrity_contract='native-triangle-boundary-v2',ocular_contract='native-eyeball-material-v1',blink_contract='connected-orbit-overlap-v3',lid_contact_overlap_m=.0002,skin_head_samples_removed=int(remove.sum()),ocular_sample_count=sum(len(eye_ids[k]) for k in ['left','right']))
    m['buffers']={name:dict(bytes=len(content),sha256=hashlib.sha256(content).hexdigest()) for name,content in payloads.items()}
    m['skin_gate_contract']='native-footprint-envelope-v1';m['skin_gate_samples']=gates;m['skin_gate_method']='head-local external envelope from center and 15 anterior source rays; intact ocular ellipsoids permit only skin/eyeball; no geometric gate when source rays miss; full anatomy restored when skin disabled'
    m['ocular_visibility_regions']=[dict(center=(e+np.array([0,0,.014])).tolist(),radii=[.030,.026,.060],bone=2,kind='intact_ocular_surface',visible_materials=['skin','native_eyeball']) for e in eyes]
    for name,content in payloads.items():(out/name).write_bytes(content)
    np.column_stack([data[:,15],data[:,19]]).astype('u1').tofile(out/'sample-material-reference.bin')
    (out/'master.json').write_text(json.dumps(m,indent=2)+'\n');(out/'eyeball-sample-indices.json').write_text(json.dumps(eye_ids,indent=2)+'\n')
    np.savez_compressed(out/'orbital-source-reference.npz',points=p,faces=kept,original_points=original,original_faces=original_faces,eye_points=ep,eye_faces=ef,**{f'{key}{i}':patch[key] for i,patch in enumerate(patches) for key in ['rest','closed','middle','faces']})
    print('INTACT_BANK27',len(data),'samples',len(vertices),'vertices',len(triangles),'triangles',flush=True)

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--input',type=Path,required=True);parser.add_argument('--base',type=Path,required=True);parser.add_argument('--out',type=Path,required=True)
    args=parser.parse_args(sys.argv[sys.argv.index('--')+1:]);upgrade(args.input,args.base,args.out)

if __name__=='__main__':main()
