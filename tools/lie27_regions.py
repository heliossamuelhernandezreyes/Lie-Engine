"""Compact spherical/ellipsoidal regions shared by body and facial authoring.

Coordinates are source-space metres. The identity outside a region and the
zero boundary gradient prevent a control from pulling an unrelated segment.
These are authored game controls, not measured physiological motion.
"""
import numpy as np
from lie26_motion import line_distance

def region(points, center, radii):
    p=np.asarray(points,dtype=np.float64).reshape(-1,3)
    r=np.asarray(radii,dtype=np.float64)
    if r.shape!=(3,) or not np.isfinite(r).all() or np.any(r<=0):
        raise ValueError('Positive finite region radii required')
    d=p-np.asarray(center);q=np.sum((d/r)**2,axis=1)
    t=np.maximum(1-q,0)
    return t**3,-6*t[:,None]**2*d/r**2

def joint_regions(bones):
    return [dict(name=b['name'],bone=b['id'],parent=b['parent'],center=b['pivot'],
                 radii=[b['band']*1.8]*3,kind='joint') for b in bones if b['parent']>=0]

def bindings(points,bones,rigid=False):
    p=np.asarray(points,dtype=np.float64).reshape(-1,3)
    distances=np.stack([line_distance(p,b)[0]-b['radius'] for b in bones],axis=1)
    owner=distances.argmin(axis=1)
    if rigid:return owner,owner,np.zeros(len(p)),np.zeros_like(p)
    first=owner.copy();second=owner.copy();weight=np.zeros(len(p));gradient=np.zeros_like(p)
    best=np.zeros(len(p))
    for b in bones:
        child=b['id'];parent=b['parent']
        if parent<0:continue
        influence,falloff_gradient=region(p,b['pivot'],[b['band']*1.8]*3)
        ids=np.flatnonzero((influence>best)&((owner==parent)|(owner==child)))
        if not len(ids):continue
        da,ga=line_distance(p[ids],bones[parent]);db,gb=line_distance(p[ids],b)
        da-=bones[parent]['radius'];db-=b['radius']
        t=np.clip(.5+(da-db)/(2*b['band']),0,1)
        mixed=t*t*(3-2*t);g=(ga-gb)*(6*t*(1-t)/(2*b['band']))[:,None]
        endpoint=(owner[ids]==child).astype(float);f=influence[ids]
        first[ids]=parent;second[ids]=child
        weight[ids]=endpoint+f*(mixed-endpoint)
        gradient[ids]=f[:,None]*g+(mixed-endpoint)[:,None]*falloff_gradient[ids]
        best[ids]=f
    # Preserve the delivered cranial ownership correction. Only the cervical
    # band blends; all facial/ocular surfaces above it follow the head.
    neck=(p[:,1]>1.36)&(np.abs(p[:,0])<.11)
    t=np.clip((p[neck,1]-1.36)/.08,0,1)
    first[neck]=1;second[neck]=2;weight[neck]=t*t*(3-2*t)
    gradient[neck]=0;gradient[neck,1]=6*t*(1-t)/.08
    return first,second,weight,gradient

FACIAL_KEYS=['blink_left','blink_right','smile','frown','brow_up','brow_down','jaw_open']

def facial_regions(eyes):
    result=[]
    for i,eye in enumerate(eyes):
        side='right' if eye[0]<0 else 'left'
        result.extend([
            dict(name=side+'_brow_up',center=[eye[0],eye[1]+.020,eye[2]+.014],radii=[.026,.013,.023],delta=[0,.005,0],channel=4,bone=2,kind='expression'),
            dict(name=side+'_brow_down',center=[eye[0],eye[1]+.020,eye[2]+.014],radii=[.026,.013,.023],delta=[0,-.004,.001],channel=5,bone=2,kind='expression'),
        ])
    for sign in [-1,1]:
        result.extend([
            dict(name=('right' if sign<0 else 'left')+'_smile',center=[sign*.022,1.484,.174],radii=[.030,.023,.030],delta=[sign*.006,.006,.001],channel=2,bone=2,kind='expression'),
            dict(name=('right' if sign<0 else 'left')+'_frown',center=[sign*.022,1.484,.174],radii=[.030,.023,.030],delta=[sign*.002,-.005,0],channel=3,bone=2,kind='expression'),
        ])
    result.append(dict(name='lower_face',center=[0,1.464,.162],radii=[.055,.040,.045],delta=[0,-.012,.002],channel=6,bone=2,kind='expression'))
    return result

def deform_face(points,zones,values):
    p=np.asarray(points,dtype=float).reshape(-1,3);out=p.copy();jac=np.repeat(np.eye(3)[None],len(p),axis=0)
    for z in zones:
        w,g=region(p,z['center'],z['radii']);delta=np.asarray(z['delta'])*values[z['channel']]
        out+=w[:,None]*delta;jac+=delta[None,:,None]*g[:,None,:]
    return out,jac
