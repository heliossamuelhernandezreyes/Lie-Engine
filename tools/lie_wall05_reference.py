"""Independent float64 oracle for the actual 872-patch opaque optical bridge."""
import json,math,sys
from pathlib import Path
import numpy as np
from lie35_directional_reference import budgets
ROOT=Path(__file__).resolve().parents[1]

def unit(v):
    length=np.linalg.norm(v)
    return np.asarray(v,dtype=float)/length if length>1e-10 else np.zeros(3)

def blocked(a,b,boxes,planes,owner):
    d=b-a
    for k,(low,high) in enumerate(boxes):
        if k==owner:continue
        near,far=.001,.999
        for axis in range(3):
            if abs(d[axis])<1e-8:
                if a[axis]<low[axis] or a[axis]>high[axis]:near,far=1,0;break
            else:
                u,v=(low[axis]-a[axis])/d[axis],(high[axis]-a[axis])/d[axis]
                near=max(near,min(u,v));far=min(far,max(u,v))
        if near<=far:
            plane=planes[k];side=np.dot(plane[:3],a)-plane[3];rate=np.dot(plane[:3],d)
            if abs(rate)<1e-9:
                if side>0:near,far=1,0
            elif rate>0:far=min(far,-side/rate)
            else:near=max(near,-side/rate)
        if near<=far:return True
    return False

def reference(root=ROOT/'gpu_compute/captures/liewall05', model_path=None):
    root=Path(root);cat=json.loads((root/'catalog.json').read_text())
    model=json.loads((Path(model_path) if model_path else ROOT/'gpu_compute/assets/lie_wall04/light-model.json').read_text())
    patch=model['patches'];n=len(patch)
    p=np.asarray([x['position'] for x in patch],float);normals=np.asarray([x['normal'] for x in patch],float);areas=np.asarray([x['area'] for x in patch])
    size=cat['masters']['real_scan_wall']['bounds_size'];center=np.asarray(cat['masters']['real_scan_wall']['bounds_center']);reach=max(1.,size[0]*.48)
    theta=math.radians(-24);lamp=center+np.array([math.sin(theta)*reach,.78,math.cos(theta)*reach+.25]);power=np.array([55.,55.*.93,55.*.86])
    planes=np.fromfile(root/'shadow-caps.bin',dtype='<f4').reshape(-1,4).astype(float);boxes=np.asarray(model['direct_shadow_boxes'])
    optics=np.fromfile(root/'optics.bin',dtype='<f4')[4:].reshape(n,16).astype(float)
    weights=[];travel=[]
    for i in range(n):
        delta=lamp-p[i];d2=np.dot(delta,delta);cosine=max(np.dot(normals[i],unit(delta)),0);fade=max(0,1-(math.sqrt(d2)/6.)**4)**2
        w=areas[i]*cosine*fade/(4*math.pi*max(d2,.0025))
        if blocked(p[i],lamp,boxes,planes,i//9 if i<864 else -1):w=0.
        weights.append(w);travel.append(unit(p[i]-lamp))
    weights=np.array(weights);incoming=weights[:,None]*power/max(1.,weights.sum());total=incoming.copy();travel=np.array(travel)
    packet=np.fromfile(root/'outgoing-csr.bin',dtype='<u4');ob,eb=map(int,packet[2:4]);adj=[]
    for src in range(n):
        row=[]
        for e in range(int(packet[ob+src]),int(packet[ob+src+1])):
            dst=int(packet[eb+e*2]);F=float(packet[eb+e*2+1:eb+e*2+2].view('<f4')[0]);row.append((dst,F))
        adj.append(row)
    generations=[incoming.sum(0).tolist()]
    for generation in range(2):
        next_power=np.zeros((n,3));next_direction=np.zeros((n,3))
        for src in range(n):
            o=optics[src];nvec=unit(o[12:15]);inc=unit(travel[src]);rough=max(o[3],.025);expo=min(2048.,max(1.,2/rough**2-2))
            source={'normal':nvec.tolist(),'incident':inc.tolist(),'albedo':o[:3].tolist(),'roughness':rough,'metallic':o[4],'transmission':0.,'ior':o[6],'sigma':[0.,0.,0.],'thickness':0.}
            parts,_,_,_=budgets(source);parts=np.asarray(parts[:2])
            mirrored=unit(inc-2*np.dot(inc,nvec)*nvec)
            links=[]
            for dst,F in adj[src]:
                direction=unit(p[dst]-p[src]);base=max(np.dot(normals[src],direction),1e-6);cosine=max(np.dot(nvec,direction),0)
                glossy=max(np.dot(mirrored,direction),0)**expo if cosine>0 else 0.
                links.append((dst,direction,F*np.array([cosine,glossy])/base))
            caps=np.maximum(1.,sum((x[2] for x in links),np.zeros(2)))
            for dst,direction,w in links:
                flux=incoming[src]*((w/caps)@parts);next_power[dst]+=flux;next_direction[dst]+=direction*float(flux.max())
        if (next_power.sum(0)>incoming.sum(0)+1e-8).any():raise AssertionError('Passive frontier energy bound')
        incoming=next_power;total+=incoming;generations.append(incoming.sum(0).tolist())
        travel=np.array([unit(v) if np.linalg.norm(v)>1e-8 else -normals[i] for i,v in enumerate(next_direction)])
    return {'schema':'wall05-scene-optical/1','source_bank_sha256':cat['sha256'],'state':{'light_azimuth':-24,'light_power':1,'clay_absorption':0,'energy_radius':False,'scan_shadows':True,'optical_codes':True},'flux':total.tolist(),'generation_totals_rgb':generations,'lamp_power_rgb':power.tolist(),'reference':'float64 independent LIE35 budgets on captured opaque CSR; no refractive graph'}
def write(root=ROOT/'gpu_compute/captures/liewall05'):
    result=reference(root);path=ROOT/'gpu_compute/fixtures/wall05-neutral-reference.json';path.parent.mkdir(parents=True,exist_ok=True);path.write_text(json.dumps(result,indent=2)+'\n');return result
if __name__=='__main__':print(json.dumps({'generation_totals_rgb':write()['generation_totals_rgb']}))
