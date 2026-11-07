"""Shading-only normals. Visibility, coverage and shadows keep geometry normals."""
import hashlib
import numpy as np
from lie_heightfield_source import sample_array
def unit(v):return v/np.maximum(np.linalg.norm(v,axis=-1,keepdims=True),1e-12)
def sample_optical(mesh,uv,faces,geometry):
    image=mesh.metadata.get('lie_optical_normal_map')
    if image is None:return np.column_stack([geometry,np.zeros(len(geometry))]).astype('<f4')
    p=np.asarray(mesh.vertices)[faces];q=np.asarray(mesh.visual.uv)[faces]
    e1=p[:,1]-p[:,0];e2=p[:,2]-p[:,0];a=q[:,1]-q[:,0];b=q[:,2]-q[:,0];det=a[:,0]*b[:,1]-a[:,1]*b[:,0]
    if (abs(det)<1e-16).any():raise ValueError('optical_degenerate_uv')
    t=(e1*b[:,1,None]-e2*a[:,1,None])/det[:,None];bt=(-e1*b[:,0,None]+e2*a[:,0,None])/det[:,None]
    t=unit(t-geometry*(t*geometry).sum(-1,keepdims=True));sign=np.where((np.cross(geometry,t)*bt).sum(-1)<0,-1.,1.);bt=np.cross(geometry,t)*sign[:,None]
    s=unit(np.clip(sample_array(image,uv),0,1)*2-1);n=unit(t*s[:,0,None]+bt*s[:,1,None]+geometry*s[:,2,None])
    if not np.isfinite(n).all() or ((n*geometry).sum(-1)<-.02).any():raise ValueError('optical_hemisphere')
    return np.column_stack([n,np.ones(len(n))]).astype('<f4')
def inspect_optical(raw,base_sha,count):
    if len(raw)!=count*16:raise ValueError('optical_count')
    a=np.frombuffer(raw,dtype='<f4').reshape(-1,4)
    if not np.isfinite(a).all() or np.max(abs(np.linalg.norm(a[:,:3],axis=1)-1))>2e-4 or not np.isin(a[:,3],[0,1]).all():raise ValueError('optical_contract')
    return {'schema':'lie-optical-normal-sidecar/1','stride':16,'bytes':len(raw),'sample_count':count,'sha256':hashlib.sha256(raw).hexdigest(),'source_bank_sha256':base_sha,'file':'optical-normals.bin','role':'shading only; geometric visibility is unchanged'}
