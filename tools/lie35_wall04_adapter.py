"""Construct LIE35 directional material codes from real, SHA-checked WALL04 samples.

The source scan's measured XYZ/normals/roughness/linear RGB are read from
its immutable 80-byte-per-sample hero LOD; missing metallic/IOR/transmission
are explicit authored clay defaults, not inferred from a photograph.
This makes a small GPU oracle fixture, NOT a live WALL04 lighting change.
"""
import hashlib
import json
import math
from pathlib import Path
import struct
import sys
import zlib

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/"tools"))
from lie35_directional_reference import normal,reflect,propagate,effective_radius

WALL=ROOT/"gpu_compute/assets/lie_wall04"
NODES=(5,6,7,8,14,15,16,17)


def extraction(directory=WALL, selected=NODES):
    directory=Path(directory)
    cat=json.loads((directory/"catalog.json").read_text())
    if cat.get("stride")!=80 or cat.get("collision",{}).get("spatial_envelope_count")!=1:
        raise ValueError("WALL04 80-byte one-envelope capture contract required")
    raw=zlib.decompress((directory/"wall_bank.zlib").read_bytes())
    if len(raw)!=cat["bytes"] or hashlib.sha256(raw).hexdigest()!=cat["sha256"]:
        raise ValueError("Immutable scan SHA-256 mismatch")
    hero=cat["masters"]["real_scan_wall"]["levels"][0]
    wanted={int(k) for k in selected}
    if len(wanted)!=len(selected) or not wanted or any(k<0 or k>=864 for k in wanted):
        raise ValueError("Select unique scanned brick material nodes only")
    acc={n:{"count":0,"p":[0.]*3,"n":[0.]*3,"rgb":[0.]*3,"rough":0.} for n in wanted}
    begin=hero["start"]*80
    end=(hero["start"]+hero["count"])*80
    for v in struct.iter_unpack("<20f",memoryview(raw)[begin:end]):
        node=int(round(v[9]))
        if node not in acc or abs(v[9]-node)>0.001 or abs(v[8]-3.0)>0.001:
            continue
        if v[6]<0.35:  # genuine exposed-front normals only
            continue
        a=acc[node]
        a["count"]+=1
        for i in range(3):
            a["p"][i]+=v[i]
            a["n"][i]+=v[4+i]
            a["rgb"][i]+=v[12+i]
        a["rough"]+=v[10]
    model=json.loads((directory/"light-model.json").read_text())
    lamp=model["lights"][0]
    emitters=[]
    for code in selected:
        a=acc[code]
        if a["count"]<25:raise ValueError("Missing real photographed front surface node: "+str(code))
        count=a["count"]
        pos=[v/count for v in a["p"]]
        n=normal([v/count for v in a["n"]])
        incoming=normal([pos[i]-lamp["position"][i] for i in range(3)])
        if sum(n[i]*incoming[i] for i in range(3))>=0:
            raise ValueError("Source patch does not face original source lamp")
        tint=[min(1.,max(0.,v/count)) for v in a["rgb"]]
        rough=min(1.,max(.025,a["rough"]/count))
        power=[0.35,0.32,0.28]  # Authoring demo budget, NOT measured photon flux.
        radius=effective_radius(power,irradiance_cutoff=0.001,radius_max=3.,
                                parent_radius=6.,radius_decay=.82)
        emitters.append({
            "position":pos,"normal":n,"incident":incoming,
            "albedo":tint,"roughness":rough,"metallic":0.,
            "transmission":0.,"ior":1.5,"sigma":[0.,0.,0.],
            "thickness":0.,"power":power,"radius":radius,
            "source_node":code,"captured_samples":count,
        })
    return {"emitters":emitters,"sha256":cat["sha256"],
            "source":"WALL04 original brick COLOR_0 measured XYZ/normal/roughness, clay optical defaults",
            "nodes":list(selected)}


def real_case():
    capture=extraction()
    src=capture["emitters"][0]
    n=src["normal"]
    mirrored=normal(reflect(src["incident"],n))
    directions=[n,mirrored,normal([n[0]+.2,n[1],n[2]])]
    targets=[]
    for direction in directions:
        position=[src["position"][i]+direction[i]*0.45 for i in range(3)]
        targets.append({"position":position,"normal":[-x for x in direction],
                        "area":0.03,"visible":True})
    return {"emitters":capture["emitters"],"receivers":targets,
            "source_sha256":capture["sha256"],"source_nodes":capture["nodes"]}


def extend_reference(path=ROOT/"gpu_compute/fixtures/lie35-directional-reference.json"):
    path=Path(path)
    fixture=json.loads(path.read_text())
    if fixture.get("schema")!="lie35-angular/1":
        raise ValueError("Existing numerical oracle missing")
    case=real_case()
    rgb=propagate(case["emitters"],case["receivers"])
    case["output"]=rgb
    case["incoming_total"]=[sum(s["power"][k] for s in case["emitters"]) for k in range(3)]
    case["received_total"]=[sum(c[k] for c in rgb) for k in range(3)]
    if not any(any(v>0 for v in row) for row in rgb):
        raise AssertionError("No real captured light transfer")
    fixture["cases"]["wall04_captured_clay"]=case
    path.write_text(json.dumps(fixture,indent=2,sort_keys=True)+"\n")
    print("LIE35 REAL WALL04",json.dumps({
        "sha256":case["source_sha256"],"nodes":case["source_nodes"],
        "samples":[s["captured_samples"] for s in case["emitters"]],
        "incoming":case["incoming_total"],"transferred":case["received_total"]
    },sort_keys=True))
    return case


if __name__=="__main__":
    extend_reference()
