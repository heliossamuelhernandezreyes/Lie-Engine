"""Shared, source-preserving preflight for LIE 80-byte masters.

Semantic orientation is authored; planar fitting needs an explicit surface
selection. Never infer a character's front from its longest bounding-box axis.
"""
import argparse,hashlib,json
from pathlib import Path
import numpy as np

def digest(data):return hashlib.sha256(data).hexdigest()
def proper_rotation(matrix):
    R=np.asarray(matrix,dtype=np.float64)
    if R.shape!=(3,3) or not np.isfinite(R).all() or not np.allclose(R@R.T,np.eye(3),atol=1e-7) or abs(np.linalg.det(R)-1)>1e-7:
        raise ValueError('frame_requires_proper_rotation')
    return R

def bound_source_support(samples,low,high):
    """Explicit AABB support policy for thin authored masters, not a polygon clip."""
    a=np.asarray(samples);lo=np.asarray(low)-2e-7;hi=np.asarray(high)+2e-7
    dominant=np.argmax(abs(a[:,4:7]),axis=1)
    for axis,(u,v) in enumerate(((2,1),(0,2),(0,1))):
        m=dominant==axis;a[m,16:18]=np.maximum(a[m,16:18],lo[[u,v]]);a[m,18:20]=np.minimum(a[m,18:20],hi[[u,v]])
    if (a[:,16:18]>a[:,18:20]).any():raise ValueError('source_support_outside_envelope')
    return a

def authored_planar_support(vertices,faces,normals,groups,basis,scale,pivot):
    """Validate an authored partition and bound each planar group in its axes.

    These are rectangles of explicitly declared planar source groups. They
    are not arbitrary polygon silhouettes or inferred semantic orientation.
    """
    v=(np.asarray(vertices)-pivot)@basis.T*scale;n=np.asarray(normals)@basis.T;f=np.asarray(faces);seen=np.zeros(len(f),int);bounds=np.zeros((len(f),4),dtype='<f4')
    for group in groups:
        ids=np.asarray(group)
        if ids.ndim!=1 or ids.dtype.kind not in 'iu' or not len(ids) or ids.min()<0 or ids.max()>=len(f) or len(np.unique(ids))!=len(ids):raise ValueError('source_support_group_indices')
        seen[ids]+=1;normal=n[ids[0]]
        if np.min(n[ids]@normal)<.99999:raise ValueError('source_support_group_not_planar')
        points=v[f[ids].ravel()];plane=points@normal
        if np.ptp(plane)>2e-6:raise ValueError('source_support_group_not_planar')
        axis=int(np.argmax(abs(normal)));u,w=((2,1),(0,2),(0,1))[axis];uv=points[:,[u,w]];bounds[ids]=np.r_[uv.min(0)-2e-7,uv.max(0)+2e-7]
    if not (seen==1).all():raise ValueError('source_support_groups_must_partition_faces')
    return bounds

def planar_frame(samples,indices,forward_hint=(0,0,1),right_hint=(1,0,0),max_planarity=.2):
    a=np.asarray(samples);ids=np.asarray(indices)
    if a.ndim!=2 or a.shape[1]<7 or ids.ndim!=1 or ids.dtype.kind not in 'iu' or len(ids)<32 or (ids<0).any() or (ids>=len(a)).any():raise ValueError('frame_surface_selection')
    front=a[ids,:3].astype(float)
    if not np.isfinite(front).all():raise ValueError('frame_nonfinite_points')
    eigen,v=np.linalg.eigh(np.cov(front,rowvar=False))
    if eigen[1]<1e-12 or eigen[0]/eigen[1]>max_planarity:raise ValueError('frame_no_reliable_plane')
    n=v[:,0];hint=np.asarray(forward_hint,dtype=float);right=np.asarray(right_hint,dtype=float)
    if hint.shape!=(3,) or right.shape!=(3,) or not np.isfinite([hint,right]).all() or np.linalg.norm(hint)<1e-10 or np.linalg.norm(right)<1e-10:raise ValueError('frame_invalid_semantic_hints')
    if n@hint<0:n=-n
    x=right-n*(right@n)
    if np.linalg.norm(x)<1e-8:raise ValueError('frame_ambiguous_right_hint')
    x/=np.linalg.norm(x);R=np.stack([x,np.cross(n,x),n]);proper_rotation(R)
    xyz=a[:,:3].astype(float)@R.T;t=-(xyz.max(0)+xyz.min(0))*.5
    return {'rotation':R,'translation':t,'bounds_size':np.ptp(xyz,axis=0),'source_normal':n,'selection_count':len(ids),'planarity_ratio':float(eigen[0]/eigen[1]),'method':'explicit source surface + semantic forward/right; rigid PCA fit'}

