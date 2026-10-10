"""Independent float64 radiometry and exact ORIGINAL-MESH camera-ray oracle.
Geometry uses source triangles rather than perception boxes or captured points.
"""
import json,math,struct,sys
from pathlib import Path
import numpy as np
import lie_light_transport as transport
from lie15_robot import scene_model,blocked,normal_world,PARTS
from lie_rigid_master import transform

def light_weight(patch,light,instances):
    p=np.array(patch['position']); n=np.array(patch['normal']); delta=np.array(light['position'])-p; d2=delta@delta
    if d2<1e-10 or blocked(p+n*.003,light['position'],instances): return 0.
    cosine=max(n@delta/math.sqrt(d2),0); window=max(0,1-(math.sqrt(d2)/light['radius'])**4)**2
    return patch['area']*cosine*window/(4*math.pi*max(d2,.0025))

def display(s,instance,index,model,result,caps,eye):
    p=np.array(transform(s[:3],instance['basis'],instance['origin'])); n=np.array(normal_world(s[4:7],instance)); v=np.array(eye)-p; v/=np.linalg.norm(v)
    m=model['surface_materials'][instance['material']]; base=s[3]*np.array(m['tint_linear']); f0=(1-m['metallic'])*.04+m['metallic']*base
    nv=max(n@v,1e-5); alpha=max(m['roughness']**2,.02); a2=alpha*alpha; direct=np.zeros(3); spec=np.zeros(3)
    lam=lambda c:.5*(math.sqrt(1+a2*max(1-c*c,0)/max(c*c,1e-8))-1)
    for l,light in enumerate(model['lights']):
        d=np.array(light['position'])-p; d2=d@d; wi=d/math.sqrt(d2); nl=max(n@wi,0)
        if nl<=0 or blocked(p+n*.003,light['position'],[part for j,part in enumerate(model['_instances']) if j!=index]): continue
        li=np.array(light['power_rgb'])*max(0,1-(math.sqrt(d2)/light['radius'])**4)**2/(4*math.pi*max(d2,.0025)*caps[l]); direct+=li*nl
        h=v+wi; h/=np.linalg.norm(h); nh=max(n@h,0); vh=max(v@h,0)
        D=a2/(math.pi*(nh*nh*(a2-1)+1)**2); G=1/(1+lam(nv)+lam(nl)); F=f0+(1-f0)*(1-vh)**5
        spec+=li*F*D*G/(4*nv)
    node=int(s[7])+index*6
    indirect=np.maximum(np.array(result['irradiance'][node])-np.array(result['direct_flux'][node])/model['patches'][node]['area'],0)
    F=f0+(1-f0)*(1-max(n@v,0))**5
    radiance=((1-F)*(1-m['metallic'])*base*(direct+indirect)/math.pi+spec)*(1-m['absorption_code']/1000)+base*m['emission']
    return {'node':node,'direct':direct.tolist(),'display':(radiance/(1+radiance)).tolist()}

def camera(yaw=24,elevation=10,scale=1,size=384):
    yaw,el=math.radians(yaw),math.radians(elevation); target=np.array([0,.25,0.]); eye=target+np.array([math.sin(yaw)*math.cos(el),math.sin(el),math.cos(yaw)*math.cos(el)])*3.6*scale
    forward=(target-eye)/np.linalg.norm(target-eye); right=np.cross(forward,[0,1,0]); right/=np.linalg.norm(right); up=np.cross(right,forward)
    y,x=np.mgrid[:size,:size]; tan=math.tan(math.pi/6)
    rays=forward+(2*(x+.5)/size-1)[...,None]*tan*right+(1-2*(y+.5)/size)[...,None]*tan*up
    return eye,rays

