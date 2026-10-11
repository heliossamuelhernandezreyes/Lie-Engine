"""Offline anatomical rig contract. Lie coordinates are metres, Y up.

Weights are a two-bone smooth distance field; the skeleton layer is rigid.
This is an authored game rig, not a physiological muscle simulation.
"""
import numpy as np

# Anchors fitted to the inspected humerus/ulna/femur/tibia bounds of the source.
def rig():
    result = [
        dict(name='pelvis', parent=-1, pivot=[0,.87,.075], end=[0,.99,.075], band=.075),
        dict(name='torso', parent=0, pivot=[0,1.00,.075], end=[0,1.43,.078], band=.10),
        dict(name='head', parent=1, pivot=[0,1.435,.078], end=[0,1.60,.10], band=.045),
    ]
    for side, sign in [('right',-1),('left',1)]:
        start=len(result)
        result += [
            dict(name=side+'_upper_arm',parent=1,pivot=[sign*.157,1.322,.071],end=[sign*.220,1.047,.071],band=.055),
            dict(name=side+'_forearm',parent=start,pivot=[sign*.220,1.047,.071],end=[sign*.264,.827,.100],band=.043),
            dict(name=side+'_hand',parent=start+1,pivot=[sign*.264,.827,.100],end=[sign*.295,.710,.121],band=.025),
        ]
    for side, sign in [('right',-1),('left',1)]:
        start=len(result)
        result += [
            dict(name=side+'_thigh',parent=0,pivot=[sign*.067,.824,.078],end=[sign*.078,.407,.071],band=.085),
            dict(name=side+'_shin',parent=start,pivot=[sign*.078,.407,.071],end=[sign*.075,.068,.060],band=.06),
            dict(name=side+'_foot',parent=start+1,pivot=[sign*.075,.068,.060],end=[sign*.075,.020,.173],band=.028),
        ]
    radii=[.115,.165,.09,.055,.045,.055,.055,.045,.055,.095,.060,.070,.095,.060,.070]
    for i,b in enumerate(result):b['id']=i;b['radius']=radii[i]
    return result

def line_distance(points, bone):
    a=np.asarray(bone['pivot']);d=np.asarray(bone['end'])-a
    t=np.clip((points-a)@d/np.dot(d,d),0,1)
    delta=points-a-t[:,None]*d
    length=np.linalg.norm(delta,axis=1)
    return length,delta/np.maximum(length[:,None],1e-9)

def bindings(points, bones, rigid=False):
    """Return parent, child, child weight and spatial weight gradient.

    In a segment interior weights saturate, giving exact rigid transforms.
    Only connected parent-child pairs may blend. Fields use metre distances.
    """
    p=np.asarray(points,dtype=np.float64).reshape(-1,3)
    distances=np.stack([line_distance(p,b)[0]-b['radius'] for b in bones],axis=1)
    owner=distances.argmin(axis=1)
    if rigid:return owner,owner,np.zeros(len(p)),np.zeros_like(p)
    first=owner.copy();second=owner.copy();weight=np.zeros(len(p));gradient=np.zeros_like(p)
    for i,b in enumerate(bones):
        ids=np.flatnonzero(owner==i)
        if not len(ids):continue
        adjacent=[j for j,c in enumerate(bones) if c['parent']==i]
        if b['parent']>=0:adjacent.append(b['parent'])
        neighbor=np.asarray(adjacent)[distances[ids][:,adjacent].argmin(axis=1)]
        for j in adjacent:
            selected=ids[neighbor==j]
            parent,child=(j,i) if b['parent']==j else (i,j)
            da,ga=line_distance(p[selected],bones[parent]);db,gb=line_distance(p[selected],bones[child])
            da-=bones[parent]['radius'];db-=bones[child]['radius']
            band=bones[child]['band'];t=np.clip(.5+(da-db)/(2*band),0,1)
            first[selected]=parent;second[selected]=child;weight[selected]=t*t*(3-2*t)
            gradient[selected]=(ga-gb)*(6*t*(1-t)/(2*band))[:,None]
    # The broad torso capsule must not capture the face/eyes. Cranial tissue
    # attaches rigidly above the neck; only the cervical band blends.
    neck=(p[:,1]>1.36)&(np.abs(p[:,0])<.11)
    t=np.clip((p[neck,1]-1.36)/.08,0,1)
    first[neck]=1;second[neck]=2;weight[neck]=t*t*(3-2*t)
    gradient[neck]=0;gradient[neck,1]=6*t*(1-t)/.08
    return first,second,weight,gradient

def skeleton_owner(name, center, bones):
    side='right' if 'right' in name else 'left' if 'left' in name else ''
    suffix=None
    if side:
        if 'humerus' in name:suffix='upper_arm'
        elif 'radius' in name or 'ulna' in name:suffix='forearm'
        elif 'femur' in name or 'patella' in name:suffix='thigh'
        elif 'tibia' in name or 'fibula' in name:suffix='shin'
        elif any(v in name for v in ['tars','talus','calcane','navicular','cuboid','cuneiform','metatars','toe']):suffix='foot'
        elif any(v in name for v in ['carpal','metacarp','phalan','finger','trapez','scaphoid','lunate','pisiform','capitate','hamate']):suffix='hand' if center[1]>.5 else 'foot'
        elif 'scapula' in name or 'clavicle' in name:return 1
        elif 'hip bone' in name:return 0
    if suffix:return next(b['id'] for b in bones if b['name']==side+'_'+suffix)
    if 'vertebra' in name or 'rib' in name or 'sternum' in name:
        return 0 if center[1]<1 else 1
    return int(bindings([center],bones,True)[0][0])

CASES=[
    dict(name='rest',pose={},camera_yaw=0,mask=15),
    dict(name='elbow',pose={'right_elbow':110,'left_elbow':75},camera_yaw=35,mask=15),
    dict(name='step',pose={'right_hip':30,'right_knee':55,'left_hip':-15,'left_knee':12,'right_shoulder':-15,'left_shoulder':20,'head_yaw':20},camera_yaw=-25,mask=15),
    dict(name='reach',pose={'right_shoulder':50,'right_elbow':60,'left_abduction':60,'left_elbow':80,'torso_bend':12},camera_yaw=20,mask=15),
    dict(name='bones',pose={'right_elbow':110,'left_knee':55,'left_hip':30},camera_yaw=35,mask=4),
]
