"""Finite inclined plane for actual GPU receiver-plane shadow validation.

The material is uniform. An isolated plane cannot cast a shadow onto itself.
No human beauty metric depends on this synthetic fixture.
"""
import hashlib
import json
import math
from pathlib import Path
import struct


def create(root):
    root.mkdir(parents=True,exist_ok=True)
    angle=math.radians(48);n=(math.sin(angle),0,math.cos(angle));t=(math.cos(angle),0,-math.sin(angle))
    vertices=[(t[0]*u,.23+v,t[2]*u) for u,v in [(-.035,-.028),(.035,-.028),(.035,.028),(-.035,.028)]]
    triangles=[(0,1,2),(0,2,3)];samples=[]
    for y in range(80):
        for x in range(80):
            u,v=(x+.5)/80,(y+.5)/80
            bary,triangle=((1-u,u-v,v),0) if v<=u else ((1-v,u,v-u),1)
            samples.append((*bary,triangle,*n,.0008,.45,.85,.7,.62,.55,0,0,.006,*n,1))
    buffers={'vertices.bin':b''.join(struct.pack('<12f',*p,0,*([0]*8)) for p in vertices),
             'triangles.bin':b''.join(struct.pack('<4I',*t,0) for t in triangles),
             'samples.bin':b''.join(struct.pack('<20f',*s) for s in samples)}
    for name,data in buffers.items():(root/name).write_bytes(data)
    manifest={'schema':1,'master_id':'lie21-finite-inclined-plane-validation','sample_count':len(samples),'vertex_count':4,'triangle_count':2,
              'buffers':{name:{'bytes':len(data),'sha256':hashlib.sha256(data).hexdigest()} for name,data in buffers.items()},
              'strides':{'sample':80,'vertex':48,'triangle':16},'original_mesh_drawn':False,
              'fixture':'Uniform finite plane, positive light-facing normal, isolated from other surfaces.'}
    (root/'master.json').write_text(json.dumps(manifest,indent=2)+'\n')


if __name__=='__main__':create(Path(__file__).resolve().parents[1]/'gpu_compute/captures/human_quality/planar-validation')
