"""Float64 articulated-light oracle and analytic camera-depth ground truth.

Visibility uses interval clipping, independently of the GPU side/cap solver.
The radiometry deliberately remains the existing bounded diffuse approximation.
"""
import json
import math
import struct
import sys
from pathlib import Path
import numpy as np
import lie_light_transport as transport
from lie_rigid_master import cylinder_blocked, scene_model, transform


def light_weight(patch, light, instances):
    p, n = patch["position"], patch["normal"]
    start = [p[k]+.003*n[k] for k in range(3)]
    delta = [light["position"][k]-p[k] for k in range(3)]
    d2 = sum(x*x for x in delta)
    if d2 < 1e-10 or cylinder_blocked(start, light["position"], instances):
        return 0
    cosine = max(sum(n[k]*delta[k] for k in range(3))/math.sqrt(d2), 0)
    window = max(0, 1-(math.sqrt(d2)/light["radius"])**4)**2
    return patch["area"]*cosine*window/(4*math.pi*max(d2,.0025))


def direct_at(p, normal, model, instances, caps):
    result = [0., 0., 0.]
    for index, light in enumerate(model["lights"]):
        patch = {"position": p, "normal": normal, "area": 1}
        weight = light_weight(patch, light, instances)/caps[index]
        for c in range(3): result[c] += light["power_rgb"][c]*weight
    return result


def solve_scene(master, samples, name):
    model, instances = scene_model(master, name)
    old_weight = transport.light_weight
    try:
        transport.light_weight = lambda patch, light, blockers, triangles=(): light_weight(patch, light, instances)
        result = transport.solve(model, bounces=model["bounces"])
    finally:
        transport.light_weight = old_weight
    caps = [max(1.,sum(light_weight(p, light, instances) for p in model["patches"])) for light in model["lights"]]
    probes = []
    for i, instance in enumerate(instances):
        material = model["materials"]["red" if i == 1 else "metal"]
        for sample_index in master["probe_samples"]:
            s = samples[sample_index]
            node = int(s[7])+i*18
            p = transform(s[:3], instance["basis"], instance["origin"])
            normal = transform(s[4:7], instance["basis"])
            direct = direct_at(p, normal, model, instances, caps)
            indirect = [max(0,result["irradiance"][node][c]-result["direct_flux"][node][c]/model["patches"][node]["area"]) for c in range(3)]
            rgb = [s[3]*material["tint_linear"][c]*(1-material["absorption_code"]/1000)*(direct[c]+indirect[c])/math.pi for c in range(3)]
            probes.append({"direct": direct,"display": [x/(1+x) for x in rgb],"node": node,"normal": normal,"position": p})
    return {"model": model,"instances": instances,"irradiance": result["irradiance"],
            "direct_flux":result["direct_flux"],"probes":probes,"caps":caps,
            "energy_by_generation":result["energy_by_generation"],
            "radius_by_generation":result["secondary_radius_by_generation"]}


def camera_depth(instances, yaw=0, elevation=12, scale=1, size=384):
    """Exact analytic ray/shape intersections: no source-view interpolation."""
    yaw, el = math.radians(yaw), math.radians(elevation)
    target=np.array([0,.5,0],dtype=np.float64)
    eye=target+np.array([math.sin(yaw)*math.cos(el),math.sin(el),math.cos(yaw)*math.cos(el)])*5.8*scale
    forward=(target-eye)/np.linalg.norm(target-eye)
    right=np.cross(forward,[0,1,0]); right/=np.linalg.norm(right)
    up=np.cross(right,forward)
    y,x=np.mgrid[:size,:size]
    tan=math.tan(math.pi/6)
    rays=forward[None,None,:]+((x+.5)/size*2-1)[...,None]*tan*right+ (1-(y+.5)/size*2)[...,None]*tan*up
    closest=np.full((size,size),np.inf,dtype=np.float64)
    owners=np.full((size,size),255,dtype=np.uint8)
    for owner,s in enumerate(instances):
        basis=np.array(s["basis"])
        p=basis@(eye-np.array(s["origin"]))
        d=rays@basis.T
        a=d[...,0]**2+d[...,2]**2
        b=2*(p[0]*d[...,0]+p[2]*d[...,2])
        c=p[0]**2+p[2]**2-s["radius"]**2
        disc=b*b-4*a*c
        roots=[(-b-np.sqrt(np.maximum(disc,0)))/(2*np.maximum(a,1e-16)),
               (-b+np.sqrt(np.maximum(disc,0)))/(2*np.maximum(a,1e-16))]
        for t in roots:
            valid=(disc>=0)&(a>1e-12)&(t>.1)&(np.abs(p[1]+t*d[...,1])<=s["half_height"])
            update=valid&(t<closest)
            closest[update]=t[update]; owners[update]=owner
        for sign in [-1,1]:
            denominator=np.where(np.abs(d[...,1])<1e-12,1e-12,d[...,1])
            t=(sign*s["half_height"]-p[1])/denominator
            radial=(p[0]+t*d[...,0])**2+(p[2]+t*d[...,2])**2
            valid=(np.abs(d[...,1])>1e-12)&(t>.1)&(radial<=s["radius"]**2)
            update=valid&(t<closest)
            closest[update]=t[update]; owners[update]=owner
    for owner in [3,4]:
        axis=1 if owner==3 else 2
        coordinate=-1.05 if owner==3 else -2
        denominator=np.where(np.abs(rays[...,axis])<1e-12,1e-12,rays[...,axis])
        t=(coordinate-eye[axis])/denominator
        p=eye+rays*t[...,None]
        inside=(np.abs(p[...,0])<=2)
        inside&=(np.abs(p[...,2])<=2) if owner==3 else ((p[...,1]>=-1)&(p[...,1]<=3))
        update=inside&(t>.1)&(t<closest)
        closest[update]=t[update]; owners[update]=owner
    closest[~np.isfinite(closest)]=0
    return closest,owners


def main(root):
    master=json.loads((root/"master.json").read_text())
    samples=list(struct.iter_unpack("<8f",(root/"master-samples.bin").read_bytes()))
    result={"schema":1,"reference_precision":"float64","scenarios":{},"geometry":{}}
    for name in ["direct","bounce","pose","light","absorbing","dark"]:
        scenario=solve_scene(master,samples,name)
        result["scenarios"][name]=scenario
    for name,yaw,elevation,scale,pose in [("base",0,12,1,"bounce"),("pose",0,12,1,"pose"),
        ("orbit",35,12,1,"bounce"),("high",35,65,1,"bounce"),("far",0,12,1.5,"bounce")]:
        depth,owners=camera_depth(result["scenarios"][pose]["instances"],yaw,elevation,scale)
        (root/("reference-"+name+"-depth.bin")).write_bytes(depth.astype("<f4").tobytes())
        (root/("reference-"+name+"-owners.bin")).write_bytes(owners.tobytes())
        result["geometry"][name]={"yaw":yaw,"elevation":elevation,"distance_scale":scale,"pose":pose,"size":384}
    (root/"rigid-reference.json").write_text(json.dumps(result,indent=2)+"\n")
    print("LIE-14 FLOAT64 REFERENCE",len(result["scenarios"]),"light cases",len(result["geometry"]),"analytic camera cases")


if __name__=="__main__": main(Path(sys.argv[1]))
