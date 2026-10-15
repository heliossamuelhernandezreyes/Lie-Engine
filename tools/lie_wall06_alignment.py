"""Rigidly orient the photographed master; transfer real mortar and rebuild GI.

WALL05 source banks are read-only. Rotation/translation preserves shape and
all RGB/material records; no flattening, shear or mesh drawing is introduced.
"""
import hashlib,json,math
from pathlib import Path
import numpy as np
from scipy.spatial import cKDTree
from lie_wall05_shared import build as build_previous
from lie_wall02_bake import layout,transform_real_samples,support_rebuild,make_node_model,canonical_light_codes
from lie_wall04_factors import calculate
from lie_sparse_transport import pack
from lie_asset_contract import planar_frame
ROOT=Path(__file__).resolve().parents[1]
DEST=ROOT/'gpu_compute/captures/liewall06'

def sha(data):return hashlib.sha256(data).hexdigest()
def orientation(source):
    hero=source[:220000]
    indices=np.flatnonzero((hero[:,6]>.85)&(hero[:,2]>.02))
    frame=planar_frame(source,indices)
    return frame['rotation'],frame['translation'],frame['bounds_size'],frame['source_normal'],frame['selection_count']

def rotate_master(source):
    R,t,dims,n,count=orientation(source)
    out=source.copy();out[:,:3]=source[:,:3].astype(float)@R.T+t
    out[:,4:7]=source[:,4:7].astype(float)@R.T
    support_rebuild(out)
    return out,(R,t,dims,n,count)

def front_tree(samples,poses,dims):
    # Use dense authentic front source (not the tiny rendered wall subset).
    f=samples[:220000];f=f[(f[:,6]>.70)&(f[:,2]>0)]
    points=[]
    scale=(dims[:2]+.0085-.003)/dims[:2]
    for i,p in enumerate(poses):
        w=transform_real_samples(f,p['center'],p['yaw_rad'],p['tone'],i*9,.0052)
        center=np.array(p['center'][:2]);w[:,:2]=center+(w[:,:2]-center)*scale
        points.append(w[:,:3])
    points=np.concatenate(points).astype(float)
    return cKDTree(points[:,:2]),points[:,2]

def transfer_mortar(old,old_tree,new_tree,ratios):
    out=old.copy();out[:,:2]=old[:,:2]*ratios
    dt,z=old_tree;nt,nz=new_tree
    # Preserve the old sample's signed setback from the same photographed
    # front layer, then clip behind measured new front source points.
    _,ids=dt.query(old[:,:2],k=8);old_front=np.quantile(z[ids],.8,axis=1)
    _,ids=nt.query(out[:,:2],k=8);new_front=np.quantile(nz[ids],.8,axis=1)
    setback=np.maximum(old_front-old[:,2],.0008)
    out[:,2]=new_front-setback
    out[:,4:6]/=ratios
    out[:,4:7]/=np.linalg.norm(out[:,4:7],axis=1)[:,None]
    support_rebuild(out)
    return out

