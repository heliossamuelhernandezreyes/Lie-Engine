"""Dedicated multi-bank kernels with shared visibility and shading-only normals."""
import json
from pathlib import Path
from lie_scanned_masonry_shader import outputs as masonry_outputs
ROOT=Path(__file__).resolve().parents[1]
def outputs():
    original=masonry_outputs();result={};gd='extends RefCounted\nconst SHADERS={\n';bindings={1:[4,5,6,7,13],2:[0,1,2,3,4,5,6,7,13,14],3:[0,1,2,3,4,5,6,7,13,14],4:[1,3,4,5,6,7,8,9,11,13],6:[1,3,4,5,6,7,8,9,11,13],7:[6,11,12]}
    for stage in (1,2,3,4,6,7):
        s=original[f'gpu_compute/shaders/lie_scanned_masonry_stage_{stage}.glsl']
        if stage in (2,3):
            s=s.replace('layout(set=0,binding=0,std430)','layout(set=0,binding=14,std430) readonly buffer OpticalNormals {vec4 v[];} optical_normals;\nlayout(set=0,binding=0,std430)',1)
            s=s.replace('Sample s=samples.v[sid];Instance inst=instances.v[job.z];','Instance inst=instances.v[job.z];\n        if(int(inst.meta.y)!=int(parameters.settings.z))return;\n        Sample s=samples.v[sid];')
            s=s.replace('p.world=vec4(world,1);p.normal=vec4(n,front);','''vec3 shading=n;
            if(parameters.settings.w>.5) {vec4 optical=optical_normals.v[sid];if(optical.w>.5)shading=normalize(transpose(inverse(basis))*optical.xyz);}
            p.world=vec4(world,1);p.normal=vec4(shading,front);''')
        if stage==4:
            s=s.replace('vec3(.025)','vec3(.04)').replace('float nl=max(dot(n,l),0),nv=','float nl=dot(point.geometry.xyz,l)>0.?max(dot(n,l),0):0.,nv=')
        path=f'shaders/lie_construction_scene_stage_{stage}.glsl';result['gpu_compute/'+path]=s;gd+=f'    {stage}:preload("res://{path}"),\n'
    gd+='}\nconst BINDINGS='+json.dumps(bindings,separators=(',',':')).replace('"','')+'\n';result['gpu_compute/lie_construction_scene_kernels.gd']=gd;return result
if __name__=='__main__':
    for path,data in outputs().items():(ROOT/path).write_text(data)
