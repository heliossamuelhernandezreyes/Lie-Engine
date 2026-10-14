"""WALL05: one immutable original brick master, IDs into it and photo mortar.

Preserves the exact source subsets, seeded poses/tints and LOD work of WALL04.
Only 4-byte source references repeat; no 80-byte brick record is precomposed.
"""
import hashlib,json,zlib
from pathlib import Path
import numpy as np
from lie_wall02_bake import layout,SEED,SAMPLES_PER_BRICK
from lie_brick02_restore import restore as restore_brick
from lie_wall04_compose import restore as restore_wall
ROOT=Path(__file__).resolve().parents[1]
DEST=ROOT/'gpu_compute/captures/liewall05'

def build(dest=DEST):
    restore_brick();restore_wall()
    brick=ROOT/'gpu_compute/captures/liebrick02';wall=ROOT/'gpu_compute/captures/liewall04'
    bc=json.loads((brick/'catalog.json').read_text());wc=json.loads((wall/'catalog.json').read_text())
    neutral=(brick/'library.bin').read_bytes();old=(wall/'library.bin').read_bytes()
    if hashlib.sha256(neutral).hexdigest()!=bc['sha256'] or hashlib.sha256(old).hexdigest()!=wc['sha256']:raise ValueError('Source bank SHA mismatch')
    a=np.frombuffer(old,dtype='<f4').reshape(-1,20)
    poses,_=layout(np.asarray(bc['source_bbox_m'],dtype=np.float32))
    chunks=[neutral];mortar_levels=[];cursor=bc['sample_count'];refs=[];jobs=[];ref_cursor=0
    for lod,(count,level) in enumerate(zip(SAMPLES_PER_BRICK,wc['masters']['real_scan_wall']['levels'])):
        src=bc['masters']['brick_full']['levels'][lod]
        row=[]
        for i in range(96):
            rng=np.random.default_rng(SEED+lod*1000003+i*7919)
            ids=(rng.choice(src['count'],count,replace=False)+src['start']).astype('<u4')
            refs.append(ids.tobytes());row.append([ref_cursor,count,i,sum(j[1] for j in row)]);ref_cursor+=count
        joint=a[level['start']:level['start']+level['count']]
        joint=joint[joint[:,9]>=864].copy();raw=joint.astype('<f4').tobytes();chunks.append(raw)
        mortar_levels.append({'start':cursor,'count':len(joint)})
        refs.append(np.arange(cursor,cursor+len(joint),dtype='<u4').tobytes())
        row.append([ref_cursor,len(joint),96,sum(j[1] for j in row)]);ref_cursor+=len(joint);cursor+=len(joint)
        jobs.append(row)
    raw=b''.join(chunks);indices=b''.join(refs)
    cat=json.loads(json.dumps(wc));cat.update(bytes=len(raw),sample_count=cursor,sha256=hashlib.sha256(raw).hexdigest())
    # All master ranges refer to actual stored samples; the separate jobs are
    # indirection ranges. Existing command validation still sees the wall master.
    cat['masters']['real_scan_wall']['levels']=[dict(x) for x in bc['masters']['brick_full']['levels']]
    cat['masters']['brick_wall']={'levels':[{'start':x['start'],'count':c} for x,c in zip(bc['masters']['brick_full']['levels'],SAMPLES_PER_BRICK)]}
    cat['masters']['joint_photo']={'levels':mortar_levels}
    cat['wall05']={'source_wall_sha256':wc['sha256'],'neutral_brick_sha256':bc['sha256'],
      'neutral_master_bytes':len(neutral),'neutral_master_count':1,'brick_instances':96,'instance_jobs':jobs,
      'poses':poses,'reference_count':ref_cursor,'reference_bytes':len(indices),'reference_sha256':hashlib.sha256(indices).hexdigest(),
      'source_records_copied_without_modification':True,'brick_radius_by_lod':[.0052,.0093,.018],
      'geometry_precomposed':False,'original_source_triangles_rendered':0,'collision_envelopes':1}
    # Robust exposed-front plane for light visibility only. AABB corners are
    # not scanned material. Clip every old proxy behind a measured source plane.
    source=np.frombuffer(neutral,dtype='<f4').reshape(-1,20)[:bc['masters']['brick_full']['levels'][0]['count']]
    front=source[(source[:,6]>.85)&(source[:,2]>.02),:3].astype(np.float64)
    _,v=np.linalg.eigh(np.cov(front,rowvar=False));n=v[:,0]
    if n[2]<0:n=-n
    offset=float(np.quantile(front@n,.05)-.0015)
    cat['wall05']['shadow_front_plane']={'normal':n.tolist(),'offset_m':offset,'clearance_m':.0015,'quantile':.05,'samples':len(front),'purpose':'light-only inner plane; no visual deformation'}
    cat['wall04']['original_brick_samples_byte_identical']=False
    cat['wall05']['neutral_brick_records_byte_identical']=True
    # Full 872-node captured optical properties, no inference of metal/IOR.
    hero=a[:wc['masters']['real_scan_wall']['levels'][0]['count']]
    node=np.rint(hero[:,9]).astype(int);counts=np.bincount(node,minlength=872)
    if (counts==0).any():raise ValueError('Missing captured optical patch')
    means=np.stack([np.bincount(node,weights=hero[:,k],minlength=872)/counts for k in (12,13,14,10,4,5,6)],axis=1)
    opt=np.zeros((872,16),dtype='<f4');opt[:,:4]=means[:,:4];opt[:,6]=1.5
    normals=means[:,4:7];normals/=np.linalg.norm(normals,axis=1)[:,None];opt[:,12:15]=normals
    optics=np.array([0,872,0,0],dtype='<u4').tobytes()+opt.tobytes()
    caps=[]
    for pose in poses:
        from math import cos,sin
        co,si=cos(pose['yaw_rad']),sin(pose['yaw_rad'])
        wn=np.array([[co,0,si],[0,1,0],[-si,0,co]])@n
        caps.append([*wn,offset+float(wn@np.asarray(pose['center']))])
    caps=np.asarray(caps,dtype='<f4').tobytes()
    sparse=np.fromfile(wall/'indirect_sparse.bin',dtype='<u4');ob=int(sparse[2]);eb=int(sparse[3]);rows=[[] for _ in range(872)]
    for dst in range(872):
        for e in range(int(sparse[ob+dst]),int(sparse[ob+dst+1])):
            src,w=map(int,sparse[eb+e*2:eb+e*2+2]);rows[src].append((dst,w))
    offsets=[0];edges=[]
    for row in rows:
        for edge in row:edges.extend(edge)
        offsets.append(len(edges)//2)
    outgoing=np.asarray([872,len(edges)//2,4,877]+offsets+edges,dtype='<u4').tobytes()
    for name,data in [('optics.bin',optics),('shadow-caps.bin',caps),('outgoing-csr.bin',outgoing)]:
        cat['wall05'][name]={'bytes':len(data),'sha256':hashlib.sha256(data).hexdigest()}
    cat['wall05']['optical_capture']={'patches':872,'attributes':'linear albedo, roughness and normal means from source samples','authored_defaults':{'metallic':0,'transmission':0,'ior':1.5,'sigma_rgb':[0,0,0],'thickness_m':0},'medium':'opaque clay/mortar; no glass paths in this wall graph'}
    dest=Path(dest);dest.mkdir(parents=True,exist_ok=True)
    (dest/'library.bin').write_bytes(raw);(dest/'sample-refs.bin').write_bytes(indices)
    for name,data in [('optics.bin',optics),('shadow-caps.bin',caps),('outgoing-csr.bin',outgoing)]: (dest/name).write_bytes(data)
    (dest/'catalog.json').write_text(json.dumps(cat,indent=2)+'\n')
    return cat
if __name__=='__main__':
    c=build();print(json.dumps({'bank_bytes':c['bytes'],'sha256':c['sha256'],'reference_bytes':c['wall05']['reference_bytes'],'source_wall':c['wall05']['source_wall_sha256'],'front_plane':c['wall05']['shadow_front_plane']},indent=2))
