"""Float64 robot hierarchy, oriented-box lighting proxies and material contract."""
import math
from lie_rigid_master import rotation_z,rotation_x,compose,transform
PARTS=15

def skeleton(phase=0., pose=False):
    if not math.isfinite(phase): raise ValueError('Finite phase required')
    eye=[[1,0,0],[0,1,0],[0,0,1]]; out=[]
    def part(name,origin,scale,basis=eye,material='steel',parent=-1,pivot=None):
        out.append({'name':name,'origin':origin,'basis':[[c[k]*scale[j] for k in range(3)] for j,c in enumerate(basis)],'scale':scale,'rotation':basis,'material':material,'parent':parent,'pivot':pivot or origin})
        return len(out)-1
    part('Torso',[0,.55,0],[.72,.82,.42],material='paint')
    headbasis=compose(rotation_z(.08*math.sin(phase)),[[math.cos(.25*math.sin(phase)),0,-math.sin(.25*math.sin(phase))],[0,1,0],[math.sin(.25*math.sin(phase)),0,math.cos(.25*math.sin(phase))]])
    part('Head',[0,1.25,0],[.58,.46,.46],headbasis,parent=0)
    part('Pelvis',[0,-.025,0],[.55,.30,.36],material='dark',parent=0)
    for side in [-1,1]:
        pivot=[side*.50,.87,0]
        a=-side*(.10+(.65 if pose else .45*math.sin(phase)))
        basis=compose(rotation_z(a),rotation_x(.15*math.sin(phase)))
        u=part('UpperArm'+str(side),transform([0,-.275,0],basis,pivot),[.23,.55,.26],basis,parent=0,pivot=pivot)
        elbow=transform([0,-.55,0],basis,pivot); lower=compose(basis,rotation_x(-(.65 if pose else .3+.25*math.cos(phase))))
        part('Forearm'+str(side),transform([0,-.25,0],lower,elbow),[.22,.50,.25],lower,parent=u,pivot=elbow)
    for side in [-1,1]:
        hip=[side*.18,-.17,0]; basis=rotation_x(side*(.3 if pose else .22*math.sin(phase)))
        t=part('Thigh'+str(side),transform([0,-.21,0],basis,hip),[.25,.42,.28],basis,parent=2,pivot=hip)
        knee=transform([0,-.42,0],basis,hip); lower=compose(basis,rotation_x(-(.35 if pose else .12*(1+math.sin(phase)))))
        s=part('Shin'+str(side),transform([0,-.21,0],lower,knee),[.23,.42,.25],lower,parent=t,pivot=knee)
        ankle=transform([0,-.42,0],lower,knee)
        part('Foot'+str(side),transform([0,-.01,.1],lower,ankle),[.30,.16,.44],lower,material='dark',parent=s,pivot=ankle)
    for side in [-1,1]:
        part('Eye'+str(side),transform([side*.14,.03,.245],headbasis,[0,1.25,0]),[.10,.10,.065],headbasis,material='eye',parent=1)
    assert len(out)==PARTS
    return out

def blocked(a,b,instances):
    for part in instances:
        columns=part['basis']; lengths=[sum(v*v for v in c) for c in columns]
        q=[a[k]-part['origin'][k] for k in range(3)]; delta=[b[k]-a[k] for k in range(3)]
        p=[sum(c[k]*q[k] for k in range(3))/lengths[j] for j,c in enumerate(columns)]
        d=[sum(c[k]*delta[k] for k in range(3))/lengths[j] for j,c in enumerate(columns)]
        low,high=.001,.999
        for axis in range(3):
            if abs(d[axis])<1e-10:
                if abs(p[axis])>.5: low,high=1,0; break
            else:
                u,v=(-.5-p[axis])/d[axis],(.5-p[axis])/d[axis]
                low=max(low,min(u,v)); high=min(high,max(u,v))
        if low<=high: return True
    return False

def normal_world(n,instance):
    basis=instance['basis']; lengths=[sum(v*v for v in c) for c in basis]
    v=[sum(n[j]*basis[j][k]/lengths[j] for j in range(3)) for k in range(3)]
    length=math.sqrt(sum(c*c for c in v))
    return [c/length for c in v]

def materials(name='bounce'):
    return {'steel':{'tint_linear':[.62,.78,.95],'absorption_code':150,'roughness':.34,'metallic':.85,'emission':0},
            'paint':{'tint_linear':[.9,.15,.07],'absorption_code':900 if name=='absorbing' else 200,'roughness':.5,'metallic':.12,'emission':0},
            'dark':{'tint_linear':[.12,.18,.23],'absorption_code':400,'roughness':.6,'metallic':.4,'emission':0},
            'eye':{'tint_linear':[.04,.8,1],'absorption_code':100,'roughness':.3,'metallic':0,'emission':.65},
            'room':{'tint_linear':[.7,.8,.9],'absorption_code':300,'roughness':.9,'metallic':0,'emission':0}}

def scene_model(master,name='bounce',phase=0):
    instances=skeleton(phase,name=='pose'); mats=materials(name); patches=[]
    for s in instances:
        for p in master['patches']:
            axis=max(range(3),key=lambda k:abs(p['normal'][k])); others=[k for k in range(3) if k!=axis]
            patches.append({**p,'position':transform(p['position'],s['basis'],s['origin']),'normal':normal_world(p['normal'],s),'area':s['scale'][others[0]]*s['scale'][others[1]],'material':s['material']})
    for wall in [False,True]:
        for row in range(4):
            for col in range(4):
                patches.append({'position':[-2+col+.5,-1+row+.5,-2] if wall else [-2+col+.5,-1.05,-2+row+.5], 'normal':[0,0,1] if wall else [0,1,0],'area':1,'gray_mean':.7,'material':'room'})
    n=len(patches); visibility=[0]*(n*n)
    for i in range(n):
        for j in range(i+1,n):
            a=[patches[i]['position'][k]+patches[i]['normal'][k]*.003 for k in range(3)]
            b=[patches[j]['position'][k]+patches[j]['normal'][k]*.003 for k in range(3)]
            value=int(not blocked(a,b,instances)); visibility[i*n+j]=visibility[j*n+i]=value
    # Only the diffuse fraction becomes a secondary emitter. Metallic reflection
    # is evaluated on visible pixels; no fictitious diffuse metallic bounce.
    transport_mats={k:{**v,'tint_linear':[c*(1-v['metallic']) for c in v['tint_linear']]} for k,v in mats.items()}
    model={'schema':1,'patches':patches,'factor_normalization':'symmetric_local','materials':transport_mats,'surface_materials':mats,'lights':[{'position':[1.6,2,1.5] if name=='light' else [-1.7,2.3,1.8],'power_rgb':[0,0,0] if name=='dark' else [130,115,95],'radius':7},{'position':[1.5,.8,-.5],'power_rgb':[0,0,0] if name=='dark' else [24,40,65],'radius':5}], 'bounces':0 if name=='direct' else 2,'blockers':[],'mesh_visibility':visibility,'secondary_radii':{'radius_max':4,'radius_decay':.82,'power_reference':.03}}
    return model,instances
