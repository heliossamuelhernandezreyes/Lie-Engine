"""Shared source-only surface selection and camera-independent surfel queries.

The bank is immutable: selections and BVH leaves contain source IDs. A surfel
is its captured tangent disk, not a box face or an original source mesh draw.
All coordinates are meters; instances may use invertible affine transforms.
"""
import hashlib,math,struct
import numpy as np
from scipy.spatial import cKDTree
EMPTY=0xffffffff

def sha(data):return hashlib.sha256(data).hexdigest()
def require_bank(samples):
    a=np.asarray(samples)
    if a.ndim!=2 or a.shape[1]!=20 or not len(a) or not np.isfinite(a).all():raise ValueError('surface bank ABI/finite')
    if (a[:,3]<=0).any() or not np.allclose(np.linalg.norm(a[:,4:7],axis=1),1,atol=2e-4):raise ValueError('surface radius/normal')
    return a

def partition_selection(samples,budget,variants=4):
    """Balanced spatial strata, separated by authored geometric hemisphere.

    Each variant chooses a genuine source member near each stratum's spatial
    centroid. No mean RGB, invented normal, enlarged support or new point.
    """
    a=require_bank(samples);n=len(a)
    if type(budget) is not int or not 1<=budget<=n or not 1<=variants<=16:raise ValueError('surface selection budget')
    p=a[:,:3].astype(float);normal=a[:,4:7];axis=np.argmax(abs(normal),axis=1)
    faces=axis*2+(normal[np.arange(n),axis]<0)
    groups=[np.flatnonzero(faces==f) for f in np.unique(faces)]
    if budget<len(groups):groups=[np.arange(n)]
    counts=np.array([len(g) for g in groups]);allocation=np.floor((budget-len(groups))*counts/n).astype(int)+1
    while allocation.sum()<budget:
        eligible=np.flatnonzero(allocation<counts)
        k=eligible[np.argmax(counts[eligible]/allocation[eligible])];allocation[k]+=1
    leaves=[]
    def split(ids,k):
        if k==1:leaves.append(ids);return
        points=p[ids];dim=np.argmax(np.ptp(points,axis=0));left=k//2
        at=max(left,min(len(ids)-(k-left),int(round(len(ids)*left/k))))
        order=np.argpartition(points[:,dim],at-1);split(ids[order[:at]],left);split(ids[order[at:]],k-left)
    for ids,k in zip(groups,allocation):split(ids,int(k))
    result=np.empty((variants,budget),dtype='<u4')
    for j,ids in enumerate(leaves):
        points=p[ids];center=points.mean(0);d=np.sum((points-center)**2,axis=1)
        nearest=ids[np.argsort(d,kind='stable')[:min(variants,len(ids))]]
        for v in range(variants):result[v,j]=nearest[(j+v)%len(nearest)]
    return result

def selection_metrics(samples,ids):
    a=require_bank(samples);tree=cKDTree(a[np.asarray(ids),:3].astype(float));d,nearest=tree.query(a[:,:3],workers=1)
    selected=a[np.asarray(ids)[nearest]]
    return {'count':len(ids),'distance_p95_m':float(np.quantile(d,.95)),'distance_p99_m':float(np.quantile(d,.99)),
            'distance_max_m':float(d.max()),'rgb_mean':selected[:,12:15].mean(0).astype(float).tolist(),
            'normal_agreement_mean':float(np.sum(a[:,4:7]*selected[:,4:7],axis=1).mean())}

def append_bvh(nodes,refs,low,high,primitive_ids,leaf_size=8):
    """Depth-first stackless BVH. lo.w=escape; hi.w=leaf-list offset/EMPTY."""
    low=np.asarray(low,dtype=float);high=np.asarray(high,dtype=float);ids=np.asarray(primitive_ids,dtype=np.uint32)
    if low.shape!=high.shape or low.shape!=(len(ids),3) or not np.isfinite(low).all() or not np.isfinite(high).all() or (low>high).any():raise ValueError('BVH bounds')
    centers=(low+high)*.5
    def visit(which):
        index=len(nodes);nodes.append(None);lo=low[which].min(0);hi=high[which].max(0)
        if len(which)<=leaf_size:
            first=len(refs);refs.extend([len(which),*ids[which].astype(int).tolist()])
        else:
            dim=np.argmax(np.ptp(centers[which],axis=0));mid=len(which)//2
            order=np.argpartition(centers[which,dim],mid-1)
            visit(which[order[:mid]]);visit(which[order[mid:]]);first=EMPTY
        nodes[index]=(lo,hi,len(nodes),first)
        return index
    return visit(np.arange(len(ids)))