def outgoing(sparse):
    data=np.frombuffer(sparse,dtype='<u4');ob,eb=map(int,data[2:4]);rows=[[] for _ in range(872)]
    for dst in range(872):
        for e in range(int(data[ob+dst]),int(data[ob+dst+1])):
            src,w=map(int,data[eb+2*e:eb+2*e+2]);rows[src].append((dst,w))
    offsets=[0];edges=[]
    for row in rows:
        for edge in row:edges.extend(edge)
        offsets.append(len(edges)//2)
    return np.asarray([872,len(edges)//2,4,877]+offsets+edges,dtype='<u4').tobytes()

def build(dest=DEST):
    previous=ROOT/'gpu_compute/captures/liewall05'
    if not (previous/'library.bin').is_file():build_previous()
    cat=json.loads((previous/'catalog.json').read_text());raw=(previous/'library.bin').read_bytes()
    if sha(raw)!=cat['sha256']:raise ValueError('WALL05 source SHA')
    source=np.frombuffer(raw,dtype='<f4').reshape(-1,20);neutral=source[:281000]
    aligned,(R,t,dims,n,count)=rotate_master(neutral)
    poses,_=layout(dims.astype(np.float32));oldposes=cat['wall05']['poses']
    olddims=np.array(json.loads((ROOT/'gpu_compute/captures/liebrick02/catalog.json').read_text())['source_bbox_m'])
    ratios=(dims[:2]+.0085)/(olddims[:2]+.0085)
    print('WALL06 rigid orientation',dims.tolist(),'rotation deg',math.degrees(math.acos(n[2])),flush=True)
    oldtree=front_tree(neutral,oldposes,olddims);newtree=front_tree(aligned,poses,dims)
    mortar=transfer_mortar(source[281000:],oldtree,newtree,ratios)
    bank=np.concatenate([aligned,mortar]).astype('<f4');bankraw=bank.tobytes()
    cat['sha256']=sha(bankraw);cat['wall05']['poses']=poses
    cat['wall05']['source_records_copied_without_modification']=False
    cat['wall05']['neutral_brick_records_byte_identical']=False
    cat['wall_layout']['scanned_brick_xyz_and_colors_unchanged']=False
    centers=np.array([p['center'] for p in poses]);lo=centers.min(0)-dims*.5-.002;hi=centers.max(0)+dims*.5+.002
    master=cat['masters']['real_scan_wall'];master['bounds_size']=(hi-lo+.005).tolist();master['bounds_center']=((hi+lo)*.5).tolist()
    g=cat['wall_layout']['mortar_shader_layout'];g.update(brick_length_m=float(dims[0]),brick_height_m=float(dims[1]),pitch_x_m=float(dims[0]+.0085),pitch_y_m=float(dims[1]+.0085),first_brick_x_m=poses[0]['center'][0],first_brick_y_m=poses[0]['center'][1],mortar_plane_z_m=float(np.quantile(mortar[:,2],.8)))
    model=make_node_model(aligned[:220000],poses,(lo,hi),dims);model['patches'].pop();model['blockers']=[]
    hero=[];refs=np.fromfile(previous/'sample-refs.bin',dtype='<u4');jobs=cat['wall05']['instance_jobs'][0]
    for i,p in enumerate(poses):
        start,howmany,_,_=jobs[i];a=aligned[refs[start:start+howmany]]
        hero.append(transform_real_samples(a,p['center'],p['yaw_rad'],p['tone'],i*9,.0052))
    level=cat['masters']['joint_photo']['levels'][0];joint=bank[level['start']:level['start']+level['count']];hero.append(joint)
    hero=np.concatenate(hero)
    for row in range(8):
        member=joint[np.rint(joint[:,9]).astype(int)==864+row]
        if len(member)==0:raise ValueError('Missing photographic mortar course')
        rgb=member[:,12:15].mean(0)
        model['patches'].append({'position':(member[:,:3].mean(0)+[0,0,.0015]).tolist(),'normal':[0.,0.,1.],'area':float((hi[0]-lo[0])*(dims[1]+.0085)*.15),'gray_mean':float(rgb.max()),'material':'mortar','brick_id':-1,'micro_id':864+row,'mortar_course':row})
    model.update(direct_shadow_mortar_count=8,mortar_light_provenance='WALL06 centroid of actual recalibrated photographed course samples')
    model=canonical_light_codes(model);light=(json.dumps(model,indent=2)+'\n').encode();cat['lighting']['sha256']=sha(light)
    cat['wall06']={'schema':'lie-rigid-scan-alignment/1','source_wall05_sha256':sha(raw),'source_neutral_sha256':sha(neutral.tobytes()),'rotation':R.tolist(),'translation_m':t.tolist(),'rotation_angle_deg':math.degrees(math.acos(n[2])),'original_front_normal':n.tolist(),'front_samples':count,'aligned_bbox_m':dims.tolist(),'shape_preserved_rigidly':True,'source_rgb_material_bytes_preserved':True,'mortar_rgb_material_bytes_preserved':True,'mortar_xy_pitch_ratio':ratios.tolist(),'mortar_setback_method':'nearest 8 dense original front points p80 before/after; minimum 0.8mm setback','metric_mortar_height_certified':False,'runtime_original_mesh_draws':0}
    # Actual oriented scan plane for both direct and indirect visibility.
    front=aligned[:220000];front=front[(front[:,6]>.85)&(front[:,2]>.02),:3].astype(float)
    _,v=np.linalg.eigh(np.cov(front,rowvar=False));normal=v[:,0]
    if normal[2]<0:normal=-normal
    offset=float(np.quantile(front@normal,.05)-.0015);planes=[]
    for p in poses:
        c,s=math.cos(p['yaw_rad']),math.sin(p['yaw_rad']);wn=np.array([[c,0,s],[0,1,0],[-s,0,c]])@normal
        planes.append([*wn,offset+np.dot(wn,p['center'])])
    capraw=np.asarray(planes,dtype='<f4').tobytes()
    factors,proof=calculate(model,cat,planes);proof['original_brick_samples_changed']=True;proof['rigid_shape_preserved']=True
    sparse,meta=pack(factors.tobytes(),872);meta.update(source_factor_sha256=proof['sha256'],input_wall_sha256=cat['sha256'],input_light_sha256=sha(light))
    node=np.rint(hero[:,9]).astype(int);counts=np.bincount(node,minlength=872)
    opt=np.zeros((872,16),dtype='<f4');opt[:,6]=1.5
    for column,field in [(0,12),(1,13),(2,14),(3,10),(12,4),(13,5),(14,6)]:opt[:,column]=np.bincount(node,weights=hero[:,field],minlength=872)/counts
    opt[:,12:15]/=np.linalg.norm(opt[:,12:15],axis=1)[:,None]
    data={'library.bin':bankraw,'sample-refs.bin':refs.tobytes(),'light-model.json':light,'indirect_factors.bin':factors.tobytes(),'indirect_sparse.bin':sparse,'optics.bin':np.array([0,872,0,0],dtype='<u4').tobytes()+opt.tobytes(),'shadow-caps.bin':capraw,'outgoing-csr.bin':outgoing(sparse)}
    for name in ['optics.bin','shadow-caps.bin','outgoing-csr.bin']:cat['wall05'][name]={'bytes':len(data[name]),'sha256':sha(data[name])}
    cat['wall05']['shadow_front_plane']={'normal':normal.tolist(),'offset_m':offset,'clearance_m':.0015,'quantile':.05,'samples':len(front),'purpose':'oriented light-only inner plane'}
    cat['note']='WALL06 rigid orientation and photo mortar transfer; no shape flattening; experimental quality.'
    dest=Path(dest);dest.mkdir(parents=True,exist_ok=True)
    for name,blob in data.items():(dest/name).write_bytes(blob)
    for name,obj in [('catalog.json',cat),('indirect_factors.json',proof),('indirect_sparse.json',meta)]:(dest/name).write_text(json.dumps(obj,indent=2)+'\n')
    return cat
if __name__=='__main__':print(json.dumps(build()['wall06'],indent=2))