def mesh_depth(instances,triangles,yaw=24,elevation=10,scale=1,size=384):
    eye,rays=camera(yaw,elevation,scale,size); rays=rays.reshape(-1,3); closest=np.full(size*size,np.inf); owners=np.full(size*size,255,dtype=np.uint8)
    for owner,s in enumerate(instances):
        columns=np.array(s['basis']); inverse=np.linalg.inv(columns.T); p=inverse@(eye-s['origin']); d=rays@inverse.T
        # Slab candidate mask limits triangle tests to projected perception box.
        low=np.full(len(d),.1); high=np.full(len(d),100.)
        for axis in range(3):
            divisor=np.where(abs(d[:,axis])<1e-12,1e-12,d[:,axis]); a=(-.5-p[axis])/divisor; b=(.5-p[axis])/divisor
            low=np.maximum(low,np.minimum(a,b)); high=np.minimum(high,np.maximum(a,b))
        indices=np.flatnonzero(low<=high); dr=d[indices]; local_depth=closest[indices].copy()
        for tri in triangles:
            a,b,c=np.array(tri); e1=b-a; e2=c-a; h=np.cross(dr,e2); det=h@e1
            divisor=np.where(abs(det)>1e-10,det,1e-10); tvec=p-a; u=h@tvec/divisor; q=np.cross(tvec,e1); v=dr@q/divisor; t=e2@q/divisor
            valid=(abs(det)>1e-10)&(u>=0)&(u<=1)&(v>=0)&(u+v<=1)&(t>.1)&(t<local_depth)
            local_depth[valid]=t[valid]
        changed=local_depth<closest[indices]; closest[indices[changed]]=local_depth[changed]; owners[indices[changed]]=owner
    for owner in [PARTS,PARTS+1]:
        axis=1 if owner==PARTS else 2; coordinate=-1.05 if axis==1 else -2
        t=(coordinate-eye[axis])/np.where(abs(rays[:,axis])<1e-12,1e-12,rays[:,axis]); p=eye+rays*t[:,None]
        inside=abs(p[:,0])<=2; inside&=abs(p[:,2])<=2 if axis==1 else ((p[:,1]>=-1)&(p[:,1]<=3))
        update=inside&(t>.1)&(t<closest)&(eye[axis]>coordinate); closest[update]=t[update]; owners[update]=owner
    closest[~np.isfinite(closest)]=0
    return closest.reshape(size,size),owners.reshape(size,size)

def main(root):
    master=json.loads((root/'master.json').read_text()); samples=list(struct.iter_unpack('<8f',(root/'master-samples.bin').read_bytes())); result={'schema':1,'scenarios':{},'geometry':{}}
    for name in ['direct','bounce','pose','light','absorbing','dark']:
        model,instances=scene_model(master,name); old=transport.light_weight
        try:
            transport.light_weight=lambda patch,light,blockers,triangles=(): light_weight(patch,light,instances)
            solution=transport.solve(model,bounces=model['bounces'])
        finally: transport.light_weight=old
        caps=[max(1,sum(light_weight(p,l,instances) for p in model['patches'])) for l in model['lights']]
        model['_instances']=instances; eye,_=camera()
        probes=[display(samples[sample],s,i,model,solution,caps,eye) for i,s in enumerate(instances) for sample in master['probe_samples']]
        result['scenarios'][name]={'irradiance':solution['irradiance'],'probes':probes,'instances':instances,'energy_by_generation':solution['energy_by_generation']}
    triangles=json.loads((root.parents[1]/'assets/lie15/source-triangles.json').read_text())
    for name,yaw,el,scale,pose in [('base',24,10,1,'bounce'),('front',0,10,1,'bounce'),('pose',24,10,1,'pose'),('orbit',110,10,1,'bounce'),('high',35,65,1,'bounce'),('close',24,10,.7,'bounce'),('far',24,10,1.5,'bounce')]:
        depth,owners=mesh_depth(result['scenarios'][pose]['instances'],triangles,yaw,el,scale)
        (root/f'reference-{name}-depth.bin').write_bytes(depth.astype('<f4').tobytes()); (root/f'reference-{name}-owners.bin').write_bytes(owners.tobytes())
        result['geometry'][name]={'yaw':yaw,'elevation':el,'distance_scale':scale,'pose':pose}
    (root/'robot-reference.json').write_text(json.dumps(result,indent=2)+'\n'); print('LIE15 FLOAT64',len(result['scenarios']),'radiometry',len(result['geometry']),'actual-source mesh cameras')
if __name__=='__main__': main(Path(sys.argv[1]))