def pack_nodes(nodes):
    return b''.join(struct.pack('<3fI3fI',*np.nextafter(np.asarray(lo,dtype='<f4'),np.float32(-np.inf)),int(escape),*np.nextafter(np.asarray(hi,dtype='<f4'),np.float32(np.inf)),int(first)) for lo,hi,escape,first in nodes)

def compile_blas(samples,ranges):
    a=require_bank(samples);nodes=[];refs=[];roots=[]
    for start,count in ranges:
        if not 0<=start<len(a) or not 1<=count<=len(a)-start:raise ValueError('BLAS source range')
        source=a[start:start+count];p=source[:,:3].astype(float);r=source[:,3,None].astype(float)
        root=append_bvh(nodes,refs,p-r,p+r,np.arange(start,start+count,dtype=np.uint32))
        roots.append({'root':root,'start':start,'count':count,'low':(p-r).min(0).tolist(),'high':(p+r).max(0).tolist()})
    return pack_nodes(nodes),np.asarray(refs,dtype='<u4').tobytes(),roots

def compile_scene(instances,roots):
    if not 1<=len(instances)<=1024:raise ValueError('scene instance count')
    records=[];low=[];high=[]
    for item in instances:
        rid=item['root'];m=np.asarray(item['matrix'],dtype=float)
        if type(rid) is not int or not 0<=rid<len(roots) or m.shape!=(4,4) or not np.isfinite(m).all() or not np.allclose(m[3],[0,0,0,1]) or abs(np.linalg.det(m[:3,:3]))<1e-10:raise ValueError('scene affine transform')
        inverse=np.linalg.inv(m);root=roots[rid]
        corners=np.array([[x,y,z,1.] for x in [root['low'][0],root['high'][0]] for y in [root['low'][1],root['high'][1]] for z in [root['low'][2],root['high'][2]]])@m.T
        low.append(corners[:,:3].min(0));high.append(corners[:,:3].max(0))
        records.append(inverse[:3].astype('<f4').tobytes()+struct.pack('<4I',root['root'],root['start'],root['count'],rid))
    nodes=[];refs=[];append_bvh(nodes,refs,np.array(low),np.array(high),np.arange(len(instances),dtype=np.uint32),leaf_size=1)
    node_data=pack_nodes(nodes);ref_data=np.asarray(refs,dtype='<u4').tobytes()
    ref_offset=4+len(node_data)//4;instance_offset=(ref_offset+len(refs)+3)//4*4
    return struct.pack('<4I',len(nodes),ref_offset,instance_offset,len(instances))+node_data+ref_data+b'\0'*(4*(instance_offset-ref_offset-len(refs)))+b''.join(records)

def brute_hit(samples,instances,roots,origin,direction,limit,minimum=.0003,skip_instance=-1,skip_source=-1):
    """Independent float64 oracle: enumerate all source disks, no BVH walk."""
    nearest=float(limit);origin=np.asarray(origin,float);direction=np.asarray(direction,float)
    for j,item in enumerate(instances):
        inv=np.linalg.inv(np.asarray(item['matrix'],float));o=(inv@np.r_[origin,1.])[:3];d=inv[:3,:3]@direction
        root=roots[item['root']];a=samples[root['start']:root['start']+root['count']].astype(float)
        # Independent segment-AABB rejection; every remaining disk is tested.
        # No BVH nodes, traversal order or cached visibility are used here.
        endpoint=o+d*nearest
        if (np.maximum(o,endpoint)<np.array(root['low'])).any() or (np.minimum(o,endpoint)>np.array(root['high'])).any():continue
        denom=a[:,4:7]@d
        t=np.divide(np.sum((a[:,:3]-o)*a[:,4:7],axis=1),denom,out=np.full(len(a),-1.),where=abs(denom)>1e-8)
        hit=o+t[:,None]*d;delta=hit-a[:,:3]
        valid=(t>minimum)&(t<nearest)&(np.sum(delta*delta,axis=1)<=a[:,3]**2)
        if j==skip_instance and root['start']<=skip_source<root['start']+root['count']:valid[skip_source-root['start']]=False
        if valid.any():nearest=min(nearest,float(t[valid].min()))
    return nearest

def reference_rays(samples,instances,roots,queries):
    values=[]
    for q in queries:
        p=np.array(q['point']);n=np.array(q['normal']);delta=np.array(q['light'])-p;distance=np.linalg.norm(delta);bias=q.get('bias',.0003);reach=min(q.get('reach',.025),distance-bias)
        if distance<=bias or n@delta<=0:values.append(1.);continue
        t=brute_hit(samples,instances,roots,p+n*bias,delta/distance,reach,bias,q.get('instance',-1),q.get('source',-1))
        u=np.clip((t-.75*reach)/(.25*reach),0,1);values.append(float(u*u*(3-2*u)))
    return values