def inspect_bank(raw,catalog):
    if catalog.get('stride')!=80 or len(raw)%80 or catalog.get('bytes')!=len(raw) or catalog.get('sample_count')!=len(raw)//80 or catalog.get('sha256')!=digest(raw):raise ValueError('asset_bank_integrity')
    a=np.frombuffer(raw,dtype='<f4').reshape(-1,20)
    if not len(a) or not np.isfinite(a).all():raise ValueError('asset_nonfinite_samples')
    if (a[:,3]<=0).any():raise ValueError('asset_nonpositive_support_radius')
    if np.max(abs(np.linalg.norm(a[:,4:7],axis=1)-1))>2e-4:raise ValueError('asset_normal_length')
    if ((a[:,12:16]<0)|(a[:,12:16]>1)).any() or ((a[:,10]<0)|(a[:,10]>1)).any():raise ValueError('asset_material_range')
    if (a[:,16:18]>a[:,18:20]).any():raise ValueError('asset_support_bounds')
    if (a[:,9]<0).any() or (a[:,9]>=2**24).any() or not np.array_equal(a[:,9],np.rint(a[:,9])):raise ValueError('asset_patch_id_precision')
    masters=catalog.get('masters',{});descriptors={}
    if not isinstance(masters,dict) or not masters:raise ValueError('asset_missing_masters')
    for name,m in masters.items():
        levels=m.get('levels',[])
        if not levels:raise ValueError('asset_missing_lods')
        for level in levels:
            start,count=level.get('start'),level.get('count')
            if type(start) is not int or type(count) is not int or start<0 or count<=0 or start+count>len(a):raise ValueError('asset_lod_bounds')
        key=digest((catalog['sha256']+'|'+name+'|80|'+','.join(str(x['start'])+':'+str(x['count']) for x in levels)).encode())
        descriptors[name]={'asset_id':key,'bank_sha256':catalog['sha256'],'stride':80,'levels':levels,'sample_ids':'uint32 bank offsets; identity scoped by bank SHA + master; resident source access'}
    return {'schema':'lie-asset-contract/1','bank_sha256':catalog['sha256'],'bytes':len(raw),'sample_count':len(a),'assets':descriptors,'checks':['integrity','finite','normals','radii','material_ranges','face_support','patch_id_precision','lod_ranges'],'renderer_acceptance':'requires native depth/coverage/material and cache tests; preflight is not visual certification'}

def optical_profile(profile):
    if not isinstance(profile,dict):raise ValueError('asset_material_declaration_required')
    fields=('metallic','transmission','ior','roughness_origin')
    if any(k not in profile for k in fields):raise ValueError('asset_material_declaration_required')
    if any(not isinstance(profile[k],(float,int)) or isinstance(profile[k],bool) or not np.isfinite(profile[k]) for k in fields[:3]):raise ValueError('asset_material_declaration_invalid')
    if not 0<=profile['metallic']<=1 or not 0<=profile['transmission']<=1 or profile['ior']<1 or profile['roughness_origin'] not in ('authored','source_factor','source_map','measured'):raise ValueError('asset_material_declaration_invalid')
    return dict(profile)

if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--bank',type=Path,required=True);p.add_argument('--catalog',type=Path,required=True);p.add_argument('--output',type=Path,required=True);args=p.parse_args()
    report=inspect_bank(args.bank.read_bytes(),json.loads(args.catalog.read_text()));args.output.parent.mkdir(parents=True,exist_ok=True);args.output.write_text(json.dumps(report,indent=2)+'\n');print(json.dumps({'bank':report['bank_sha256'],'masters':list(report['assets']),'checks':report['checks']}))
