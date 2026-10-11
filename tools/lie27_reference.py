"""Independent NumPy FK and source-space probes for the region GPU contract."""
import argparse,json,math
from pathlib import Path
import numpy as np
from lie27_regions import deform_face,FACIAL_KEYS

def qmul(a,b):
    return np.r_[a[3]*b[:3]+b[3]*a[:3]+np.cross(a[:3],b[:3]),a[3]*b[3]-a[:3]@b[:3]]

def axis_angle(axis,angle):
    a=np.asarray(axis,dtype=float);a/=np.linalg.norm(a);t=math.radians(angle)*.5
    return np.r_[a*math.sin(t),math.cos(t)]

def rotate(q,p):
    return p+2*np.cross(q[:3],np.cross(q[:3],p)+q[3]*p)

def fk(bones,pose):
    qs=[];os=[];dq=[]
    for b in bones:
        x=y=z=0;name=b['name'];pivot=np.asarray(b['pivot']);parent=b['parent']
        if 'control' in b:local=axis_angle(b['axis'],pose.get(b['control'],0)*b['gain'])
        else:
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
            local=qmul(qmul(axis_angle([0,1,0],y),axis_angle([0,0,1],z)),axis_angle([1,0,0],x))
        q=local if parent<0 else qmul(qs[parent],local)
        o=pivot+np.asarray(pose.get('root_position',[0,0,0])) if parent<0 else os[parent]+rotate(qs[parent],pivot-np.asarray(bones[parent]['pivot']))
        t=o-rotate(q,pivot);d=.5*qmul(np.r_[t,0],q);qs.append(q);os.append(o);dq.append([q,d])
    return np.asarray(dq),np.asarray(os),np.asarray(qs)

def skin(p,a,b,w,dq):
    r0,d0=dq[int(a)];r1,d1=dq[int(b)]
    if r0@r1<0:r1=-r1;d1=-d1
    r=r0*(1-w)+r1*w;d=d0*(1-w)+d1*w;n=np.linalg.norm(r);r/=n;d/=n
    translation=2*qmul(d,np.r_[-r[:3],r[3]])[:3]
    return rotate(r,np.asarray(p))+translation

CASES=[
    dict(name='neutral',pose={},face={}),
    dict(name='closed',pose={},face={'blink_left':1,'blink_right':1}),
    dict(name='wink',pose={},face={'blink_left':1}),
    dict(name='smile',pose={},face={'smile':1}),
    dict(name='frown',pose={},face={'frown':1,'brow_down':1}),
    dict(name='surprise',pose={},face={'brow_up':1,'jaw_open':1}),
    dict(name='head_turn',pose={'head_yaw':25,'head_pitch':15},face={}),
    dict(name='head_turn_closed',pose={'head_yaw':25,'head_pitch':15},face={'blink_left':1,'blink_right':1}),
    dict(name='fist',pose={'right_index':65,'right_middle':70,'right_ring':70,'right_little':70,'right_thumb':25},face={}),
]

def main():
    p=argparse.ArgumentParser();p.add_argument('root',type=Path);p.add_argument('--fixture',type=Path);args=p.parse_args();root=args.root;m=json.loads((root/'master.json').read_text())
    data=np.fromfile(root/'samples.bin',dtype='<f4').reshape(-1,20);v=np.fromfile(root/'vertices.bin',dtype='<f4').reshape(-1,24);tri=np.fromfile(root/'triangles.bin',dtype='<u4').reshape(-1,4)
    groups=[np.flatnonzero((data[:,3]>=15)&(data[:,3]<45)),np.flatnonzero((data[:,3]>=0)&(data[:,15]==0)&(data[:,1]>1.44)),np.flatnonzero(data[:,3]<-6154)]
    ids=np.unique(np.concatenate([g[np.linspace(0,len(g)-1,min(40,len(g)),dtype=int)] for g in groups if len(g)]));results=[];fixture=[]
    for case in CASES:
        dq,origins,rotations=fk(m['bones'],case['pose']);values=[case['face'].get(key,0) for key in FACIAL_KEYS]
        posed=[]
        for vert in v:
            point=vert[:3].astype(float)
            if vert[15]==1:
                blink=values[1-int(vert[11])];point+=vert[8:11]*blink+vert[12:15]*4*blink*(1-blink)
            point=deform_face([point],m['facial_regions'],values)[0][0]
            posed.append(skin(point,vert[3],vert[4],vert[5],dq))
        posed=np.asarray(posed);points=[]
        for index in ids:
            s=data[index]
            if s[3]<0:point=s[:3]@posed[tri[int(-s[3])-1,:3]]
            else:
                point=s[:3].astype(float)
                if s[15]<2:point=deform_face([point],m['facial_regions'],values)[0][0]
                point=skin(point,s[3],s[14],s[13],dq)
            points.append(point.tolist())
        results.append(dict(case,positions=points));fixture.append(dict(name=case['name'],pose=case['pose'],origins=origins.tolist(),rotations=rotations.tolist()))
        print('REFERENCE27',case['name'],len(ids),flush=True)
    (root/'region-probes.json').write_text(json.dumps(dict(indices=ids.tolist(),cases=results),indent=2)+'\n')
    if args.fixture:args.fixture.write_text(json.dumps(dict(bones=m['bones'],cases=fixture,credit=m['credit'],license=m['license']),indent=2)+'\n')

if __name__=='__main__':main()
